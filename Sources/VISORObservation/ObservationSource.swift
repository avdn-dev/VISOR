import Foundation
import os

nonisolated package struct _ObservationGroupID: Hashable, Sendable {
  fileprivate let rawValue: UUID
}

nonisolated fileprivate final class _ObservationGroupCore: Sendable {
  fileprivate let id = _ObservationGroupID(rawValue: UUID())
  private let lock = OSAllocatedUnfairLock(initialState: ())

  fileprivate func withLock<Result: Sendable>(
    _ body: @Sendable () throws -> Result
  ) rethrows -> Result {
    try lock.withLock { _ in try body() }
  }
}

/// A stable, read-only latest-State capability.
///
/// Published snapshots must retain stable contents after publication. The
/// runtime does not deep-copy values or diagnose transitive mutable aliases.
nonisolated public struct ObservationSource<Value: Sendable>: Sendable {
  fileprivate let core: _ObservationCore<Value>

  fileprivate init(core: _ObservationCore<Value>) {
    self.core = core
  }

  public func currentSnapshot() -> Value {
    core.currentSnapshot()
  }

  package var _visorIdentity: _ObservationSourceID {
    core.sourceID
  }

  package var _visorGroupIdentity: _ObservationGroupID {
    core.group.id
  }

  package var _visorActiveSubscriptionCount: Int {
    core.activeSubscriptionCount()
  }

  /// Generated control-plane code opens synchronously. Registration and the
  /// baseline read occur in one critical section, leaving no suspension gap.
  package func _visorOpen() throws -> _OpenObservation<Value> {
    try core.open()
  }

  package func _visorPrepareOpen() throws -> _PreparedObservation<Value> {
    try core.prepareOpen()
  }

  package func _visorErase() -> _AnyObservationSource {
    _AnyObservationSource(
      sourceID: core.sourceID,
      group: core.group,
      validatePrepareLocked: {
        try core.validateOpenAssumingGroupLocked()
      },
      prepareLocked: {
        _AnyPreparedObservation(
          try core.prepareOpenAssumingGroupLocked())
      })
  }
}

/// A producer-owned latest-State channel.
///
/// `Value: Sendable` protects isolation transfer, but cannot prove transitive
/// value semantics. Producers must publish stable full snapshots.
nonisolated public final class ObservationChannel<Value: Sendable>: Sendable {
  private let core: _ObservationCore<Value>
  public let source: ObservationSource<Value>

  public init(_ initialSnapshot: sending Value) {
    let core = _ObservationCore(
      initialSnapshot,
      group: _ObservationGroupCore())
    self.core = core
    source = ObservationSource(core: core)
  }

  /// Creates another performance lane in the anchor channel's immutable
  /// producer checkpoint group without introducing a third public concept.
  public init<Anchor: Sendable>(
    _ initialSnapshot: sending Value,
    groupedWith anchor: ObservationChannel<Anchor>
  ) {
    let core = _ObservationCore(
      initialSnapshot,
      group: anchor.core.group)
    self.core = core
    source = ObservationSource(core: core)
  }

  /// Publication is deliberately synchronous. An actor service can mutate its
  /// domain state and publish the matching snapshot in the same actor turn.
  public func publish(_ snapshot: sending Value) {
    core.publish(snapshot)
  }

  package func _visorTerminate(
    with failure: _ObservationSourceFailure = .unexpectedTermination
  ) {
    core.terminate(with: failure)
  }
}

// MARK: - Generated runtime control plane

nonisolated package enum _ObservationSourceFailure:
  Error,
  Equatable,
  Sendable
{
  case unexpectedTermination
  case failed(String)
  case revisionExhausted
  case protocolViolation(String)
  case safetyDeadlineExceeded(
    phase: String,
    sourceIDs: [_ObservationSourceID],
    omittedSourceCount: Int)
}

nonisolated package struct _ObservationSourceID: Hashable, Sendable {
  fileprivate let rawValue: UUID
}

nonisolated package struct _ObservationEpoch: Hashable, Sendable {
  fileprivate let rawValue: UUID
}

nonisolated package struct _ObservationEnvelope<Value: Sendable>: Sendable {
  public let sourceID: _ObservationSourceID
  public let epoch: _ObservationEpoch
  public let revision: UInt64
  public let snapshot: Value
}

nonisolated package struct _ObservationCheckpoint<Value: Sendable>: Sendable {
  fileprivate let subscriptionID: UUID
  public let envelope: _ObservationEnvelope<Value>
}

nonisolated package struct _OpenObservation<Value: Sendable>: Sendable {
  public let baseline: _ObservationEnvelope<Value>
  public let subscription: _ObservationSubscription<Value>
}

nonisolated package struct _PreparedObservation<Value: Sendable>: Sendable {
  fileprivate let openObservation: _OpenObservation<Value>

  public var baseline: _ObservationEnvelope<Value> {
    openObservation.baseline
  }

  public func _visorActivate() -> _OpenObservation<Value> {
    openObservation
  }

  public func _visorCancel() {
    openObservation.subscription._visorCancel()
  }
}

