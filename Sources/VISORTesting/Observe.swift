import Testing
import VISOR

/// Starts the generated observation session and reconciles every source before
/// entering `body`.
///
/// Teardown normally joins before this function returns. If VISOR's private
/// safety deadline expires first, the function returns after reporting the
/// failure while retaining the State reservation until the session truly
/// joins, preventing a replacement scope from receiving retired writes.
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
