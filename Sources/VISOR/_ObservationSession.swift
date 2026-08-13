import Foundation
import os
import VISORObservation

// Empty deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated classes.

nonisolated private final class _ObservationFailureLatch: Sendable {
  private typealias Waiter = CheckedContinuation<
    Result<_ObservationSourceFailure, CancellationError>,
    Never
  >

  private struct State: Sendable {
    var failure: _ObservationSourceFailure?
    var isFinished = false
    var waiters: [UUID: Waiter] = [:]
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  func wait() async throws -> _ObservationSourceFailure {
    let id = UUID()
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let immediate = lock.withLock {
          state -> Result<_ObservationSourceFailure, CancellationError>? in
          if let failure = state.failure {
            return .success(failure)
          }
          if state.isFinished || Task.isCancelled {
            return .failure(CancellationError())
          }
          state.waiters[id] = continuation
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      let continuation = lock.withLock { state in
        state.waiters.removeValue(forKey: id)
      }
      continuation?.resume(returning: .failure(CancellationError()))
    }
    return try result.get()
  }

  func latch(_ failure: _ObservationSourceFailure) {
    let waiters: [Waiter] = lock.withLock { state in
      guard state.failure == nil, !state.isFinished else {
        return [Waiter]()
      }
      state.failure = failure
      let waiters = Array(state.waiters.values)
      state.waiters.removeAll(keepingCapacity: false)
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: .success(failure))
    }
  }

  func finish() {
    let waiters: [Waiter] = lock.withLock { state in
      guard !state.isFinished else { return [Waiter]() }
      state.isFinished = true
      let waiters = Array(state.waiters.values)
      state.waiters.removeAll(keepingCapacity: false)
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: .failure(CancellationError()))
    }
  }
}

@MainActor
private final class _ObservationHandlerInvocation {
  let sessionID: UUID?
  let laneID: UUID?
  private(set) var isActive = true

  init(sessionID: UUID?, laneID: UUID?) {
    self.sessionID = sessionID
    self.laneID = laneID
  }

  deinit {}

  func finish() {
    isActive = false
  }
}

nonisolated private enum _ObservationHandlerExecution {
  @TaskLocal static var currentInvocation: _ObservationHandlerInvocation?

  @MainActor
  static func withHandler(
    sessionID: UUID?,
    laneID: UUID? = nil,
    operation: @MainActor () async -> Void
  ) async {
    let invocation = _ObservationHandlerInvocation(
      sessionID: sessionID,
      laneID: laneID)
    await Self.$currentInvocation.withValue(invocation) {
      await operation()
    }
    // An awaited child inherits the active invocation and cannot self-join.
    // A fire-and-forget child may retain the token, but no longer represents
    // handler execution once the handler itself has returned.
    invocation.finish()
  }
}