nonisolated package struct _ObservationSubscription<Value: Sendable>: Sendable {
  fileprivate let id: UUID
  fileprivate let core: _ObservationCore<Value>

  public func _visorNext() async throws -> _ObservationEnvelope<Value>? {
    try await core.next(for: id)
  }

  public func _visorAcknowledge(
    _ envelope: _ObservationEnvelope<Value>
  ) throws {
    try core.acknowledge(envelope, for: id)
  }

  public func _visorCheckpointAndPause() throws -> _ObservationCheckpoint<Value> {
    try core.checkpointAndPause(id: id)
  }

  public func _visorWaitUntilAcknowledged(
    _ checkpoint: _ObservationCheckpoint<Value>
  ) async throws {
    try await core.waitUntilAcknowledged(checkpoint, for: id)
  }

  public func _visorClaimForDirectReconciliation(
    _ checkpoint: _ObservationCheckpoint<Value>
  ) throws -> _ObservationEnvelope<Value> {
    try core.claimForDirectReconciliation(checkpoint, for: id)
  }

  public func _visorResume(
    after checkpoint: _ObservationCheckpoint<Value>
  ) throws {
    try core.resume(after: checkpoint, for: id)
  }

  public func _visorCancel() {
    core.cancel(id: id)
  }

  public func _visorErase() -> _AnyObservationSubscription {
    _AnyObservationSubscription(self)
  }
}

nonisolated fileprivate protocol _PreparedObservationStorage: Sendable {}

nonisolated fileprivate struct _PreparedObservationBox<Value: Sendable>:
  _PreparedObservationStorage,
  Sendable
{
  let observation: _PreparedObservation<Value>
}

nonisolated package struct _AnyPreparedObservation: Sendable {
  public let sourceID: _ObservationSourceID
  public let groupID: _ObservationGroupID
  fileprivate let storage: any _PreparedObservationStorage
  private let cancelOperation: @Sendable () -> Void

  fileprivate init<Value: Sendable>(
    _ observation: _PreparedObservation<Value>
  ) {
    sourceID = observation.baseline.sourceID
    groupID = observation.openObservation.subscription.core.group.id
    storage = _PreparedObservationBox(observation: observation)
    cancelOperation = { observation._visorCancel() }
  }

  public func _visorUnwrap<Value: Sendable>(
    as type: Value.Type = Value.self
  ) throws -> _PreparedObservation<Value> {
    guard let box = storage as? _PreparedObservationBox<Value> else {
      throw _ObservationSourceFailure.protocolViolation(
        "A prepared source was adopted by a lane with another value type")
    }
    return box.observation
  }

  public func _visorCancel() {
    cancelOperation()
  }
}

nonisolated package struct _AnyObservationSource: Sendable {
  public let sourceID: _ObservationSourceID
  public let groupID: _ObservationGroupID
  fileprivate let group: _ObservationGroupCore
  fileprivate let validatePrepareLocked: @Sendable () throws -> Void
  fileprivate let prepareLocked: @Sendable () throws -> _AnyPreparedObservation

  fileprivate init(
    sourceID: _ObservationSourceID,
    group: _ObservationGroupCore,
    validatePrepareLocked: @escaping @Sendable () throws -> Void,
    prepareLocked: @escaping @Sendable () throws -> _AnyPreparedObservation
  ) {
    self.sourceID = sourceID
    groupID = group.id
    self.group = group
    self.validatePrepareLocked = validatePrepareLocked
    self.prepareLocked = prepareLocked
  }
}

nonisolated fileprivate struct _AnyDeliveryResumption: Sendable {
  let resumeValue: @Sendable () -> Void
  let resumeCancellation: @Sendable () -> Void

  init<Value: Sendable>(_ resumption: _NextResumption<Value>) {
    resumeValue = {
      resumption.continuation.resume(returning: resumption.envelope)
    }
    resumeCancellation = {
      resumption.continuation.resume(throwing: CancellationError())
    }
  }
}

nonisolated fileprivate protocol _ObservationRetirementStorage: Sendable {}

nonisolated fileprivate struct _ObservationRetirementBox<Value: Sendable>:
  _ObservationRetirementStorage,
  Sendable
{
  let envelope: _ObservationEnvelope<Value>
}

/// Keeps a user-supplied snapshot alive until the caller has left every source
/// and group critical section. A snapshot's `deinit` can execute arbitrary
/// synchronous code, including re-entering its producer channel.
nonisolated fileprivate struct _AnyObservationRetirement: Sendable {
  private let storage: any _ObservationRetirementStorage

  init<Value: Sendable>(_ envelope: _ObservationEnvelope<Value>) {
    storage = _ObservationRetirementBox(envelope: envelope)
  }

  func afterUnlock(_ operation: () -> Void) {
    withExtendedLifetime(storage, operation)
  }
}

