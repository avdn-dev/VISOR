import Testing
import VISOR

@MainActor
private struct JournalEntry {
  let fieldID: ObjectIdentifier
  let fieldName: String
  let oldValue: Any
  let newValue: Any
}

package struct _OutsideWindowMutationForProof: Equatable {
  package enum Relation: Equatable {
    case beforeFirstAction
    case beforeAction(UInt64)
    case betweenActions(previous: UInt64, next: UInt64)
    case afterAction(UInt64)
  }

  package let order: UInt64
  package let fieldID: ObjectIdentifier
  package let fieldName: String
  package let relation: Relation
}

package struct _OutsideWindowDiagnosticContextForProof: Equatable {
  package let entries: [_OutsideWindowMutationForProof]
  package let omittedEntryCount: UInt64
}

private struct OutsideWindowMutationEntry {
  let order: UInt64
  let fieldID: ObjectIdentifier
  let fieldName: String
  var relation: _OutsideWindowMutationForProof.Relation
}

private struct OutsideWindowMutationRing {
  private var storage: [OutsideWindowMutationEntry?]
  private var oldestIndex = 0
  private(set) var count = 0
  private(set) var omittedEntryCount: UInt64 = 0
  private var nextOrder: UInt64 = 1

  init(capacity: Int) {
    precondition(capacity > 0)
    storage = Array(repeating: nil, count: capacity)
  }

  mutating func append(
    fieldID: ObjectIdentifier,
    fieldName: String,
    relation: _OutsideWindowMutationForProof.Relation
  ) {
    let entry = OutsideWindowMutationEntry(
      order: nextOrder,
      fieldID: fieldID,
      fieldName: fieldName,
      relation: relation)
    if nextOrder < .max {
      nextOrder += 1
    }

    if count < storage.count {
      let index = (oldestIndex + count) % storage.count
      storage[index] = entry
      count += 1
      return
    }

    storage[oldestIndex] = entry
    oldestIndex = (oldestIndex + 1) % storage.count
    if omittedEntryCount < .max {
      omittedEntryCount += 1
    }
  }

  mutating func reclassifyBeforeFirstAction(as action: UInt64) {
    for index in storage.indices {
      guard var entry = storage[index] else { continue }
      guard entry.relation == .beforeFirstAction else { continue }
      entry.relation = .beforeAction(action)
      storage[index] = entry
    }
  }

  mutating func reclassifyAfterAction(
    _ previous: UInt64,
    asBefore next: UInt64
  ) {
    for index in storage.indices {
      guard var entry = storage[index] else { continue }
      guard entry.relation == .afterAction(previous) else { continue }
      entry.relation = .betweenActions(previous: previous, next: next)
      storage[index] = entry
    }
  }

  func snapshot() -> _OutsideWindowDiagnosticContextForProof {
    var entries: [_OutsideWindowMutationForProof] = []
    entries.reserveCapacity(count)

    for offset in 0..<count {
      let index = (oldestIndex + offset) % storage.count
      guard let entry = storage[index] else { continue }
      entries.append(_OutsideWindowMutationForProof(
        order: entry.order,
        fieldID: entry.fieldID,
        fieldName: entry.fieldName,
        relation: entry.relation))
    }

    return _OutsideWindowDiagnosticContextForProof(
      entries: entries,
      omittedEntryCount: omittedEntryCount)
  }

  mutating func removeAll() {
    for index in storage.indices {
      storage[index] = nil
    }
    oldestIndex = 0
    count = 0
    omittedEntryCount = 0
    nextOrder = 1
  }
}

private enum JournalWindowState: Equatable {
  case outside
  case opening(UInt64)
  case active
  case invalidated
  case ended
}

private enum StateJournalFailure: Error, CustomStringConvertible {
  case logicalCommitGuardExceeded

  var description: String {
    "active State journal exceeded its logical commit guard"
  }
}

@MainActor
private final class StateJournal: _StateMutationRecorder {
  // The fixture's scalar, growing-collection and repeated copy-on-write stress
  // window retains 4,352 raw commits. This internal guard leaves headroom for
  // larger ordinary tests while still bounding runaway cheap-value storms.
  fileprivate static let defaultActiveCommitLimit = 8_192
  fileprivate static let defaultOutsideWindowCapacity = 32