@MainActor
package final class _ObservationLane<Value: Sendable> {
  package typealias Handler = @MainActor @Sendable (Value) async -> Void

  private enum Lifecycle {
    case idle
    case prepared
    case projected
    case initialised
    case active
    case ended
  }

  fileprivate let source: ObservationSource<Value>
  private let projections: [Handler]
  private let reactions: [Handler]
  private var lifecycle = Lifecycle.idle
  private var subscription: _ObservationSubscription<Value>?
  private var worker: Task<Void, any Error>?
  private var sessionID: UUID?
  private let handlerExecutionID = UUID()

  package init(
    source: ObservationSource<Value>,
    handlers: [Handler],
    initialReactions: [Handler] = []
  ) {
    self.source = source
    projections = handlers
    reactions = initialReactions
  }

  deinit {}

  package func _visorErase() -> _AnyObservationLane {
    _AnyObservationLane(
      source: source._visorErase(),
      adopt: { [self] prepared, sessionID in
        let observation = try prepared._visorUnwrap(as: Value.self)
        return _AnyPreparedObservationLane(
          try adopt(observation, sessionID: sessionID))
      })
  }

  package func _visorPrepare() throws -> _PreparedLane<Value> {
    try adopt(source._visorPrepareOpen(), sessionID: nil)
  }

  fileprivate func adopt(
    _ observation: _PreparedObservation<Value>,
    sessionID: UUID?
  ) throws -> _PreparedLane<Value> {
    guard lifecycle == .idle, subscription == nil else {
      observation._visorCancel()
      throw _ObservationSourceFailure.protocolViolation(
        "An observation lane can prepare once per generation")
    }

    let opened = observation._visorActivate()
    self.sessionID = sessionID
    subscription = opened.subscription
    lifecycle = .prepared
    return _PreparedLane(
      lane: self,
      observation: observation,
      opened: opened)
  }

  fileprivate func applyProjection(
    _ envelope: _ObservationEnvelope<Value>
  ) async throws {
    guard lifecycle == .prepared else {
      throw _ObservationSourceFailure.protocolViolation(
        "A prepared lane can project one startup target")
    }

    do {
      try Task.checkCancellation()
      for projection in projections {
        await _ObservationHandlerExecution.withHandler(
          sessionID: sessionID,
          laneID: handlerExecutionID
        ) {
          await projection(envelope.snapshot)
        }
        try Task.checkCancellation()
      }
      guard lifecycle == .prepared else {
        throw CancellationError()
      }
      lifecycle = .projected
    } catch {
      signalCancellation()
      throw error
    }
  }

  fileprivate func applyInitialReactionsAndAcknowledge(
    _ envelope: _ObservationEnvelope<Value>
  ) async throws {
    guard lifecycle == .projected, let subscription else {
      throw _ObservationSourceFailure.protocolViolation(
        "A projected lane can run its initial reactions once")
    }

    do {
      try Task.checkCancellation()
      for reaction in reactions {
        await _ObservationHandlerExecution.withHandler(
          sessionID: sessionID,
          laneID: handlerExecutionID
        ) {
          await reaction(envelope.snapshot)
        }
        try Task.checkCancellation()
      }
      guard lifecycle == .projected else {
        throw CancellationError()
      }
      try subscription._visorAcknowledge(envelope)
      lifecycle = .initialised
    } catch {
      signalCancellation()
      throw error
    }
  }

  fileprivate func apply(
    _ envelope: _ObservationEnvelope<Value>
  ) async throws {
    try await applyProjection(envelope)
    try await applyInitialReactionsAndAcknowledge(envelope)
  }

  fileprivate func startWorker(
    reportingFailure: @escaping @MainActor @Sendable
      (_ObservationSourceFailure) -> Void = { _ in }
  ) throws {
    guard lifecycle == .initialised,
          worker == nil,
          let subscription
    else {
      throw _ObservationSourceFailure.protocolViolation(
        "An observation lane starts after exactly one startup target")
    }

    let handlerSessionID = sessionID
    let handlerLaneID = handlerExecutionID
    worker = Task {
      @MainActor [projections, reactions, handlerSessionID, handlerLaneID] in
      do {
        while let envelope = try await subscription._visorNext() {
          try Task.checkCancellation()
          for projection in projections {
            await _ObservationHandlerExecution.withHandler(
              sessionID: handlerSessionID,
              laneID: handlerLaneID
            ) {
              await projection(envelope.snapshot)
            }
            try Task.checkCancellation()
          }
          for reaction in reactions {
            await _ObservationHandlerExecution.withHandler(
              sessionID: handlerSessionID,
              laneID: handlerLaneID
            ) {
              await reaction(envelope.snapshot)
            }
            try Task.checkCancellation()
          }
          try subscription._visorAcknowledge(envelope)
        }
        if !Task.isCancelled {
          reportingFailure(.unexpectedTermination)
        }
      } catch is CancellationError {
        // Owner teardown is the ordinary termination path.
      } catch let failure as _ObservationSourceFailure {
        reportingFailure(failure)
      } catch {
        reportingFailure(.failed(String(describing: error)))
      }
    }
    lifecycle = .active
  }

  fileprivate func signalCancellation() {
    worker?.cancel()
    subscription?._visorCancel()
    lifecycle = .ended
  }

  fileprivate func join() async {
    if let worker {
      _ = await worker.result
    }
    worker = nil
    subscription = nil
    lifecycle = .ended
  }

  fileprivate func cancelPreparation() {
    guard lifecycle == .prepared
      || lifecycle == .projected
      || lifecycle == .initialised
    else { return }
    signalCancellation()
  }

  package func _visorCheckpointAndPause() async throws
    -> _ObservationCheckpoint<Value>
  {
    guard !isExecutingHandler else {
      throw _ObservationSourceFailure.protocolViolation(
        "An observation handler cannot checkpoint its own lane")
    }
    guard lifecycle == .active, let subscription else {
      throw _ObservationSourceFailure.protocolViolation(
        "The observation lane has not started")
    }
    do {
      try Task.checkCancellation()
      let checkpoint = try subscription._visorCheckpointAndPause()
      try await subscription._visorWaitUntilAcknowledged(checkpoint)
      return checkpoint
    } catch {
      signalCancellation()
      await join()
      throw error
    }
  }

  package func _visorResume(
    after checkpoint: _ObservationCheckpoint<Value>
  ) throws {
    guard lifecycle == .active, let subscription else {
      throw _ObservationSourceFailure.protocolViolation(
        "The observation lane has not started")
    }
    try subscription._visorResume(after: checkpoint)
  }

  package func _visorCancelAndJoin() async {
    signalCancellation()
    // Joining here would make a handler wait for the worker or startup task
    // that is currently awaiting that same handler. Cancellation is already
    // visible synchronously; an owner outside the handler can join later.
    guard !isExecutingHandler else { return }
    await join()
  }

  private var isExecutingHandler: Bool {
    guard let invocation = _ObservationHandlerExecution.currentInvocation else {
      return false
    }
    return invocation.isActive && invocation.laneID == handlerExecutionID
  }
}

