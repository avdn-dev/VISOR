import Foundation
import Observation
import os
import VISORObservation

// MARK: - _ViewModelObservationRequestSignal

/// A coalescing wake-up signal for the owner's latest desired policy state.
///
/// The lock protects only synchronous bookkeeping. Continuations are removed
/// under the lock and resumed afterwards, so no suspension or resumed work can
/// execute while the critical section is held.
nonisolated private final class _ViewModelObservationRequestSignal: Sendable {

  // MARK: Internal

  func yield() {
    let waiter: Waiter? = lock.withLock { state in
      guard !state.isFinished else { return nil }
      guard let waiter = state.waiter else {
        state.hasPendingRequest = true
        return nil
      }
      state.waiter = nil
      return waiter
    }
    waiter?.resume(returning: true)
  }

  func wait() async -> Bool {
    await withCheckedContinuation { continuation in
      let immediate: Bool? = lock.withLock { state in
        if state.isFinished {
          return false
        }
        if state.hasPendingRequest {
          state.hasPendingRequest = false
          return true
        }
        precondition(state.waiter == nil)
        state.waiter = continuation
        return nil
      }
      if let immediate {
        continuation.resume(returning: immediate)
      }
    }
  }

  func finish() {
    let waiter: Waiter? = lock.withLock { state in
      guard !state.isFinished else { return nil }
      state.isFinished = true
      state.hasPendingRequest = false
      defer { state.waiter = nil }
      return state.waiter
    }
    waiter?.resume(returning: false)
  }

  // MARK: Private

  private typealias Waiter = CheckedContinuation<Bool, Never>

  private struct State: Sendable {
    var hasPendingRequest = false
    var isFinished = false
    var waiter: Waiter?
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

}

// MARK: - _ViewModelObservationOwnerFailure

nonisolated package enum _ViewModelObservationOwnerFailure:
  Equatable,
  Sendable
{
  case duplicateOwner
  case infrastructure(_ObservationSourceFailure)
}

nonisolated private let _viewModelObservationOwnerLogger = Logger(
  subsystem: "VISOR",
  category: "ViewModelObservationOwner",
)

nonisolated private func reportViewModelObservationOwnerFailure(
  _ failure: _ViewModelObservationOwnerFailure
) {
  switch failure {
  case .duplicateOwner:
    _viewModelObservationOwnerLogger.error(
      "Rejected a duplicate production observation owner"
    )

  case .infrastructure(let failure):
    _viewModelObservationOwnerLogger.error(
      "Observation generation failed: \(String(describing: failure), privacy: .public)"
    )
  }
}

// MARK: - _ViewModelObservationOwner

/// The structured production owner hidden by `_ViewModelObservationHost`.
///
/// One invocation spans the SwiftUI host lifetime. Scene-policy changes are
/// synchronous requests into that lifetime; this owner serially joins the old
/// generation before it can open a fresh one.
@MainActor
@Observable
package final class _ViewModelObservationOwner<VM: ViewModel> {

  // MARK: Lifecycle

  package init(
    _visorDidBecomeReady:
    @escaping @MainActor @Sendable () -> Void = { },
    _visorDidFail:
    @escaping @MainActor @Sendable
    (_ViewModelObservationOwnerFailure) -> Void = {
      reportViewModelObservationOwnerFailure($0)
    },
    _visorWillStartGeneration:
    @escaping @MainActor @Sendable () -> Void = { },
    _visorDidStopGeneration:
    @escaping @MainActor @Sendable () -> Void = { },
    _visorDidClaimOwnership:
    @escaping @MainActor @Sendable () async -> Void = { },
    _visorDidEnterOwnershipWait:
    @escaping @MainActor @Sendable () -> Void = { },
    _visorDeadlinePolicy: _ObservationDeadlinePolicy = .production,
  ) {
    didBecomeReady = _visorDidBecomeReady
    didFail = _visorDidFail
    willStartGeneration = _visorWillStartGeneration
    didStopGeneration = _visorDidStopGeneration
    didClaimOwnership = _visorDidClaimOwnership
    didEnterOwnershipWait = _visorDidEnterOwnershipWait
    deadlinePolicy = _visorDeadlinePolicy
  }

  /// Works around a Swift 6.2.4 release optimiser crash for explicitly
  /// MainActor-isolated classes.
  deinit { }

  // MARK: Package

  package private(set) var _visorIsReady = false

  package private(set) var _visorFailure:
    _ViewModelObservationOwnerFailure?

  @ObservationIgnored package private(set) var _visorGenerationCount = 0

  package func _visorCanExposeContent(
    for viewModel: VM,
    isEnabled: Bool,
  ) -> Bool {
    isEnabled
      && _visorIsReady
      && ownership === viewModel._visorObservationOwnership
      && viewModel._visorObservationOwnership._visorIsActionable(
        ownerID: ObjectIdentifier(self)
      )
  }

  /// Runs the single structured root for one SwiftUI host lifetime.
  ///
  /// Cancellation normally joins the active generation before returning. If
  /// the private teardown deadline expires, the root may return while the one
  /// supervisor retains the graph; the identity lease remains releasing until
  /// that supervisor reports the eventual true join.
  package func _visorRun(
    viewModel: VM,
    initiallyEnabled: Bool,
  ) async {
    let candidate = viewModel._visorObservationOwnership
    let ownerID = ObjectIdentifier(self)
    guard !isRunning else { return }
    isRunning = true
    desiredIsEnabled = initiallyEnabled
    activationEpoch = initiallyEnabled ? ActivationEpoch() : nil
    failedActivationEpoch = nil
    failedGenerationID = nil
    reportedGenerationFailureID = nil
    generationAwaitingEventualJoinID = nil
    _visorIsReady = false
    _visorFailure = nil

    let requests = _ViewModelObservationRequestSignal()
    requestSignal = requests

    let claim = await withTaskCancellationHandler {
      let claim = await candidate._visorClaim(
        self,
        _visorDidEnterWait: didEnterOwnershipWait,
      )
      guard case .claimed = claim else { return claim }

      ownership = candidate
      // Package-only proof seam: the cancellation handler already protects
      // the newly acquired lease while this deliberate suspension is active.
      await didClaimOwnership()
      await runRequestLoop(viewModel: viewModel, requests: requests)
      return claim
    } onCancel: {
      // A replacement host may now wait for this exact joined hand-off rather
      // than being rejected or racing an early lease release.
      candidate._visorBeginRelease(ownerID: ownerID)
      // Wakes an idle request loop. An active generation separately observes
      // cancellation through its awaited session operation.
      requests.finish()
    }

    requests.finish()
    requestSignal = nil
    _visorIsReady = false
    let didJoin = await stopCurrentGeneration()
    if didJoin {
      candidate._visorRelease(ownerID: ownerID)
    } else if let generation {
      // The session's strongly retaining supervisor continues the real join.
      // Keep this identity lease in its releasing state until that hand-off is
      // truly safe, even though the cancelled SwiftUI root may now return.
      candidate._visorBeginRelease(ownerID: ownerID)
      generation.session._visorWhenStopped {
        candidate._visorRelease(ownerID: ownerID)
      }
    } else {
      candidate._visorRelease(ownerID: ownerID)
    }
    ownership = nil
    desiredIsEnabled = false
    isRunning = false

    if case .duplicateOwner = claim {
      _visorFailure = .duplicateOwner
      didFail(.duplicateOwner)
    }
  }

  /// Applies a scene-policy decision without creating an unstructured task.
  /// A disable request revokes readiness and requests cancellation before the
  /// caller can next observe owner state.
  package func _visorSetEnabled(_ enabled: Bool) {
    guard desiredIsEnabled != enabled else { return }
    desiredIsEnabled = enabled
    if enabled {
      // Each genuine disabled-to-enabled edge is a distinct retry authority.
      // A generation captures the epoch that opened it, so a delayed teardown
      // failure cannot consume a newer activation already queued by the host.
      activationEpoch = ActivationEpoch()
    } else {
      _visorIsReady = false
      generation?.session._visorRequestStop()
    }
    requestSignal?.yield()
  }

  // MARK: Private

  private struct ActivationEpoch: Equatable {
    let id = UUID()
  }

  private struct Generation {
    let id: UUID
    let activationEpoch: ActivationEpoch
    let session: _ObservationSession
  }

  @ObservationIgnored private let didBecomeReady: @MainActor @Sendable () -> Void

  @ObservationIgnored private let didFail:
    @MainActor @Sendable (_ViewModelObservationOwnerFailure) -> Void

  @ObservationIgnored private let willStartGeneration: @MainActor @Sendable () -> Void

  @ObservationIgnored private let didStopGeneration: @MainActor @Sendable () -> Void

  @ObservationIgnored private let didClaimOwnership: @MainActor @Sendable () async -> Void

  @ObservationIgnored private let didEnterOwnershipWait: @MainActor @Sendable () -> Void

  @ObservationIgnored private let deadlinePolicy: _ObservationDeadlinePolicy

  @ObservationIgnored private var generation: Generation?

  @ObservationIgnored private var ownership: _ViewModelObservationOwnership?

  @ObservationIgnored private var desiredIsEnabled = false

  @ObservationIgnored private var activationEpoch: ActivationEpoch?

  @ObservationIgnored private var failedActivationEpoch: ActivationEpoch?

  @ObservationIgnored private var isRunning = false

  @ObservationIgnored private var requestSignal: _ViewModelObservationRequestSignal?

  @ObservationIgnored private var failedGenerationID: UUID?

  @ObservationIgnored private var reportedGenerationFailureID: UUID?

  @ObservationIgnored private var generationAwaitingEventualJoinID: UUID?

  private var activationPermitsGeneration: Bool {
    guard desiredIsEnabled, let activationEpoch else { return false }
    return failedActivationEpoch != activationEpoch
  }

  private func runRequestLoop(
    viewModel: VM,
    requests: _ViewModelObservationRequestSignal,
  ) async {
    while !Task.isCancelled {
      // A deadline may let this control loop stop waiting while the single
      // teardown supervisor still owns the prior generation. No enable edge
      // can replace that retained generation before its eventual true join.
      if generation != nil {
        guard await requests.wait() else { return }
        continue
      }
      if activationPermitsGeneration {
        await runGeneration(viewModel: viewModel, requests: requests)
        continue
      }
      guard await requests.wait() else { return }
    }
  }

  private func runGeneration(
    viewModel: VM,
    requests: _ViewModelObservationRequestSignal,
  ) async {
    guard
      activationPermitsGeneration,
      let generationActivationEpoch = activationEpoch,
      !Task.isCancelled
    else {
      return
    }

    _visorFailure = nil
    failedGenerationID = nil
    failedActivationEpoch = nil
    willStartGeneration()

    let generationID = UUID()
    let session = _ObservationSession(
      recipes: viewModel._visorMakeObservationRecipes(),
      _visorOnFailure: { [weak self] failure in
        self?.recordTerminalFailure(
          .infrastructure(failure),
          generationID: generationID,
        )
        requests.yield()
      },
      _visorDeadlinePolicy: deadlinePolicy,
    )
    generation = Generation(
      id: generationID,
      activationEpoch: generationActivationEpoch,
      session: session,
    )
    _visorGenerationCount += 1

    do {
      try await session._visorStart()
      try Task.checkCancellation()
      guard
        generation?.id == generationID,
        desiredIsEnabled,
        activationEpoch == generationActivationEpoch,
        !session._visorIsStopping
      else {
        throw CancellationError()
      }

      _visorIsReady = true
      didBecomeReady()

      // Scene-policy requests and terminal failures wake the same owner loop.
      // Ignore a stale/coalesced wake while this generation remains healthy;
      // only its synchronous stopping state authorises bounded teardown.
      while !session._visorIsStopping {
        guard await requests.wait() else {
          throw CancellationError()
        }
      }
      if let failure = session._visorFailure {
        recordTerminalFailure(
          .infrastructure(failure),
          generationID: generationID,
        )
      }
    } catch is CancellationError {
      // Cancellation is the ordinary owner and scene-pause path.
    } catch {
      recordTerminalFailure(
        .infrastructure(.failed(String(describing: error))),
        generationID: generationID,
      )
    }

    // Readiness is revoked before cancellation becomes visible to children.
    if generation?.id == generationID {
      _visorIsReady = false
    }
    let didJoin = await stopSessionOnce(session)
    if didJoin {
      completeGenerationTeardown(generationID: generationID)
    } else {
      deferGenerationCompletionUntilEventualJoin(
        session: session,
        generationID: generationID,
      )
      reportGenerationFailureIfNeeded(generationID: generationID)
    }
  }

  @discardableResult
  private func stopCurrentGeneration() async -> Bool {
    _visorIsReady = false
    guard let generation else { return true }
    guard generationAwaitingEventualJoinID != generation.id else {
      return false
    }
    let didJoin = await stopSessionOnce(generation.session)
    if didJoin {
      completeGenerationTeardown(generationID: generation.id)
    } else {
      deferGenerationCompletionUntilEventualJoin(
        session: generation.session,
        generationID: generation.id,
      )
      reportGenerationFailureIfNeeded(generationID: generation.id)
    }
    return didJoin
  }

  private func stopSessionOnce(_ session: _ObservationSession) async -> Bool {
    if session._visorIsStopped { return true }
    session._visorRequestStop()
    return await session._visorStopWithinDeadline()
  }

  private func deferGenerationCompletionUntilEventualJoin(
    session: _ObservationSession,
    generationID: UUID,
  ) {
    guard generationAwaitingEventualJoinID != generationID else { return }
    generationAwaitingEventualJoinID = generationID
    session._visorWhenStopped { [weak self] in
      self?.completeGenerationTeardown(generationID: generationID)
    }
  }

  private func completeGenerationTeardown(generationID: UUID) {
    guard generation?.id == generationID else { return }
    generation = nil
    if generationAwaitingEventualJoinID == generationID {
      generationAwaitingEventualJoinID = nil
    }
    didStopGeneration()
    reportGenerationFailureIfNeeded(generationID: generationID)
    requestSignal?.yield()
  }

  private func reportGenerationFailureIfNeeded(generationID: UUID) {
    guard
      failedGenerationID == generationID,
      reportedGenerationFailureID != generationID,
      let failure = _visorFailure
    else { return }
    reportedGenerationFailureID = generationID
    didFail(failure)
  }

  private func recordTerminalFailure(
    _ failure: _ViewModelObservationOwnerFailure,
    generationID: UUID,
  ) {
    guard
      let generation,
      generation.id == generationID,
      failedGenerationID != generationID
    else {
      return
    }
    failedGenerationID = generationID
    failedActivationEpoch = generation.activationEpoch
    _visorIsReady = false
    _visorFailure = failure
  }

}