  private(set) var entries: [JournalEntry] = []
  private var baselines: [ObjectIdentifier: Any] = [:]
  private(set) var hasClosedWindow = false
  private let activeCommitLimit: Int
  private var outsideWindowRing: OutsideWindowMutationRing
  private var windowState = JournalWindowState.outside
  private var nextActionOrdinal: UInt64 = 1
  private var currentActionOrdinal: UInt64?
  private var lastCompletedActionOrdinal: UInt64?
  private var activeSourceLocation: SourceLocation?
  private var failureHandler:
    (@MainActor (any Error, SourceLocation) -> Void)?

  init(
    activeCommitLimit: Int = defaultActiveCommitLimit,
    outsideWindowCapacity: Int = defaultOutsideWindowCapacity
  ) {
    precondition(activeCommitLimit > 0)
    self.activeCommitLimit = activeCommitLimit
    outsideWindowRing = OutsideWindowMutationRing(
      capacity: outsideWindowCapacity)
  }

  func installFailureHandler(
    _ handler: @escaping @MainActor (any Error, SourceLocation) -> Void
  ) {
    failureHandler = handler
  }

  func begin<State: _ViewModelState>(
    state: State,
    sourceLocation: SourceLocation
  ) -> Bool {
    guard windowState == .outside else {
      Issue.record(
        "A perform window is already active for this State",
        sourceLocation: sourceLocation)
      return false
    }

    let actionOrdinal = nextActionOrdinal
    if nextActionOrdinal < .max {
      nextActionOrdinal += 1
    }
    windowState = .opening(actionOrdinal)

    // Releasing the previous typed window may synchronously run a retained
    // value's deinitialiser. Its routed writes still precede this action's
    // baseline and are classified through the explicit opening phase below.
    entries.removeAll(keepingCapacity: true)
    baselines.removeAll(keepingCapacity: true)

    if let previous = lastCompletedActionOrdinal {
      outsideWindowRing.reclassifyAfterAction(
        previous,
        asBefore: actionOrdinal)
    } else {
      outsideWindowRing.reclassifyBeforeFirstAction(as: actionOrdinal)
    }

    for field in State._visorAllFields {
      baselines[field.identity] = field.read(from: state)
    }
    activeSourceLocation = sourceLocation
    hasClosedWindow = false
    currentActionOrdinal = actionOrdinal
    windowState = .active
    return true
  }

  func close() {
    guard windowState == .active else { return }
    windowState = .outside
    hasClosedWindow = true
    activeSourceLocation = nil
    lastCompletedActionOrdinal = currentActionOrdinal
    currentActionOrdinal = nil
  }

  func abandon() {
    windowState = .invalidated
    hasClosedWindow = false
    activeSourceLocation = nil
    currentActionOrdinal = nil
    entries.removeAll(keepingCapacity: false)
    baselines.removeAll(keepingCapacity: false)
  }

  func finish() {
    windowState = .ended
    hasClosedWindow = false
    activeSourceLocation = nil
    currentActionOrdinal = nil
    lastCompletedActionOrdinal = nil
    entries.removeAll(keepingCapacity: false)
    baselines.removeAll(keepingCapacity: false)
    outsideWindowRing.removeAll()
  }

  func record(
    fieldID: ObjectIdentifier,
    fieldName: String,
    oldValue: Any,
    newValue: Any
  ) {
    switch windowState {
    case .outside:
      let relation = lastCompletedActionOrdinal.map {
        _OutsideWindowMutationForProof.Relation.afterAction($0)
      } ?? .beforeFirstAction
      outsideWindowRing.append(
        fieldID: fieldID,
        fieldName: fieldName,
        relation: relation)
      return
    case let .opening(action):
      let relation = lastCompletedActionOrdinal.map {
        _OutsideWindowMutationForProof.Relation.betweenActions(
          previous: $0,
          next: action)
      } ?? .beforeAction(action)
      outsideWindowRing.append(
        fieldID: fieldID,
        fieldName: fieldName,
        relation: relation)
      return
    case .invalidated, .ended:
      return
    case .active:
      break
    }

    guard entries.count < activeCommitLimit else {
      let sourceLocation = activeSourceLocation
      abandon()
      if let sourceLocation {
        failureHandler?(
          StateJournalFailure.logicalCommitGuardExceeded,
          sourceLocation)
      }
      return
    }

    entries.append(JournalEntry(
      fieldID: fieldID,
      fieldName: fieldName,
      oldValue: oldValue,
      newValue: newValue))
  }