@MainActor
package final class _PreparedLane<Value: Sendable> {
  private enum Phase {
    case pending
    case projected
    case initialised
    case active
    case cancelled
  }

  private let lane: _ObservationLane<Value>
  private let observation: _PreparedObservation<Value>
  private let opened: _OpenObservation<Value>
  private var phase = Phase.pending
  private var startupEnvelope: _ObservationEnvelope<Value>?

  fileprivate init(
    lane: _ObservationLane<Value>,
    observation: _PreparedObservation<Value>,
    opened: _OpenObservation<Value>
  ) {
    self.lane = lane
    self.observation = observation
    self.opened = opened
  }

  package var baseline: Value {
    observation.baseline.snapshot
  }

  fileprivate var erasedSubscription: _AnyObservationSubscription {
    opened.subscription._visorErase()
  }

  package func _visorApply(
    _ checkpoint: _AnyObservationCheckpoint
  ) async throws {
    try await _visorApplyProjection(checkpoint)
    try await _visorApplyInitialReactions()
  }

  package func _visorApplyProjection(
    _ checkpoint: _AnyObservationCheckpoint
  ) async throws {
    guard phase == .pending else {
      throw _ObservationSourceFailure.protocolViolation(
        "A prepared lane projects one startup target")
    }
    let typedCheckpoint = try checkpoint._visorUnwrap(as: Value.self)
    let envelope = try opened.subscription
      ._visorClaimForDirectReconciliation(typedCheckpoint)
    do {
      try await lane.applyProjection(envelope)
      startupEnvelope = envelope
      phase = .projected
    } catch {
      phase = .cancelled
      observation._visorCancel()
      throw error
    }
  }

  package func _visorApplyInitialReactions() async throws {
    guard phase == .projected, let startupEnvelope else {
      throw _ObservationSourceFailure.protocolViolation(
        "A projected lane runs its initial reactions once")
    }
    do {
      try await lane.applyInitialReactionsAndAcknowledge(startupEnvelope)
      self.startupEnvelope = nil
      phase = .initialised
    } catch {
      self.startupEnvelope = nil
      phase = .cancelled
      observation._visorCancel()
      throw error
    }
  }

  package func _visorStartWorker(
    reportingFailure: @escaping @MainActor @Sendable
      (_ObservationSourceFailure) -> Void = { _ in }
  ) throws {
    guard phase == .initialised else {
      throw _ObservationSourceFailure.protocolViolation(
        "A prepared lane starts after its startup target")
    }
    try lane.startWorker(reportingFailure: reportingFailure)
    phase = .active
  }

  /// Compatibility spelling for the earlier single-lane proof.
  package func _visorActivate() async throws {
    guard phase == .pending else {
      throw _ObservationSourceFailure.protocolViolation(
        "A prepared observation lane can activate once")
    }
    do {
      try await lane.apply(opened.baseline)
      phase = .initialised
      try lane.startWorker()
      phase = .active
    } catch {
      phase = .cancelled
      observation._visorCancel()
      throw error
    }
  }

  package func _visorCancel() {
    guard phase != .cancelled else { return }
    phase = .cancelled
    observation._visorCancel()
    lane.cancelPreparation()
  }

  fileprivate func signalCancellation() {
    phase = .cancelled
    lane.signalCancellation()
  }

  fileprivate func join() async {
    await lane.join()
  }

  deinit {
    switch phase {
    case .pending, .projected, .initialised:
      observation._visorCancel()
    case .active, .cancelled:
      break
    }
  }
}