nonisolated fileprivate struct _AnyResumeOutcome: Sendable {
  private let resumption: _AnyDeliveryResumption?
  private let retirement: _AnyObservationRetirement

  init<Value: Sendable>(_ outcome: _ResumeOutcome<Value>) {
    resumption = outcome.resumption.map(_AnyDeliveryResumption.init)
    retirement = _AnyObservationRetirement(outcome.retiredPauseEnvelope)
  }

  func resumeValueAfterUnlock() {
    retirement.afterUnlock {
      resumption?.resumeValue()
    }
  }

  func resumeCancellationAfterUnlock() {
    retirement.afterUnlock {
      resumption?.resumeCancellation()
    }
  }
}

nonisolated package struct _AnyObservationCheckpoint: Sendable {
  public let sourceID: _ObservationSourceID
  public let groupID: _ObservationGroupID
  fileprivate let group: _ObservationGroupCore
  fileprivate let subscriptionID: UUID
  fileprivate let storage: any _ObservationCheckpointStorage
  private let waitOperation: @Sendable () async throws -> Void
  fileprivate let resumeLockedOperation:
    @Sendable () throws -> _AnyResumeOutcome
  private let cancelOperation: @Sendable () -> Void

  fileprivate init<Value: Sendable>(
    checkpoint: _ObservationCheckpoint<Value>,
    subscription: _ObservationSubscription<Value>
  ) {
    sourceID = checkpoint.envelope.sourceID
    groupID = subscription.core.group.id
    group = subscription.core.group
    subscriptionID = subscription.id
    storage = _ObservationCheckpointBox(checkpoint: checkpoint)
    waitOperation = {
      try await subscription._visorWaitUntilAcknowledged(checkpoint)
    }
    resumeLockedOperation = {
      _AnyResumeOutcome(
        try subscription.core.resumeAssumingGroupLocked(
          after: checkpoint,
          for: subscription.id))
    }
    cancelOperation = { subscription._visorCancel() }
  }

  fileprivate func waitUntilAcknowledged() async throws {
    try await waitOperation()
  }

  fileprivate func cancel() {
    cancelOperation()
  }

  public func _visorUnwrap<Value: Sendable>(
    as type: Value.Type = Value.self
  ) throws -> _ObservationCheckpoint<Value> {
    guard let box = storage as? _ObservationCheckpointBox<Value> else {
      throw _ObservationSourceFailure.protocolViolation(
        "A checkpoint was adopted by a lane with another value type")
    }
    return box.checkpoint
  }
}

nonisolated fileprivate protocol _ObservationCheckpointStorage: Sendable {}

nonisolated fileprivate struct _ObservationCheckpointBox<Value: Sendable>:
  _ObservationCheckpointStorage,
  Sendable
{
  let checkpoint: _ObservationCheckpoint<Value>
}

nonisolated package struct _AnyObservationSubscription: Sendable {
  public let sourceID: _ObservationSourceID
  public let groupID: _ObservationGroupID
  fileprivate let group: _ObservationGroupCore
  fileprivate let subscriptionID: UUID
  fileprivate let checkpointLockedOperation:
    @Sendable () throws -> (_AnyObservationCheckpoint, _AnyDeliveryResumption?)
  fileprivate let validateCheckpointLockedOperation: @Sendable () throws -> Void
  private let cancelOperation: @Sendable () -> Void

  fileprivate init<Value: Sendable>(
    _ subscription: _ObservationSubscription<Value>
  ) {
    sourceID = subscription.core.sourceID
    groupID = subscription.core.group.id
    group = subscription.core.group
    subscriptionID = subscription.id
    validateCheckpointLockedOperation = {
      try subscription.core.validateCheckpointAssumingGroupLocked(
        id: subscription.id)
    }
    checkpointLockedOperation = {
      let outcome = try subscription.core
        .checkpointAndPauseAssumingGroupLocked(id: subscription.id)
      return (
        _AnyObservationCheckpoint(
          checkpoint: outcome.checkpoint,
          subscription: subscription),
        outcome.resumption.map(_AnyDeliveryResumption.init))
    }
    cancelOperation = { subscription._visorCancel() }
  }

  public func _visorCancel() {
    cancelOperation()
  }
}