  func entries(for fieldID: ObjectIdentifier) -> [JournalEntry] {
    entries.filter { $0.fieldID == fieldID }
  }

  func baseline(for fieldID: ObjectIdentifier) -> Any? {
    baselines[fieldID]
  }

  func outsideWindowDiagnosticContext()
    -> _OutsideWindowDiagnosticContextForProof
  {
    outsideWindowRing.snapshot()
  }

  func addingOutsideWindowDiagnosticContext(to message: String) -> String {
    let context = outsideWindowRing.snapshot()
    guard !context.entries.isEmpty || context.omittedEntryCount > 0 else {
      return message
    }

    let entries = context.entries.map { entry in
      "#\(entry.order) \(entry.fieldName) \(describe(entry.relation))"
    }
    let entryList = entries.joined(separator: "; ")
    return "\(message)\nOutside-window context (\(context.omittedEntryCount) omitted): \(entryList)"
  }

  private func describe(
    _ relation: _OutsideWindowMutationForProof.Relation
  ) -> String {
    switch relation {
    case .beforeFirstAction:
      "before the first action"
    case let .beforeAction(action):
      "before action \(action)"
    case let .betweenActions(previous, next):
      "between actions \(previous) and \(next)"
    case let .afterAction(action):
      "after action \(action)"
    }
  }
}

private enum ObservationTestControlError: Error {
  case unavailableResult
  case stateIdentityChanged
}

private enum ObservationTestPhase: Equatable {
  case ready
  case performing
  case cancellationPending
  case poisoned
  case ended
}

private enum WindowTransition {
  case succeeded
  case unavailable
  case cancelled
}

@MainActor
public final class ObservationTest<SUT: ViewModel> {
  private var sut: SUT?
  private var state: SUT.State?
  private var journal: StateJournal?
  private var session: _ObservationSession?
  private var phase = ObservationTestPhase.ready
  private var hasReportedInfrastructureFailure = false
  private let infrastructureIssueRecorder:
    @MainActor (String, SourceLocation) -> Void

  fileprivate init(
    sut: SUT,
    state: SUT.State,
    journal: StateJournal,
    session: _ObservationSession,
    infrastructureIssueRecorder:
      @escaping @MainActor (String, SourceLocation) -> Void
  ) {
    self.sut = sut
    self.state = state
    self.journal = journal
    self.session = session
    self.infrastructureIssueRecorder = infrastructureIssueRecorder
  }

  public func perform(
    _ action: SUT.Action,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    guard let sut else {
      recordEndedScopeMisuse(sourceLocation: sourceLocation)
      return
    }
    guard await openWindow(sourceLocation: sourceLocation) == .succeeded else {
      return
    }

    await sut.handle(action)
    _ = await closeWindow(sourceLocation: sourceLocation)
  }

  public func perform(
    _ operation: @MainActor () async -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    guard await openWindow(sourceLocation: sourceLocation) == .succeeded else {
      return
    }

    await operation()
    _ = await closeWindow(sourceLocation: sourceLocation)
  }