@MainActor
package final class _AnyObservationLane {
  package let source: _AnyObservationSource
  private let adoptOperation:
    @MainActor (_AnyPreparedObservation, UUID) throws
      -> _AnyPreparedObservationLane

  fileprivate init(
    source: _AnyObservationSource,
    adopt: @escaping @MainActor (_AnyPreparedObservation, UUID) throws
      -> _AnyPreparedObservationLane
  ) {
    self.source = source
    adoptOperation = adopt
  }

  deinit {}

  fileprivate func adopt(
    _ observation: _AnyPreparedObservation,
    sessionID: UUID
  ) throws -> _AnyPreparedObservationLane {
    try adoptOperation(observation, sessionID)
  }
}

@MainActor
package final class _AnyPreparedObservationLane {
  private let subscriptionOperation:
    @MainActor () -> _AnyObservationSubscription
  private let applyOperation:
    @MainActor (_AnyObservationCheckpoint) async throws -> Void
  private let applyProjectionOperation:
    @MainActor (_AnyObservationCheckpoint) async throws -> Void
  private let applyInitialReactionsOperation:
    @MainActor () async throws -> Void
  private let startOperation:
    @MainActor (@escaping @MainActor @Sendable
      (_ObservationSourceFailure) -> Void) throws -> Void
  private let cancelOperation: @MainActor () -> Void
  private let joinOperation: @MainActor () async -> Void

  fileprivate init<Value: Sendable>(_ lane: _PreparedLane<Value>) {
    subscriptionOperation = { lane.erasedSubscription }
    applyOperation = { try await lane._visorApply($0) }
    applyProjectionOperation = { try await lane._visorApplyProjection($0) }
    applyInitialReactionsOperation = {
      try await lane._visorApplyInitialReactions()
    }
    startOperation = { try lane._visorStartWorker(reportingFailure: $0) }
    cancelOperation = { lane.signalCancellation() }
    joinOperation = { await lane.join() }
  }

  deinit {}

  fileprivate var subscription: _AnyObservationSubscription {
    subscriptionOperation()
  }

  fileprivate func apply(
    _ checkpoint: _AnyObservationCheckpoint
  ) async throws {
    try await applyOperation(checkpoint)
  }

  fileprivate func applyProjection(
    _ checkpoint: _AnyObservationCheckpoint
  ) async throws {
    try await applyProjectionOperation(checkpoint)
  }

  fileprivate func applyInitialReactions() async throws {
    try await applyInitialReactionsOperation()
  }

  fileprivate func start(
    reportingFailure: @escaping @MainActor @Sendable
      (_ObservationSourceFailure) -> Void
  ) throws {
    try startOperation(reportingFailure)
  }

  fileprivate func cancel() {
    cancelOperation()
  }

  fileprivate func join() async {
    await joinOperation()
  }
}

