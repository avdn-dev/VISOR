import Testing
import VISOR

/// Starts the generated observation session and reconciles every source before
/// entering `body`.
///
/// Teardown normally joins before this function returns. If VISOR's private
/// safety deadline expires first, the function returns after reporting the
/// failure while retaining the State reservation until the session truly
/// joins, preventing a replacement scope from receiving retired writes.
///
/// The supplied ``ObservationTest`` handle is valid only inside `body`.
/// Each `perform` window records at most 8,000 raw State commits by default.
/// Use ``observe(_:maximumCommitCountPerAction:sourceLocation:_:)`` for an
/// intentional action that needs a larger bounded history.
/// - Throws: Cancellation or an error thrown by `body`.
@MainActor
public func observe<SUT: ViewModel>(
  _ sut: SUT,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observe(
    sut,
    maximumCommitCountPerAction:
      StateJournal.defaultMaximumCommitCountPerAction,
    sourceLocation: sourceLocation,
    body)
}

/// Starts a generated observation session with an explicit bound on the raw
/// State commits retained for each `perform` window.
///
/// The limit counts routed writes across every State field, including writes
/// that assign an equal value. Exceeding it fails the complete action window
/// closed and poisons the observation scope.
///
/// - Parameters:
///   - sut: The view model whose generated State is observed.
///   - maximumCommitCountPerAction: A positive per-action history bound. Choose
///     a value appropriate for an intentional high-volume action.
///   - sourceLocation: The call site reported for setup and teardown failures.
///   - body: The observation scope entered after every source is reconciled.
/// - Throws: Cancellation or an error thrown by `body`.
@MainActor
public func observe<SUT: ViewModel>(
  _ sut: SUT,
  maximumCommitCountPerAction: Int,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observeImplementation(
    sut,
    sourceLocation: sourceLocation,
    beforePauseDrain: {},
    maximumCommitCountPerAction: maximumCommitCountPerAction,
    deadlinePolicy: .production,
    issueRecorder: { message, sourceLocation in
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
    maximumCommitCountPerAction:
      StateJournal.defaultMaximumCommitCountPerAction,
    deadlinePolicy: .production,
    issueRecorder: { message, sourceLocation in
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
  logicalCommitLimit: Int =
    StateJournal.defaultMaximumCommitCountPerAction,
  outsideWindowCapacity: Int = StateJournal.defaultOutsideWindowCapacity,
  issueRecorder: @escaping ObservationTestIssueRecorder,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observeImplementation(
    sut,
    sourceLocation: sourceLocation,
    beforePauseDrain: {},
    maximumCommitCountPerAction: logicalCommitLimit,
    outsideWindowCapacity: outsideWindowCapacity,
    deadlinePolicy: .production,
    issueRecorder: issueRecorder,
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
  issueRecorder: @escaping ObservationTestIssueRecorder,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  try await observeImplementation(
    sut,
    sourceLocation: sourceLocation,
    beforePauseDrain: beforePauseDrain,
    maximumCommitCountPerAction:
      StateJournal.defaultMaximumCommitCountPerAction,
    deadlinePolicy: deadlinePolicy,
    didFinishTeardown: _visorDidFinishTeardown,
    issueRecorder: issueRecorder,
    body)
}

@MainActor
private func observeImplementation<SUT: ViewModel>(
  _ sut: SUT,
  sourceLocation: SourceLocation,
  beforePauseDrain: @escaping @MainActor @Sendable () async -> Void,
  maximumCommitCountPerAction: Int,
  outsideWindowCapacity: Int = StateJournal.defaultOutsideWindowCapacity,
  deadlinePolicy: _ObservationDeadlinePolicy,
  didFinishTeardown:
    @escaping @MainActor @Sendable () -> Void = {},
  issueRecorder: @escaping ObservationTestIssueRecorder,
  _ body: @MainActor (ObservationTest<SUT>) async throws -> Void
) async throws {
  guard maximumCommitCountPerAction > 0 else {
    issueRecorder(
      "maximumCommitCountPerAction must be greater than zero",
      sourceLocation)
    return
  }

  let state = sut.state
  guard state._visorMutationRecorder == nil else {
    issueRecorder(
      "This State already has an active observation scope",
      sourceLocation)
    return
  }

  let journal = StateJournal(
    maximumCommitCountPerAction: maximumCommitCountPerAction,
    outsideWindowCapacity: outsideWindowCapacity,
    issueRecorder: issueRecorder)
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
    issueRecorder: issueRecorder)
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
    issueRecorder(
      "VISOR failed while starting observation: \(String(describing: error))",
      sourceLocation)
    test.end()
    return
  }

  guard sut.state === state else {
    issueRecorder(
      "VISOR failed while starting observation: stateIdentityChanged",
      sourceLocation)
    test.end()
    await session._visorStop()
    return
  }

  do {
    try await body(test)
    try Task.checkCancellation()
  } catch ObservationTestError.resultUnavailable {
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
