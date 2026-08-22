import Foundation
import Testing
import VISOR

/// A failure produced by VISOR's test-observation control plane.
public enum ObservationTestError: Error, Equatable, Sendable {
  /// The requested operation could not run, so no result exists.
  case resultUnavailable
}

extension ObservationTestError: LocalizedError {
  /// A human-readable explanation suitable for a failed test diagnostic.
  public var errorDescription: String? {
    switch self {
    case .resultUnavailable:
      "The observation action could not run because its State window was unavailable. Review the recorded test issue for the underlying infrastructure failure."
    }
  }
}

enum ObservationTestControlError: Error {
  case stateIdentityChanged
}

enum ObservationTestPhase: Equatable {
  case ready
  case performing
  case cancellationPending
  case poisoned
  case ended
}

enum WindowTransition {
  case succeeded
  case unavailable
  case cancelled
}

package typealias ObservationTestIssueRecorder =
  @MainActor (String, SourceLocation) -> Void

/// A scoped handle for fencing one semantic action at a time and matching its
/// complete State mutation history.
@MainActor
public final class ObservationTest<SUT: ViewModel> {
  private var sut: SUT?
  private var state: SUT.State?
  private var journal: StateJournal?
  private var session: _ObservationSession?
  private var phase = ObservationTestPhase.ready
  private var hasReportedInfrastructureFailure = false
  private let issueRecorder: ObservationTestIssueRecorder

  init(
    sut: SUT,
    state: SUT.State,
    journal: StateJournal,
    session: _ObservationSession,
    issueRecorder: @escaping ObservationTestIssueRecorder
  ) {
    self.sut = sut
    self.state = state
    self.journal = journal
    self.session = session
    self.issueRecorder = issueRecorder
  }

  // Work around a Swift 6.2.4 release optimiser crash for explicitly
  // MainActor-isolated classes.
  deinit {}

  /// Performs one ViewModel action and fences all participating sources.
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

  /// Performs one nonthrowing asynchronous operation and fences its State writes.
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

  /// Performs one throwing Void operation and fences its State writes.
  /// - Throws: The operation's error after the observation window is closed.
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

  /// Performs one throwing value-producing operation and fences its State writes.
  /// - Returns: The operation's result after the observation window is closed.
  /// - Throws: Cancellation, the operation's error, or an unavailable-result
  ///   ``ObservationTestError/resultUnavailable`` if infrastructure fails
  ///   before the operation starts.
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
      throw ObservationTestError.resultUnavailable
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
      recordIssue(
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
      session._visorRequestStop()
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
  func reportSessionFailureIfNeeded(
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
    recordIssue(
      "VISOR failed while \(phase): \(String(describing: error))",
      sourceLocation: sourceLocation)
  }

  func journalFailed(
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
    // Make cancellation visible before reporting, because the issue recorder
    // may synchronously re-enter user code.
    session?._visorRequestStop()
    recordInfrastructureFailure(
      failure,
      phase: failurePhase,
      sourceLocation: sourceLocation)
  }

  private func recordEndedScopeMisuse(
    sourceLocation: SourceLocation
  ) {
    recordIssue(
      "This observation scope has ended",
      sourceLocation: sourceLocation)
  }

  func recordIssue(
    _ message: String,
    sourceLocation: SourceLocation
  ) {
    issueRecorder(message, sourceLocation)
  }

  func end() {
    guard phase != .ended else { return }
    phase = .ended
    journal?.finish()
    sut = nil
    state = nil
    journal = nil
    session = nil
  }

  func reportUnobservedSessionFailure(
    _ failure: (any Error)?,
    sourceLocation: SourceLocation
  ) {
    guard let failure else { return }
    recordInfrastructureFailure(
      failure,
      phase: "running the observation session",
      sourceLocation: sourceLocation)
  }

  func journalForExpectation(
    sourceLocation: SourceLocation
  ) -> StateJournal? {
    guard phase != .cancellationPending, phase != .poisoned else { return nil }
    guard phase != .ended, let journal else {
      recordEndedScopeMisuse(sourceLocation: sourceLocation)
      return nil
    }
    guard phase != .performing else {
      recordIssue(
        "expect requires a completed perform window",
        sourceLocation: sourceLocation)
      return nil
    }
    guard !reportSessionFailureIfNeeded(sourceLocation: sourceLocation) else {
      return nil
    }
    guard journal.hasClosedWindow else {
      recordIssue(
        "expect requires a completed perform window",
        sourceLocation: sourceLocation)
      return nil
    }
    return journal
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
      throw ObservationTestError.resultUnavailable
    }
    _ = try await session._visorWaitForFailure()
  }

}