/// Provisional underscored operations used by generated session code.
nonisolated package enum _ObservationRuntime {
  public static func _visorPrepareAll(
    _ sources: [_AnyObservationSource]
  ) throws -> [_AnyPreparedObservation] {
    guard Set(sources.map(\.sourceID)).count == sources.count else {
      throw _ObservationSourceFailure.protocolViolation(
        "One generated session lane must own each source subscription")
    }

    let groups = sourceGroups(sources)
    let resolved = OSAllocatedUnfairLock(
      initialState: [PreparedResult]())

    do {
      for entries in groups {
        try Task.checkCancellation()
        guard let group = entries.first?.source.group else { continue }
        try group.withLock {
          for entry in entries {
            try entry.source.validatePrepareLocked()
          }
          for entry in entries {
            try Task.checkCancellation()
            let observation = try entry.source.prepareLocked()
            resolved.withLock {
              $0.append(
                PreparedResult(
                  index: entry.index,
                  observation: observation))
            }
          }
        }
      }

      let ordered = resolved.withLock { $0.sorted { $0.index < $1.index } }
      guard ordered.count == sources.count else {
        throw _ObservationSourceFailure.protocolViolation(
          "The grouped source preparation returned an incomplete result")
      }
      return ordered.map(\.observation)
    } catch {
      for result in resolved.withLock({ $0 }) {
        result.observation._visorCancel()
      }
      throw error
    }
  }

  public static func _visorCheckpointAndPauseAll(
    _ subscriptions: [_AnyObservationSubscription]
  ) throws -> [_AnyObservationCheckpoint] {
    guard Set(subscriptions.map(\.subscriptionID)).count
      == subscriptions.count
    else {
      throw _ObservationSourceFailure.protocolViolation(
        "A subscription cannot appear twice in one checkpoint")
    }

    let groups = subscriptionGroups(subscriptions)
    let checkpointResults = OSAllocatedUnfairLock(
      initialState: [CheckpointResult]())
    let resumptions = OSAllocatedUnfairLock(
      initialState: [_AnyDeliveryResumption]())

    do {
      for entries in groups {
        try Task.checkCancellation()
        guard let group = entries.first?.subscription.group else { continue }
        try group.withLock {
          for entry in entries {
            try entry.subscription.validateCheckpointLockedOperation()
          }
          for entry in entries {
            try Task.checkCancellation()
            let (checkpoint, resumption) = try entry.subscription
              .checkpointLockedOperation()
            checkpointResults.withLock {
              $0.append(
                CheckpointResult(
                  index: entry.index,
                  checkpoint: checkpoint))
            }
            if let resumption {
              resumptions.withLock { $0.append(resumption) }
            }
          }
        }
      }

      for resumption in resumptions.withLock({ $0 }) {
        resumption.resumeValue()
      }

      let ordered = checkpointResults.withLock {
        $0.sorted { $0.index < $1.index }
      }
      guard ordered.count == subscriptions.count else {
        throw _ObservationSourceFailure.protocolViolation(
          "The grouped checkpoint returned an incomplete result")
      }
      return ordered.map(\.checkpoint)
    } catch {
      for resumption in resumptions.withLock({ $0 }) {
        resumption.resumeCancellation()
      }
      for subscription in subscriptions {
        subscription._visorCancel()
      }
      throw error
    }
  }

  public static func _visorWaitUntilAcknowledgedAll(
    _ checkpoints: [_AnyObservationCheckpoint]
  ) async throws {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        for checkpoint in checkpoints {
          group.addTask {
            try await checkpoint.waitUntilAcknowledged()
          }
        }
        try await group.waitForAll()
      }
    } catch {
      for checkpoint in checkpoints {
        checkpoint.cancel()
      }
      throw error
    }
  }

  public static func _visorResumeAll(
    after checkpoints: [_AnyObservationCheckpoint]
  ) throws {
    let groups = checkpointGroups(checkpoints)
    let outcomes = OSAllocatedUnfairLock(
      initialState: [_AnyResumeOutcome]())

    do {
      for entries in groups {
        try Task.checkCancellation()
        guard let group = entries.first?.checkpoint.group else { continue }
        try group.withLock {
          for entry in entries {
            try Task.checkCancellation()
            let outcome = try entry.checkpoint.resumeLockedOperation()
            outcomes.withLock { $0.append(outcome) }
          }
        }
      }
      for outcome in outcomes.withLock({ $0 }) {
        outcome.resumeValueAfterUnlock()
      }
    } catch {
      for outcome in outcomes.withLock({ $0 }) {
        outcome.resumeCancellationAfterUnlock()
      }
      for checkpoint in checkpoints {
        checkpoint.cancel()
      }
      throw error
    }
  }

  private struct IndexedSource: Sendable {
    let index: Int
    let source: _AnyObservationSource
  }

  private struct PreparedResult: Sendable {
    let index: Int
    let observation: _AnyPreparedObservation
  }

  private struct CheckpointResult: Sendable {
    let index: Int
    let checkpoint: _AnyObservationCheckpoint
  }

  private struct IndexedSubscription: Sendable {
    let index: Int
    let subscription: _AnyObservationSubscription
  }

  private struct IndexedCheckpoint: Sendable {
    let index: Int
    let checkpoint: _AnyObservationCheckpoint
  }

  private static func sourceGroups(
    _ sources: [_AnyObservationSource]
  ) -> [[IndexedSource]] {
    var positions: [_ObservationGroupID: Int] = [:]
    var result: [[IndexedSource]] = []
    for (index, source) in sources.enumerated() {
      if let position = positions[source.groupID] {
        result[position].append(IndexedSource(index: index, source: source))
      } else {
        positions[source.groupID] = result.count
        result.append([IndexedSource(index: index, source: source)])
      }
    }
    return result
  }

  private static func subscriptionGroups(
    _ subscriptions: [_AnyObservationSubscription]
  ) -> [[IndexedSubscription]] {
    var positions: [_ObservationGroupID: Int] = [:]
    var result: [[IndexedSubscription]] = []
    for (index, subscription) in subscriptions.enumerated() {
      if let position = positions[subscription.groupID] {
        result[position].append(
          IndexedSubscription(index: index, subscription: subscription))
      } else {
        positions[subscription.groupID] = result.count
        result.append([
          IndexedSubscription(index: index, subscription: subscription),
        ])
      }
    }
    return result
  }

  private static func checkpointGroups(
    _ checkpoints: [_AnyObservationCheckpoint]
  ) -> [[IndexedCheckpoint]] {
    var positions: [_ObservationGroupID: Int] = [:]
    var result: [[IndexedCheckpoint]] = []
    for (index, checkpoint) in checkpoints.enumerated() {
      if let position = positions[checkpoint.groupID] {
        result[position].append(
          IndexedCheckpoint(index: index, checkpoint: checkpoint))
      } else {
        positions[checkpoint.groupID] = result.count
        result.append([
          IndexedCheckpoint(index: index, checkpoint: checkpoint),
        ])
      }
    }
    return result
  }
}