  public func perform(
    _ operation: @MainActor () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async rethrows {
    guard await openWindow(sourceLocation: sourceLocation) == .succeeded else {
      return
    }

    do {
      try await operation()
    } catch {
      _ = await closeWindow(sourceLocation: sourceLocation)
      throw error
    }
    _ = await closeWindow(sourceLocation: sourceLocation)
  }

  public func perform<Result>(
    _ operation: @MainActor () async throws -> Result,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws -> Result {
    switch await openWindow(sourceLocation: sourceLocation) {
    case .succeeded:
      break
    case .cancelled:
      throw CancellationError()
    case .unavailable:
      if Task.isCancelled {
        throw CancellationError()
      }
      throw ObservationTestControlError.unavailableResult
    }

    let result: Result
    do {
      result = try await operation()
    } catch {
      _ = await closeWindow(sourceLocation: sourceLocation)
      throw error
    }

    // Once the operation has produced its domain result, an infrastructure
    // failure while closing is reported separately and poisons the scope; it
    // must not replace or fabricate that already-produced value. Cancellation
    // remains distinct and propagates after joined cleanup.
    switch await closeWindow(sourceLocation: sourceLocation) {
    case .succeeded:
      return result
    case .cancelled:
      throw CancellationError()
    case .unavailable:
      if Task.isCancelled {
        throw CancellationError()
      }
      return result
    }
  }

  private func openWindow(
    sourceLocation: SourceLocation
  ) async -> WindowTransition {
    switch phase {
    case .ready:
      phase = .performing
    case .performing:
      Issue.record(
        "A perform window is already active for this State",
        sourceLocation: sourceLocation)
      return .unavailable
    case .cancellationPending:
      return .cancelled
    case .poisoned:
      return .unavailable
    case .ended:
      recordEndedScopeMisuse(sourceLocation: sourceLocation)
      return .unavailable
    }

    guard let state, let journal, let session else {
      phase = .ended
      return .unavailable
    }
    guard sut?.state === state else {
      journal.abandon()
      phase = .poisoned
      recordInfrastructureFailure(
        ObservationTestControlError.stateIdentityChanged,
        phase: "opening an action window",
        sourceLocation: sourceLocation)
      return .unavailable
    }
    guard !reportSessionFailureIfNeeded(sourceLocation: sourceLocation) else {
      return .unavailable
    }

    do {
      let didBegin = try await session._visorWithPause(
        {
          journal.begin(state: state, sourceLocation: sourceLocation)
        },
        _visorPhase: .openingFence)
      guard didBegin else {
        phase = .ready
        return .unavailable
      }
      return .succeeded
    } catch is CancellationError {
      journal.abandon()
      phase = .cancellationPending
      return .cancelled
    } catch {
      journal.abandon()
      phase = .poisoned
      recordInfrastructureFailure(
        session._visorFailure ?? error,
        phase: "opening an action window",
        sourceLocation: sourceLocation)
      return .unavailable
    }
  }

  private func closeWindow(
    sourceLocation: SourceLocation
  ) async -> WindowTransition {
    if phase == .poisoned {
      await session?._visorStop()
      return .unavailable
    }
    guard phase == .performing else {
      return phase == .cancellationPending ? .cancelled : .unavailable
    }
    guard let journal, let session else {
      phase = .ended
      return .unavailable
    }
    do {
      try await session._visorWithPause(
        { journal.close() },
        _visorPhase: .closingFence)
      phase = .ready
      return .succeeded
    } catch is CancellationError {
      journal.abandon()
      phase = .cancellationPending
      return .cancelled
    } catch {
      journal.abandon()
      phase = .poisoned
      recordInfrastructureFailure(
        session._visorFailure ?? error,
        phase: "closing an action window",
        sourceLocation: sourceLocation)
      return .unavailable
    }
  }

  @discardableResult
  private func reportSessionFailureIfNeeded(
    sourceLocation: SourceLocation
  ) -> Bool {
    guard let session else { return false }
    guard let failure = session._visorFailure else { return false }
    journal?.abandon()
    phase = .poisoned
    recordInfrastructureFailure(
      failure,
      phase: "running the observation session",
      sourceLocation: sourceLocation)
    return true
  }

  private func recordInfrastructureFailure(
    _ error: any Error,
    phase: String,
    sourceLocation: SourceLocation
  ) {
    guard !hasReportedInfrastructureFailure else { return }
    hasReportedInfrastructureFailure = true
    infrastructureIssueRecorder(
      "VISOR failed while \(phase): \(String(describing: error))",
      sourceLocation)
  }

  fileprivate func journalFailed(
    _ error: any Error,
    sourceLocation: SourceLocation
  ) {
    guard phase == .performing else { return }
    phase = .poisoned
    let sessionFailure = session?._visorFailure
    let failure = sessionFailure ?? error
    let failurePhase = sessionFailure == nil
      ? "recording an action window"
      : "running the observation session"
    // Make cancellation visible before reporting, because the injected proof
    // recorder (and Swift Testing itself) may synchronously re-enter user code.
    session?._visorRequestStop()
    recordInfrastructureFailure(
      failure,
      phase: failurePhase,
      sourceLocation: sourceLocation)
  }

  private func recordEndedScopeMisuse(
    sourceLocation: SourceLocation
  ) {
    Issue.record(
      "This observation scope has ended",
      sourceLocation: sourceLocation)
  }

  fileprivate func end() {
    guard phase != .ended else { return }
    phase = .ended
    journal?.finish()
    sut = nil
    state = nil
    journal = nil
    session = nil
  }

  fileprivate func reportUnobservedSessionFailure(
    _ failure: (any Error)?,
    sourceLocation: SourceLocation
  ) {
    guard let failure else { return }
    recordInfrastructureFailure(
      failure,
      phase: "running the observation session",
      sourceLocation: sourceLocation)
  }

  public func expect<Value: Equatable>(
    _ selection: KeyPath<
      SUT.State._VISORSelectors,
      _StateField<SUT.State, Value>
    >,
    hasExactChanges expected: [Value],
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard phase != .cancellationPending, phase != .poisoned else { return }
    guard phase != .ended, let journal else {
      recordEndedScopeMisuse(sourceLocation: sourceLocation)
      return
    }
    guard phase != .performing else {
      Issue.record(
        "expect requires a completed perform window",
        sourceLocation: sourceLocation)
      return
    }
    guard !reportSessionFailureIfNeeded(sourceLocation: sourceLocation) else {
      return
    }
    guard journal.hasClosedWindow else {
      Issue.record(
        "expect requires a completed perform window",
        sourceLocation: sourceLocation)
      return
    }

    let field = SUT.State._visorSelectors[keyPath: selection]

    guard let history = strictHistory(
      for: field,
      in: journal,
      sourceLocation: sourceLocation
    ) else { return }

    guard !containsAdjacentDuplicate(in: expected) else {
      Issue.record(
        "hasExactChanges cannot contain adjacent duplicate values for '\(field.name)'",
        sourceLocation: sourceLocation)
      return
    }

    var previous = history.baseline
    var actual: [Value] = []

    for value in history.commits {
      if value != previous {
        actual.append(value)
        previous = value
      }
    }

    guard actual == expected else {
      Issue.record(
        Comment(rawValue: journal.addingOutsideWindowDiagnosticContext(
          to: "Expected exact changes \(String(describing: expected)) for '\(field.name)', got \(String(describing: actual))")),
        sourceLocation: sourceLocation)
      return
    }
  }

  public func expect<Value>(
    _ selection: KeyPath<
      SUT.State._VISORSelectors,
      _StateField<SUT.State, Value>
    >,
    alwaysSatisfies predicate: @MainActor (Value) -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard phase != .cancellationPending, phase != .poisoned else { return }
    guard phase != .ended, let journal else {
      recordEndedScopeMisuse(sourceLocation: sourceLocation)
      return
    }
    guard phase != .performing else {
      Issue.record(
        "expect requires a completed perform window",
        sourceLocation: sourceLocation)
      return
    }
    guard !reportSessionFailureIfNeeded(sourceLocation: sourceLocation) else {
      return
    }
    guard journal.hasClosedWindow else {
      Issue.record(
        "expect requires a completed perform window",
        sourceLocation: sourceLocation)
      return
    }

    let field = SUT.State._visorSelectors[keyPath: selection]

    guard let history = strictHistory(
      for: field,
      in: journal,
      sourceLocation: sourceLocation
    ) else { return }

    guard predicate(history.baseline) else {
      Issue.record(
        Comment(rawValue: journal.addingOutsideWindowDiagnosticContext(
          to: "The baseline for '\(field.name)' did not always satisfy the predicate")),
        sourceLocation: sourceLocation)
      return
    }

    for value in history.commits {
      guard predicate(value) else {
        Issue.record(
          Comment(rawValue: journal.addingOutsideWindowDiagnosticContext(
            to: "A committed value for '\(field.name)' did not always satisfy the predicate")),
          sourceLocation: sourceLocation)
        return
      }
    }
  }

  private func strictHistory<Value>(
    for field: _StateField<SUT.State, Value>,
    in journal: StateJournal,
    sourceLocation: SourceLocation
  ) -> (baseline: Value, commits: [Value])? {
    guard let erasedBaseline = journal.baseline(for: field.identity) else {
      Issue.record(
        "VISOR could not recover the typed baseline for '\(field.name)'",
        sourceLocation: sourceLocation)
      return nil
    }

    let fieldEntries = journal.entries(for: field.identity)
    guard
      !field.isDirectReference,
      !isOuterReference(erasedBaseline),
      !fieldEntries.contains(where: { isOuterReference($0.newValue) })
    else {
      Issue.record(
        "Strict State history does not support an outer reference value for field '\(field.name)'",
        sourceLocation: sourceLocation)
      return nil
    }

    guard let baseline = erasedBaseline as? Value else {
      Issue.record(
        "VISOR could not recover the typed baseline for '\(field.name)'",
        sourceLocation: sourceLocation)
      return nil
    }

    var commits: [Value] = []
    commits.reserveCapacity(fieldEntries.count)

    for entry in fieldEntries {
      guard let value = entry.newValue as? Value else {
        Issue.record(
          "VISOR could not recover a typed commit for '\(field.name)'",
          sourceLocation: sourceLocation)
        return nil
      }
      commits.append(value)
    }

    return (baseline, commits)
  }

  private func isOuterReference(_ value: Any) -> Bool {
    type(of: value) is AnyObject.Type
  }

  private func containsAdjacentDuplicate<Value: Equatable>(
    in values: [Value]
  ) -> Bool {
    zip(values, values.dropFirst()).contains { $0 == $1 }
  }

  package func _rawCommitCount<Value>(
    _ selection: KeyPath<
      SUT.State._VISORSelectors,
      _StateField<SUT.State, Value>
    >
  ) -> Int {
    guard let journal else { return 0 }
    let field = SUT.State._visorSelectors[keyPath: selection]
    return journal.entries(for: field.identity).count
  }

  package var _rawCommitFieldNames: [String] {
    journal?.entries.map(\.fieldName) ?? []
  }

  package var _outsideWindowDiagnosticContextForProof:
    _OutsideWindowDiagnosticContextForProof
  {
    journal?.outsideWindowDiagnosticContext()
      ?? _OutsideWindowDiagnosticContextForProof(
        entries: [],
        omittedEntryCount: 0)
  }

  package func _waitForSessionFailureForProof() async throws {
    guard let session else {
      throw ObservationTestControlError.unavailableResult
    }
    _ = try await session._visorWaitForFailure()
  }

  package func _captureBaselineForProof(
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard let journal, let state else {
      recordEndedScopeMisuse(sourceLocation: sourceLocation)
      return
    }
    guard journal.begin(
      state: state,
      sourceLocation: sourceLocation
    ) else { return }
    journal.close()
  }
}

@MainActor
public func observe<SUT: ViewModel>(
  _ sut: SUT,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observeImplementation(
    sut,
    sourceLocation: sourceLocation,
    beforePauseDrain: {},
    activeJournalCommitLimit: StateJournal.defaultActiveCommitLimit,
    deadlinePolicy: .production,
    infrastructureIssueRecorder: { message, sourceLocation in
      Issue.record(
        Comment(rawValue: message),
        sourceLocation: sourceLocation)
    },
    body)
}

@MainActor
package func _observeForProof<SUT: ViewModel>(
  _ sut: SUT,
  sourceLocation: SourceLocation = #_sourceLocation,
  beforePauseDrain: @escaping @MainActor @Sendable () async -> Void,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observeImplementation(
    sut,
    sourceLocation: sourceLocation,
    beforePauseDrain: beforePauseDrain,
    activeJournalCommitLimit: StateJournal.defaultActiveCommitLimit,
    deadlinePolicy: .production,
    infrastructureIssueRecorder: { message, sourceLocation in
      Issue.record(
        Comment(rawValue: message),
        sourceLocation: sourceLocation)
    },
    body)
}

@MainActor
package func _observeWithJournalPolicyForProof<SUT: ViewModel>(
  _ sut: SUT,
  sourceLocation: SourceLocation = #_sourceLocation,
  logicalCommitLimit: Int,
  outsideWindowCapacity: Int = StateJournal.defaultOutsideWindowCapacity,
  infrastructureIssueRecorder:
    @escaping @MainActor (String, SourceLocation) -> Void,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observeImplementation(
    sut,
    sourceLocation: sourceLocation,
    beforePauseDrain: {},
    activeJournalCommitLimit: logicalCommitLimit,
    outsideWindowCapacity: outsideWindowCapacity,
    deadlinePolicy: .production,
    infrastructureIssueRecorder: infrastructureIssueRecorder,
    body)
}

@MainActor
package func _observeWithDeadlinePolicyForProof<SUT: ViewModel>(
  _ sut: SUT,
  sourceLocation: SourceLocation = #_sourceLocation,
  beforePauseDrain: @escaping @MainActor @Sendable () async -> Void = {},
  deadlinePolicy: _ObservationDeadlinePolicy,
  _visorDidFinishTeardown:
    @escaping @MainActor @Sendable () -> Void = {},
  infrastructureIssueRecorder:
    @escaping @MainActor (String, SourceLocation) -> Void,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observeImplementation(
    sut,
    sourceLocation: sourceLocation,
    beforePauseDrain: beforePauseDrain,
    activeJournalCommitLimit: StateJournal.defaultActiveCommitLimit,
    deadlinePolicy: deadlinePolicy,
    didFinishTeardown: _visorDidFinishTeardown,
    infrastructureIssueRecorder: infrastructureIssueRecorder,
    body)
}

@MainActor
private func observeImplementation<SUT: ViewModel>(
  _ sut: SUT,
  sourceLocation: SourceLocation,
  beforePauseDrain: @escaping @MainActor @Sendable () async -> Void,
  activeJournalCommitLimit: Int,
  outsideWindowCapacity: Int = StateJournal.defaultOutsideWindowCapacity,
  deadlinePolicy: _ObservationDeadlinePolicy,
  didFinishTeardown:
    @escaping @MainActor @Sendable () -> Void = {},
  infrastructureIssueRecorder:
    @escaping @MainActor (String, SourceLocation) -> Void,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  let state = sut.state
  guard state._visorMutationRecorder == nil else {
    infrastructureIssueRecorder(
      "This State already has an active observation scope",
      sourceLocation)
    return
  }

  let journal = StateJournal(
    activeCommitLimit: activeJournalCommitLimit,
    outsideWindowCapacity: outsideWindowCapacity)
  // The dormant recorder reserves this State identity before startup's first
  // suspension. It does not capture values until a perform window opens.
  state._visorMutationRecorder = journal
  let session = _ObservationSession(
    recipes: sut._visorMakeObservationRecipes(),
    _visorBeforePauseDrain: beforePauseDrain,
    _visorDeadlinePolicy: deadlinePolicy)
  let test = ObservationTest(
    sut: sut,
    state: state,
    journal: journal,
    session: session,
    infrastructureIssueRecorder: infrastructureIssueRecorder)
  journal.installFailureHandler { [weak test] error, sourceLocation in
    test?.journalFailed(error, sourceLocation: sourceLocation)
  }

  // A bounded stop may return before an uncooperative handler reaches its
  // true join. Keep the finished journal as a dormant, poisoned reservation
  // until that join, so no later observe scope can attach and receive writes
  // from the retired generation. Weak captures preserve escaped-handle/SUT
  // release while the State itself owns the exact reservation.
  session._visorWhenStopped { [weak state, weak journal] in
    if let state,
       let journal,
       state._visorMutationRecorder === journal
    {
      state._visorMutationRecorder = nil
    }
    didFinishTeardown()
  }

  do {
    try await session._visorStart()
  } catch is CancellationError {
    test.end()
    throw CancellationError()
  } catch {
    infrastructureIssueRecorder(
      "VISOR failed while starting observation: \(String(describing: error))",
      sourceLocation)
    test.end()
    return
  }

  guard sut.state === state else {
    infrastructureIssueRecorder(
      "VISOR failed while starting observation: stateIdentityChanged",
      sourceLocation)
    test.end()
    await session._visorStop()
    return
  }

  do {
    try await body(test)
    try Task.checkCancellation()
  } catch ObservationTestControlError.unavailableResult {
    test.end()
    await session._visorStop()
    test.reportUnobservedSessionFailure(
      session._visorFailure,
      sourceLocation: sourceLocation)
    return
  } catch {
    test.end()
    await session._visorStop()
    test.reportUnobservedSessionFailure(
      session._visorFailure,
      sourceLocation: sourceLocation)
    throw error
  }

  test.end()
  await session._visorStop()
  test.reportUnobservedSessionFailure(
    session._visorFailure,
    sourceLocation: sourceLocation)
}