@MainActor
package final class _ObservationSession {
  private static let deadlineDiagnosticSourceLimit = 8

  private enum Lifecycle {
    case idle
    case starting
    case ready
    case paused(UUID)
    case stopping
    case stopped
  }

  private let recipes: [_AnyObservationLane]
  private let beforeReady: @MainActor @Sendable () async -> Void
  private let afterStartupHandoff: @MainActor @Sendable () async -> Void
  private let beforePauseCheckpoint: @MainActor @Sendable () -> Void
  private let afterPauseCheckpoint: @MainActor @Sendable () -> Void
  private let beforePauseDrain: @MainActor @Sendable () async -> Void
  private let beforePauseOperation: @MainActor @Sendable () async -> Void
  private let onFailure:
    @MainActor @Sendable (_ObservationSourceFailure) -> Void
  let deadlinePolicy: _ObservationDeadlinePolicy
  private let failureLatch = _ObservationFailureLatch()
  private let handlerExecutionID = UUID()
  private var lifecycle = Lifecycle.idle
  private var lanes: [_AnyPreparedObservationLane] = []
  var failure: _ObservationSourceFailure?
  private var hasReservedControlOperation = false
  private var activeControlTask: Task<Void, Never>?
  private var activeControlTaskID: UUID?
  private var teardownTask: Task<Void, Never>?
  var teardownDeadlineCoordinator: _ObservationTeardownDeadlineCoordinator?
  var teardownDeadlineWatchdog: Task<Void, Never>?
  private var stoppedCallbacks: [@MainActor @Sendable () -> Void] = []
  private var hasExceededTeardownDeadline = false

  package init(
    lanes: [_AnyObservationLane],
    _visorBeforeReady: @escaping @MainActor @Sendable () async -> Void = {},
    _visorAfterStartupHandoff:
      @escaping @MainActor @Sendable () async -> Void = {},
    _visorBeforePauseCheckpoint:
      @escaping @MainActor @Sendable () -> Void = {},
    _visorAfterPauseCheckpoint:
      @escaping @MainActor @Sendable () -> Void = {},
    _visorBeforePauseDrain: @escaping @MainActor @Sendable () async -> Void = {},
    _visorBeforePauseOperation: @escaping @MainActor @Sendable () async -> Void = {},
    _visorOnFailure:
      @escaping @MainActor @Sendable
        (_ObservationSourceFailure) -> Void = { _ in },
    _visorDeadlinePolicy: _ObservationDeadlinePolicy = .production
  ) {
    recipes = lanes
    beforeReady = _visorBeforeReady
    afterStartupHandoff = _visorAfterStartupHandoff
    beforePauseCheckpoint = _visorBeforePauseCheckpoint
    afterPauseCheckpoint = _visorAfterPauseCheckpoint
    beforePauseDrain = _visorBeforePauseDrain
    beforePauseOperation = _visorBeforePauseOperation
    onFailure = _visorOnFailure
    deadlinePolicy = _visorDeadlinePolicy
  }

  package convenience init(
    recipes: [_ObservationRecipe],
    _visorBeforePauseDrain: @escaping @MainActor @Sendable () async -> Void = {},
    _visorOnFailure:
      @escaping @MainActor @Sendable
        (_ObservationSourceFailure) -> Void = { _ in },
    _visorDeadlinePolicy: _ObservationDeadlinePolicy = .production
  ) {
    self.init(
      lanes: recipes.map { $0._visorMakeLane() },
      _visorBeforePauseDrain: _visorBeforePauseDrain,
      _visorOnFailure: _visorOnFailure,
      _visorDeadlinePolicy: _visorDeadlinePolicy)
  }

  deinit {}

  package var _visorIsReady: Bool {
    if case .ready = lifecycle { return true }
    return false
  }

  package var _visorFailure: _ObservationSourceFailure? {
    failure
  }

  package var _visorIsStopped: Bool {
    if case .stopped = lifecycle { return true }
    return false
  }

  package var _visorIsStopping: Bool {
    if case .stopping = lifecycle { return true }
    return false
  }

  package func _visorWhenStopped(
    _ callback: @escaping @MainActor @Sendable () -> Void
  ) {
    if case .stopped = lifecycle {
      callback()
      return
    }
    stoppedCallbacks.append(callback)
  }

  package func _visorWaitForFailure() async throws -> _ObservationSourceFailure {
    guard !isExecutingHandler else {
      throw _ObservationSourceFailure.protocolViolation(
        "An observation handler cannot wait for its own session to fail")
    }
    return try await failureLatch.wait()
  }

  package func _visorStart() async throws {
    guard case .idle = lifecycle else {
      throw _ObservationSourceFailure.protocolViolation(
        "An observation session starts once per generation")
    }
    guard !hasReservedControlOperation else {
      throw _ObservationSourceFailure.protocolViolation(
        "An observation session runs one control operation at a time")
    }
    hasReservedControlOperation = true
    defer { hasReservedControlOperation = false }
    lifecycle = .starting

    switch await runWithDeadline(
      phase: .readiness,
      operation: { [self] in
        try await runStartup()
        await afterStartupHandoff()
        try Task.checkCancellation()
        // A worker may fail after runStartup marks the session ready but before
        // this task resumes from its final hand-off. Revalidate before exposing
        // readiness to the owner.
        try validateStartupHandoff()
      })
    {
    case .success:
      return

    case .cancelled:
      let teardown = beginTeardown()
      _ = await awaitTeardownWithinDeadline(teardown)
      throw CancellationError()

    case .failure(let startupFailure):
      let teardown = beginTeardown(failure: startupFailure)
      _ = await awaitTeardownWithinDeadline(teardown)
      throw failure ?? startupFailure
    }
  }

  private func validateStartupHandoff() throws {
    if let failure {
      throw failure
    }
    guard case .ready = lifecycle else {
      if case .stopping = lifecycle {
        throw CancellationError()
      }
      if case .stopped = lifecycle {
        throw CancellationError()
      }
      throw _ObservationSourceFailure.protocolViolation(
        "The session changed lifecycle before startup returned")
    }
  }

  private func runStartup() async throws {
    let observations = try _ObservationRuntime._visorPrepareAll(
      recipes.map(\.source))

    var adopted: [_AnyPreparedObservationLane] = []
    do {
      try Task.checkCancellation()
      for (recipe, observation) in zip(recipes, observations) {
        try Task.checkCancellation()
        adopted.append(
          try recipe.adopt(
            observation,
            sessionID: handlerExecutionID))
      }
    } catch {
      for lane in adopted.reversed() {
        lane.cancel()
      }
      for observation in observations.dropFirst(adopted.count) {
        observation._visorCancel()
      }
      throw error
    }
    lanes = adopted

    let checkpoints = try _ObservationRuntime
      ._visorCheckpointAndPauseAll(adopted.map(\.subscription))
    for (lane, checkpoint) in zip(adopted, checkpoints) {
      try Task.checkCancellation()
      try await lane.applyProjection(checkpoint)
    }
    for lane in adopted {
      try Task.checkCancellation()
      try await lane.applyInitialReactions()
    }
    try await _ObservationRuntime
      ._visorWaitUntilAcknowledgedAll(checkpoints)
    try Task.checkCancellation()
    if let failure {
      throw failure
    }
    guard case .starting = lifecycle else {
      if case .stopping = lifecycle {
        throw CancellationError()
      }
      if case .stopped = lifecycle {
        throw CancellationError()
      }
      throw _ObservationSourceFailure.protocolViolation(
        "The session stopped before readiness completed")
    }
    try _ObservationRuntime._visorResumeAll(after: checkpoints)
    for lane in adopted {
      try Task.checkCancellation()
      try lane.start { [weak self] failure in
        self?.workerFailed(failure)
      }
    }
    await _ObservationHandlerExecution.withHandler(
      sessionID: handlerExecutionID
    ) {
      await beforeReady()
    }
    try Task.checkCancellation()
    lifecycle = .ready
  }

  package func _visorWithPause<Result>(
    _ operation: @MainActor () throws -> Result,
    _visorPhase: _ObservationDeadlinePhase = .fence
  ) async throws -> Result {
    guard !isExecutingHandler else {
      throw _ObservationSourceFailure.protocolViolation(
        "An observation handler cannot pause its own session")
    }
    guard !hasReservedControlOperation else {
      throw _ObservationSourceFailure.protocolViolation(
        "An observation session runs one control operation at a time")
    }
    hasReservedControlOperation = true
    defer { hasReservedControlOperation = false }

    let paused: (id: UUID, checkpoints: [_AnyObservationCheckpoint])
    switch await runWithDeadline(
      phase: _visorPhase,
      synchronousPreparation: { [self] deadlineHasResolved in
        // Checkpoint synchronously in the caller's MainActor turn. Deferring
        // this cut into the operation Task would let another source drain
        // between the fence request and its first suspension. The deadline
        // race and off-actor watchdog are already active at this point.
        try preparePause(deadlineHasResolved: deadlineHasResolved)
      },
      operation: { [self] prepared in
        try await drainPreparedPause(prepared)
      })
    {
    case .success(let value):
      paused = value
    case .cancelled:
      let teardown = beginTeardown()
      _ = await awaitTeardownWithinDeadline(teardown)
      throw CancellationError()
    case .failure(let pauseFailure):
      let teardown = beginTeardown(failure: pauseFailure)
      _ = await awaitTeardownWithinDeadline(teardown)
      throw failure ?? pauseFailure
    }

    let (id, checkpoints) = paused
    do {
      await beforePauseOperation()
      try Task.checkCancellation()
      try validateActivePause(id: id)
      let result = try operation()
      try Task.checkCancellation()
      try await resume(id: id, checkpoints: checkpoints)
      return result
    } catch {
      let primary = failure ?? (error as? _ObservationSourceFailure)
      let teardown = beginTeardown(failure: primary)
      _ = await awaitTeardownWithinDeadline(teardown)
      throw failure ?? error
    }
  }

  private func preparePause(
    deadlineHasResolved: @Sendable () -> Bool
  ) throws
    -> (id: UUID, checkpoints: [_AnyObservationCheckpoint])
  {
    try Task.checkCancellation()
    guard !deadlineHasResolved() else {
      throw _ObservationDeadlinePreparationAborted()
    }
    guard case .ready = lifecycle else {
      throw _ObservationSourceFailure.protocolViolation(
        "A ready observation session can begin one pause")
    }
    let id = UUID()
    lifecycle = .paused(id)

    beforePauseCheckpoint()
    try Task.checkCancellation()
    // Expiry that wins while synchronous preparation is deliberately blocked
    // fails closed without touching the source checkpoint frontier. If this
    // check wins first, the checkpoint cut is the linearised control-plane
    // event and any later expiry still tears the session down.
    guard !deadlineHasResolved() else {
      throw _ObservationDeadlinePreparationAborted()
    }
    let checkpoints = try _ObservationRuntime
      ._visorCheckpointAndPauseAll(lanes.map(\.subscription))
    afterPauseCheckpoint()
    return (id, checkpoints)
  }

  private func drainPreparedPause(
    _ prepared: (id: UUID, checkpoints: [_AnyObservationCheckpoint])
  ) async throws -> (id: UUID, checkpoints: [_AnyObservationCheckpoint]) {
    let (id, checkpoints) = prepared
    await beforePauseDrain()
    try Task.checkCancellation()
    try await _ObservationRuntime
      ._visorWaitUntilAcknowledgedAll(checkpoints)
    try Task.checkCancellation()
    if let failure {
      throw failure
    }
    guard case .paused(let currentID) = lifecycle, currentID == id else {
      if case .stopping = lifecycle {
        throw CancellationError()
      }
      if case .stopped = lifecycle {
        throw CancellationError()
      }
      throw _ObservationSourceFailure.protocolViolation(
        "The session stopped while its pause was draining")
    }
    return (id, checkpoints)
  }

  private func resume(
    id: UUID,
    checkpoints: [_AnyObservationCheckpoint]
  ) async throws {
    guard case .paused(let currentID) = lifecycle, currentID == id else {
      if case .stopping = lifecycle {
        throw CancellationError()
      }
      if case .stopped = lifecycle {
        throw CancellationError()
      }
      throw _ObservationSourceFailure.protocolViolation(
        "A session pause can resume once in its generation")
    }
    do {
      try _ObservationRuntime._visorResumeAll(after: checkpoints)
      lifecycle = .ready
    } catch {
      let primary = failure ?? (error as? _ObservationSourceFailure)
      let teardown = beginTeardown(failure: primary)
      _ = await awaitTeardownWithinDeadline(teardown)
      throw failure ?? error
    }
  }

  private func validateActivePause(id: UUID) throws {
    guard case .paused(let currentID) = lifecycle, currentID == id else {
      if case .stopping = lifecycle {
        throw CancellationError()
      }
      if case .stopped = lifecycle {
        throw CancellationError()
      }
      throw _ObservationSourceFailure.protocolViolation(
        "A session pause remains active through its scoped operation")
    }
  }

  package func _visorStop() async {
    _ = await _visorStopWithinDeadline()
  }

  package func _visorStopWithinDeadline() async -> Bool {
    if case .stopped = lifecycle { return true }
    let teardown = beginTeardown()
    // Joining here would make a handler wait for the worker or startup task
    // that is currently awaiting that same handler. The request is already
    // visible synchronously through `.stopping`; its owner can join later.
    guard !isExecutingHandler else { return false }
    guard !hasExceededTeardownDeadline else { return false }
    return await awaitTeardownWithinDeadline(teardown)
  }

  /// Synchronously makes cancellation visible before an owner awaits joined
  /// teardown. This remains package-only lifecycle machinery.
  package func _visorRequestStop() {
    _ = beginTeardown()
  }

  private var isExecutingHandler: Bool {
    guard let invocation = _ObservationHandlerExecution.currentInvocation else {
      return false
    }
    return invocation.isActive && invocation.sessionID == handlerExecutionID
  }

  private func workerFailed(_ failure: _ObservationSourceFailure) {
    controlPlaneFailed(failure)
  }

  @discardableResult
  func beginTeardownForDeadlineSupport() -> Task<Void, Never> {
    beginTeardown()
  }

  func installControlTask(
    _ task: Task<Void, Never>,
    id: UUID
  ) {
    precondition(activeControlTask == nil)
    activeControlTask = task
    activeControlTaskID = id
  }

  func clearControlTask(id: UUID) {
    guard activeControlTaskID == id else { return }
    activeControlTask = nil
    activeControlTaskID = nil
  }

  func deadlineFailure(
    for phase: _ObservationDeadlinePhase
  ) -> _ObservationSourceFailure {
    let allSourceIDs = recipes.map { $0.source.sourceID }
    let sourceIDs = Array(
      allSourceIDs.prefix(Self.deadlineDiagnosticSourceLimit))
    return .safetyDeadlineExceeded(
      phase: phase.diagnosticName,
      sourceIDs: sourceIDs,
      omittedSourceCount: allSourceIDs.count - sourceIDs.count)
  }

  func deadlineDidFire(phase: _ObservationDeadlinePhase) {
    if phase == .teardownJoin {
      hasExceededTeardownDeadline = true
    }
    controlPlaneFailed(deadlineFailure(for: phase))
  }

  func markTeardownDeadlineWaitEnded() {
    hasExceededTeardownDeadline = true
  }

  func finishTeardownDeadlineWait(
    _ coordinator: _ObservationTeardownDeadlineCoordinator
  ) {
    guard teardownDeadlineCoordinator === coordinator else { return }
    teardownDeadlineWatchdog?.cancel()
    teardownDeadlineWatchdog = nil
    teardownDeadlineCoordinator = nil
  }

  package func controlPlaneFailed(_ failure: _ObservationSourceFailure) {
    guard self.failure == nil, !self._visorIsStopped else { return }
    // Latch the cause, revoke the lifecycle and request cancellation before
    // invoking arbitrary owner code. A synchronous re-entrant failure then
    // observes this first cause and cannot replace or report it twice.
    _ = beginTeardown(failure: failure)
    onFailure(failure)
  }

  private func beginTeardown(
    failure newFailure: _ObservationSourceFailure? = nil
  ) -> Task<Void, Never> {
    if case .stopped = lifecycle {
      return Task { @MainActor in }
    }
    if let newFailure, failure == nil {
      failure = newFailure
      failureLatch.latch(newFailure)
    }
    if let teardownTask {
      return teardownTask
    }

    lifecycle = .stopping
    activeControlTask?.cancel()
    for lane in lanes {
      lane.cancel()
    }

    let control = activeControlTask
    let controlID = activeControlTaskID
    let adopted = lanes
    let teardown = Task { @MainActor [self] in
      if let control {
        await control.value
      }
      for lane in adopted {
        await lane.join()
      }
      if self.activeControlTaskID == controlID {
        self.activeControlTask = nil
        self.activeControlTaskID = nil
      }
      self.lanes.removeAll(keepingCapacity: false)
      self.lifecycle = .stopped
      self.failureLatch.finish()
      self.teardownTask = nil
      let callbacks = self.stoppedCallbacks
      self.stoppedCallbacks.removeAll(keepingCapacity: false)
      for callback in callbacks {
        callback()
      }
    }
    teardownTask = teardown
    return teardown
  }

}