nonisolated private struct _AcknowledgementWaiter: Sendable {
  let id: UUID
  let revision: UInt64
  let continuation: CheckedContinuation<Void, any Error>
}

nonisolated fileprivate struct _SubscriptionState<Value: Sendable>: Sendable {
  var lastIssuedRevision: UInt64
  var lastAcknowledgedRevision: UInt64?
  var pauseEnvelope: _ObservationEnvelope<Value>?
  var nextWaiter: CheckedContinuation<_ObservationEnvelope<Value>?, any Error>?
  var acknowledgementWaiters: [_AcknowledgementWaiter] = []
}

nonisolated private struct _CoreState<Value: Sendable>: Sendable {
  var current: _ObservationEnvelope<Value>
  var subscriptions: [UUID: _SubscriptionState<Value>] = [:]
  var terminalFailure: _ObservationSourceFailure?
}

nonisolated fileprivate struct _NextResumption<Value: Sendable>: Sendable {
  let continuation: CheckedContinuation<_ObservationEnvelope<Value>?, any Error>
  let envelope: _ObservationEnvelope<Value>
}

nonisolated fileprivate struct _CheckpointOutcome<Value: Sendable>: Sendable {
  let checkpoint: _ObservationCheckpoint<Value>
  let resumption: _NextResumption<Value>?
}

nonisolated fileprivate struct _ResumeOutcome<Value: Sendable>: Sendable {
  let resumption: _NextResumption<Value>?
  let retiredPauseEnvelope: _ObservationEnvelope<Value>
}

nonisolated private struct _PublicationSuccess<Value: Sendable>: Sendable {
  let resumptions: [_NextResumption<Value>]
  let retiredEnvelope: _ObservationEnvelope<Value>
}

nonisolated fileprivate struct _TerminationResumptions<Value: Sendable>: Sendable {
  var next: [CheckedContinuation<_ObservationEnvelope<Value>?, any Error>] = []
  var acknowledgements: [CheckedContinuation<Void, any Error>] = []
  var retiredSubscriptions: [_SubscriptionState<Value>] = []
}

nonisolated private enum _NextResolution<Value: Sendable> {
  case suspended
  case value(_ObservationEnvelope<Value>?)
  case failure(any Error)
}

nonisolated private enum _VoidResolution {
  case suspended
  case success
  case failure(any Error)
}

nonisolated fileprivate final class _ObservationCore<Value: Sendable>: Sendable {
  fileprivate let sourceID: _ObservationSourceID
  fileprivate let group: _ObservationGroupCore
  private let epoch: _ObservationEpoch
  private let lock: OSAllocatedUnfairLock<_CoreState<Value>>

  fileprivate init(
    _ initialSnapshot: sending Value,
    group: _ObservationGroupCore
  ) {
    let sourceID = _ObservationSourceID(rawValue: UUID())
    let epoch = _ObservationEpoch(rawValue: UUID())
    self.sourceID = sourceID
    self.group = group
    self.epoch = epoch
    lock = OSAllocatedUnfairLock(
      initialState: _CoreState(
        current: _ObservationEnvelope(
          sourceID: sourceID,
          epoch: epoch,
          revision: 0,
          snapshot: initialSnapshot)))
  }

  fileprivate func currentSnapshot() -> Value {
    lock.withLock { $0.current.snapshot }
  }

  fileprivate func activeSubscriptionCount() -> Int {
    lock.withLock { $0.subscriptions.count }
  }

  fileprivate func open() throws -> _OpenObservation<Value> {
    try group.withLock {
      try openAssumingGroupLocked()
    }
  }

  fileprivate func validateOpenAssumingGroupLocked() throws {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
    }
  }

  fileprivate func openAssumingGroupLocked() throws -> _OpenObservation<Value> {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }

      let id = UUID()
      let baseline = state.current
      state.subscriptions[id] = _SubscriptionState(
        lastIssuedRevision: baseline.revision,
        lastAcknowledgedRevision: nil,
        pauseEnvelope: nil,
        nextWaiter: nil)

      return _OpenObservation(
        baseline: baseline,
        subscription: _ObservationSubscription(id: id, core: self))
    }
  }

  fileprivate func prepareOpen() throws -> _PreparedObservation<Value> {
    _PreparedObservation(openObservation: try open())
  }

  fileprivate func prepareOpenAssumingGroupLocked() throws
    -> _PreparedObservation<Value>
  {
    _PreparedObservation(
      openObservation: try openAssumingGroupLocked())
  }

  fileprivate func publish(_ snapshot: sending Value) {
    let snapshot = snapshot
    let outcome = withExtendedLifetime(snapshot) {
      group.withLock {
        lock.withLock {
          state -> Result<_PublicationSuccess<Value>, _ObservationSourceFailure> in
          if let terminalFailure = state.terminalFailure {
            return .failure(terminalFailure)
          }
          guard state.current.revision < .max else {
            return .failure(.revisionExhausted)
          }

          let retiredEnvelope = state.current
          state.current = _ObservationEnvelope(
            sourceID: sourceID,
            epoch: epoch,
            revision: state.current.revision + 1,
            snapshot: snapshot)

          return .success(
            _PublicationSuccess(
              resumptions: deliverLatestWherePossible(in: &state),
              retiredEnvelope: retiredEnvelope))
        }
      }
    }

    switch outcome {
    case .success(let success):
      withExtendedLifetime(success.retiredEnvelope) {
        resume(success.resumptions)
      }
    case .failure(.revisionExhausted):
      terminate(with: .revisionExhausted)
    case .failure(let failure):
      // Observation infrastructure must not infect a valid production
      // mutation. Existing sessions see the failure already latched below.
      terminate(with: failure)
    }
  }

  fileprivate func next(
    for id: UUID
  ) async throws -> _ObservationEnvelope<Value>? {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()

      return try await withCheckedThrowingContinuation { continuation in
        let resolution = lock.withLock { state -> _NextResolution<Value> in
          if let terminalFailure = state.terminalFailure {
            return .failure(terminalFailure)
          }
          guard var subscription = state.subscriptions[id] else {
            return .value(nil)
          }
          if Task.isCancelled {
            return .failure(CancellationError())
          }
          if let envelope = takeEligibleEnvelope(
            from: &subscription,
            current: state.current)
          {
            state.subscriptions[id] = subscription
            return .value(envelope)
          }
          guard subscription.nextWaiter == nil else {
            return .failure(
              _ObservationSourceFailure.protocolViolation(
                "A subscription supports one iterator task"))
          }

          subscription.nextWaiter = continuation
          state.subscriptions[id] = subscription
          return .suspended
        }

        switch resolution {
        case .suspended:
          break
        case .value(let envelope):
          continuation.resume(returning: envelope)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      // Synchronous cancellation closes the registration race without an
      // unstructured Task hopping to another isolation domain.
      cancel(id: id)
    }
  }

  fileprivate func acknowledge(
    _ envelope: _ObservationEnvelope<Value>,
    for id: UUID
  ) throws {
    let resumptions = try lock.withLock {
      state -> [CheckedContinuation<Void, any Error>] in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard envelope.sourceID == sourceID, envelope.epoch == epoch else {
        throw _ObservationSourceFailure.protocolViolation(
          "An acknowledgement came from another source or epoch")
      }
      guard envelope.revision <= subscription.lastIssuedRevision else {
        throw _ObservationSourceFailure.protocolViolation(
          "An acknowledgement preceded delivery")
      }
      if let lastAcknowledgedRevision = subscription.lastAcknowledgedRevision,
         envelope.revision < lastAcknowledgedRevision
      {
        throw _ObservationSourceFailure.protocolViolation(
          "Acknowledgements must be monotonic")
      }

      subscription.lastAcknowledgedRevision = envelope.revision
      let ready = subscription.acknowledgementWaiters.filter {
        $0.revision <= envelope.revision
      }
      subscription.acknowledgementWaiters.removeAll {
        $0.revision <= envelope.revision
      }
      state.subscriptions[id] = subscription
      return ready.map(\.continuation)
    }

    for continuation in resumptions {
      continuation.resume()
    }
  }

  fileprivate func checkpointAndPause(
    id: UUID
  ) throws -> _ObservationCheckpoint<Value> {
    let outcome = try group.withLock {
      try checkpointAndPauseAssumingGroupLocked(id: id)
    }

    if let resumption = outcome.resumption {
      resumption.continuation.resume(returning: resumption.envelope)
    }
    return outcome.checkpoint
  }

  fileprivate func checkpointAndPauseAssumingGroupLocked(
    id: UUID
  ) throws -> _CheckpointOutcome<Value> {
    try lock.withLock { state -> _CheckpointOutcome<Value> in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard subscription.pauseEnvelope == nil else {
        throw _ObservationSourceFailure.protocolViolation(
          "A subscription is already paused")
      }

      let target = state.current
      subscription.pauseEnvelope = target
      let resumption = takeWaitingDelivery(
        from: &subscription,
        current: state.current)
      state.subscriptions[id] = subscription
      return _CheckpointOutcome(
        checkpoint: _ObservationCheckpoint(
          subscriptionID: id,
          envelope: target),
        resumption: resumption)
    }
  }

  fileprivate func validateCheckpointAssumingGroupLocked(
    id: UUID
  ) throws {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard let subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard subscription.pauseEnvelope == nil else {
        throw _ObservationSourceFailure.protocolViolation(
          "A subscription is already paused")
      }
    }
  }

  fileprivate func waitUntilAcknowledged(
    _ checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID
  ) async throws {
    let waiterID = UUID()

    try await withTaskCancellationHandler {
      try Task.checkCancellation()

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let resolution = lock.withLock { state -> _VoidResolution in
          if let terminalFailure = state.terminalFailure {
            return .failure(terminalFailure)
          }
          guard validate(checkpoint, for: id) else {
            return .failure(
              _ObservationSourceFailure.protocolViolation(
                "A checkpoint belongs to another subscription, source or epoch"))
          }
          guard var subscription = state.subscriptions[id] else {
            return .failure(CancellationError())
          }
          if Task.isCancelled {
            return .failure(CancellationError())
          }
          if let revision = subscription.lastAcknowledgedRevision,
             revision >= checkpoint.envelope.revision
          {
            return .success
          }

          subscription.acknowledgementWaiters.append(
            _AcknowledgementWaiter(
              id: waiterID,
              revision: checkpoint.envelope.revision,
              continuation: continuation))
          state.subscriptions[id] = subscription
          return .suspended
        }

        switch resolution {
        case .suspended:
          break
        case .success:
          continuation.resume()
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      cancelAcknowledgementWaiter(waiterID: waiterID, for: id)
    }
  }

  fileprivate func claimForDirectReconciliation(
    _ checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID
  ) throws -> _ObservationEnvelope<Value> {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard validate(checkpoint, for: id) else {
        throw _ObservationSourceFailure.protocolViolation(
          "A checkpoint belongs to another subscription, source or epoch")
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard subscription.pauseEnvelope?.revision
        == checkpoint.envelope.revision
      else {
        throw _ObservationSourceFailure.protocolViolation(
          "Only the active pause target can be reconciled directly")
      }
      guard subscription.nextWaiter == nil else {
        throw _ObservationSourceFailure.protocolViolation(
          "A direct reconciliation cannot race the iterator")
      }
      guard checkpoint.envelope.revision >= subscription.lastIssuedRevision else {
        throw _ObservationSourceFailure.protocolViolation(
          "A direct reconciliation cannot move delivery backwards")
      }

      subscription.lastIssuedRevision = checkpoint.envelope.revision
      state.subscriptions[id] = subscription
      return checkpoint.envelope
    }
  }

  fileprivate func resume(
    after checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID
  ) throws {
    let outcome = try group.withLock {
      try resumeAssumingGroupLocked(after: checkpoint, for: id)
    }

    withExtendedLifetime(outcome.retiredPauseEnvelope) {
      if let resumption = outcome.resumption {
        resumption.continuation.resume(returning: resumption.envelope)
      }
    }
  }

  fileprivate func resumeAssumingGroupLocked(
    after checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID
  ) throws -> _ResumeOutcome<Value> {
    try lock.withLock { state -> _ResumeOutcome<Value> in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard validate(checkpoint, for: id) else {
        throw _ObservationSourceFailure.protocolViolation(
          "A checkpoint belongs to another subscription, source or epoch")
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard let retiredPauseEnvelope = subscription.pauseEnvelope,
            retiredPauseEnvelope.revision == checkpoint.envelope.revision
      else {
        throw _ObservationSourceFailure.protocolViolation(
          "The checkpoint is not the subscription's active pause")
      }
      guard let acknowledged = subscription.lastAcknowledgedRevision,
            acknowledged >= checkpoint.envelope.revision
      else {
        throw _ObservationSourceFailure.protocolViolation(
          "A subscription cannot resume before its target is acknowledged")
      }

      subscription.pauseEnvelope = nil
      let resumption = takeWaitingDelivery(
        from: &subscription,
        current: state.current)
      state.subscriptions[id] = subscription
      return _ResumeOutcome(
        resumption: resumption,
        retiredPauseEnvelope: retiredPauseEnvelope)
    }
  }

  fileprivate func cancel(id: UUID) {
    let subscription = group.withLock {
      cancelAssumingGroupLocked(id: id)
    }
    resumeCancellation(of: subscription)
  }

  fileprivate func cancelAssumingGroupLocked(
    id: UUID
  ) -> _SubscriptionState<Value>? {
    lock.withLock { state in
      state.subscriptions.removeValue(forKey: id)
    }
  }

  fileprivate func resumeCancellation(
    of subscription: _SubscriptionState<Value>?
  ) {
    // Explicitly use the retired pause envelope after unlocking. This prevents
    // ARC lifetime shortening from releasing its snapshot in the inlined
    // `removeValue` critical section when no continuation retains it.
    withExtendedLifetime(subscription?.pauseEnvelope) {
      subscription?.nextWaiter?.resume(returning: nil)
      for waiter in subscription?.acknowledgementWaiters ?? [] {
        waiter.continuation.resume(throwing: CancellationError())
      }
    }
  }

  fileprivate func terminate(with failure: _ObservationSourceFailure) {
    let resumptions = group.withLock {
      terminateAssumingGroupLocked(with: failure)
    }
    resumeTermination(resumptions, failure: failure)
  }

  fileprivate func terminateAssumingGroupLocked(
    with failure: _ObservationSourceFailure
  ) -> _TerminationResumptions<Value>? {
    lock.withLock { state -> _TerminationResumptions<Value>? in
      guard state.terminalFailure == nil else {
        return nil
      }
      state.terminalFailure = failure
      var resumptions = _TerminationResumptions<Value>()
      // Copy subscription state before clearing it so paused snapshots cannot
      // run arbitrary deinitialisation while either source lock is held.
      resumptions.retiredSubscriptions = Array(state.subscriptions.values)
      for subscription in state.subscriptions.values {
        if let nextWaiter = subscription.nextWaiter {
          resumptions.next.append(nextWaiter)
        }
        resumptions.acknowledgements.append(
          contentsOf: subscription.acknowledgementWaiters.map(\.continuation))
      }
      state.subscriptions.removeAll(keepingCapacity: false)
      return resumptions
    }
  }

  fileprivate func resumeTermination(
    _ resumptions: _TerminationResumptions<Value>?,
    failure: _ObservationSourceFailure
  ) {
    guard let resumptions else {
      return
    }
    withExtendedLifetime(resumptions.retiredSubscriptions) {
      for continuation in resumptions.next {
        continuation.resume(throwing: failure)
      }
      for continuation in resumptions.acknowledgements {
        continuation.resume(throwing: failure)
      }
    }
  }

  private func cancelAcknowledgementWaiter(
    waiterID: UUID,
    for id: UUID
  ) {
    let continuation = lock.withLock {
      state -> CheckedContinuation<Void, any Error>? in
      guard var subscription = state.subscriptions[id],
            let index = subscription.acknowledgementWaiters.firstIndex(
              where: { $0.id == waiterID })
      else {
        return nil
      }
      let waiter = subscription.acknowledgementWaiters.remove(at: index)
      state.subscriptions[id] = subscription
      return waiter.continuation
    }
    continuation?.resume(throwing: CancellationError())
  }

  private func validate(
    _ checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID
  ) -> Bool {
    checkpoint.subscriptionID == id
      && checkpoint.envelope.sourceID == sourceID
      && checkpoint.envelope.epoch == epoch
  }

  private func takeEligibleEnvelope(
    from subscription: inout _SubscriptionState<Value>,
    current: _ObservationEnvelope<Value>
  ) -> _ObservationEnvelope<Value>? {
    let candidate = subscription.pauseEnvelope ?? current
    guard candidate.revision > subscription.lastIssuedRevision else {
      return nil
    }
    subscription.lastIssuedRevision = candidate.revision
    return candidate
  }

  private func takeWaitingDelivery(
    from subscription: inout _SubscriptionState<Value>,
    current: _ObservationEnvelope<Value>
  ) -> _NextResumption<Value>? {
    guard let continuation = subscription.nextWaiter,
          let envelope = takeEligibleEnvelope(
            from: &subscription,
            current: current)
    else {
      return nil
    }
    subscription.nextWaiter = nil
    return _NextResumption(
      continuation: continuation,
      envelope: envelope)
  }

  private func deliverLatestWherePossible(
    in state: inout _CoreState<Value>
  ) -> [_NextResumption<Value>] {
    var resumptions: [_NextResumption<Value>] = []
    for id in state.subscriptions.keys {
      guard var subscription = state.subscriptions[id] else {
        continue
      }
      if let resumption = takeWaitingDelivery(
        from: &subscription,
        current: state.current)
      {
        resumptions.append(resumption)
      }
      state.subscriptions[id] = subscription
    }
    return resumptions
  }

  private func resume(_ resumptions: [_NextResumption<Value>]) {
    for resumption in resumptions {
      resumption.continuation.resume(returning: resumption.envelope)
    }
  }
}
