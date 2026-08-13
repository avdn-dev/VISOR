import Observation
import os
import SwiftUI

/// A coalescing wake-up signal for the owner's latest desired policy state.
///
/// The lock protects only synchronous bookkeeping. Continuations are removed
/// under the lock and resumed afterwards, so no suspension or resumed work can
/// execute while the critical section is held.
nonisolated private final class _ViewModelObservationRequestSignal: Sendable {
  private typealias Waiter = CheckedContinuation<Bool, Never>

  private struct State: Sendable {
    var hasPendingRequest = false
    var isFinished = false
    var waiter: Waiter?
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

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
}

/// An inert identity token emitted by `@ViewModel`.
///
/// Generated downstream code can construct and carry this token, but only
/// VISOR can use it to claim production observation ownership.
/// Result of attempting to acquire a ViewModel's observation identity lease.
nonisolated package enum _ViewModelObservationOwnershipClaim {
  case claimed
  case duplicateOwner
  case cancelled
}

public final class _ViewModelObservationOwnership: Sendable {
  private typealias Waiter = CheckedContinuation<Bool, Never>

  private struct State: Sendable {
    var ownerID: ObjectIdentifier?
    var isReleasing = false
    var waiters: [UUID: Waiter] = [:]
  }

  private enum ImmediateClaim {
    case claimed
    case duplicateOwner
    case wait
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  public init() {}

  /// Claims immediately unless another active owner holds the lease. When the
  /// holder is already releasing, waits for that specific joined hand-off.
  @MainActor
  package func _visorClaim(
    _ candidate: AnyObject,
    _visorDidEnterWait: @MainActor @Sendable () -> Void = {}
  ) async -> _ViewModelObservationOwnershipClaim {
    let candidateID = ObjectIdentifier(candidate)
    while !Task.isCancelled {
      let immediate: ImmediateClaim = lock.withLock { state in
        // Cancellation may arrive after the loop condition but before this
        // critical section. Never create a lease for an already-cancelled root.
        guard !Task.isCancelled else { return .wait }
        guard let ownerID = state.ownerID else {
          state.ownerID = candidateID
          state.isReleasing = false
          return .claimed
        }
        if ownerID == candidateID {
          return state.isReleasing ? .wait : .claimed
        }
        return state.isReleasing ? .wait : .duplicateOwner
      }

      switch immediate {
      case .claimed:
        return .claimed
      case .duplicateOwner:
        return .duplicateOwner
      case .wait:
        guard !Task.isCancelled else { return .cancelled }
        guard await waitForRelease(
          _visorDidEnterWait: _visorDidEnterWait)
        else {
          return .cancelled
        }
      }
    }
    return .cancelled
  }

  /// Makes a cancelled root non-actionable to new claimants without releasing
  /// its lease before its complete observation generation has joined.
  nonisolated package func _visorBeginRelease(
    ownerID: ObjectIdentifier
  ) {
    lock.withLock { state in
      guard state.ownerID == ownerID else { return }
      state.isReleasing = true
    }
  }

  /// Whether this owner still holds an active, non-releasing lease.
  /// Readiness gates consult this so root cancellation becomes fail-closed in
  /// the cancellation handler, before MainActor teardown can resume.
  package func _visorIsActionable(ownerID: ObjectIdentifier) -> Bool {
    lock.withLock { state in
      state.ownerID == ownerID && !state.isReleasing
    }
  }

  package func _visorRelease(ownerID: ObjectIdentifier) {
    let waiters: [Waiter] = lock.withLock { state in
      guard state.ownerID == ownerID else { return [] }
      state.ownerID = nil
      state.isReleasing = false
      let waiters = Array(state.waiters.values)
      state.waiters.removeAll(keepingCapacity: false)
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: true)
    }
  }

  @MainActor
  private func waitForRelease(
    _visorDidEnterWait: @MainActor @Sendable () -> Void
  ) async -> Bool {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let immediate: Bool? = lock.withLock { state in
          guard !Task.isCancelled else { return false }
          guard state.ownerID != nil, state.isReleasing else {
            return true
          }
          state.waiters[id] = continuation
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        } else {
          _visorDidEnterWait()
        }
      }
    } onCancel: {
      let waiter = lock.withLock { state in
        state.waiters.removeValue(forKey: id)
      }
      waiter?.resume(returning: false)
    }
  }
}

nonisolated package enum _ViewModelObservationOwnerFailure:
  Equatable,
  Sendable
{
  case duplicateOwner
  case infrastructure(String)
}

nonisolated private let _viewModelObservationOwnerLogger = Logger(
  subsystem: "VISOR",
  category: "ViewModelObservationOwner")

nonisolated private func reportViewModelObservationOwnerFailure(
  _ failure: _ViewModelObservationOwnerFailure
) {
  switch failure {
  case .duplicateOwner:
    _viewModelObservationOwnerLogger.error(
      "Rejected a duplicate production observation owner")
  case .infrastructure(let detail):
    _viewModelObservationOwnerLogger.error(
      "Observation generation failed: \(detail, privacy: .public)")
  }
}

/// The structured production owner hidden by `_ViewModelObservationHost`.
///
/// One invocation spans the SwiftUI host lifetime. Scene-policy changes are
/// synchronous requests into that lifetime; this owner serially joins the old
/// generation before it can open a fresh one.
@MainActor
@Observable
package final class _ViewModelObservationOwner<VM: ViewModel> {
  private struct ActivationEpoch: Equatable {
    let id = UUID()
  }

  private struct Generation {
    let id: UUID
    let activationEpoch: ActivationEpoch
    let session: _ObservationSession
  }

  package private(set) var _visorIsReady = false

  @ObservationIgnored
  package private(set) var _visorFailure:
    _ViewModelObservationOwnerFailure?

  @ObservationIgnored
  package private(set) var _visorGenerationCount = 0

  @ObservationIgnored
  private let didBecomeReady: @MainActor @Sendable () -> Void

  @ObservationIgnored
  private let didFail:
    @MainActor @Sendable (_ViewModelObservationOwnerFailure) -> Void

  @ObservationIgnored
  private let willStartGeneration: @MainActor @Sendable () -> Void

  @ObservationIgnored
  private let didStopGeneration: @MainActor @Sendable () -> Void

  @ObservationIgnored
  private let didClaimOwnership: @MainActor @Sendable () async -> Void

  @ObservationIgnored
  private let didEnterOwnershipWait: @MainActor @Sendable () -> Void

  @ObservationIgnored
  private let deadlinePolicy: _ObservationDeadlinePolicy

  @ObservationIgnored
  private var generation: Generation?

  @ObservationIgnored
  private var ownership: _ViewModelObservationOwnership?

  @ObservationIgnored
  private var desiredIsEnabled = false

  @ObservationIgnored
  private var activationEpoch: ActivationEpoch?

  @ObservationIgnored
  private var failedActivationEpoch: ActivationEpoch?

  @ObservationIgnored
  private var isRunning = false

  @ObservationIgnored
  private var requestSignal: _ViewModelObservationRequestSignal?

  @ObservationIgnored
  private var failedGenerationID: UUID?

  @ObservationIgnored
  private var reportedGenerationFailureID: UUID?

  @ObservationIgnored
  private var generationAwaitingEventualJoinID: UUID?

  package init(
    _visorDidBecomeReady:
      @escaping @MainActor @Sendable () -> Void = {},
    _visorDidFail:
      @escaping @MainActor @Sendable
        (_ViewModelObservationOwnerFailure) -> Void = {
          reportViewModelObservationOwnerFailure($0)
        },
    _visorWillStartGeneration:
      @escaping @MainActor @Sendable () -> Void = {},
    _visorDidStopGeneration:
      @escaping @MainActor @Sendable () -> Void = {},
    _visorDidClaimOwnership:
      @escaping @MainActor @Sendable () async -> Void = {},
    _visorDidEnterOwnershipWait:
      @escaping @MainActor @Sendable () -> Void = {},
    _visorDeadlinePolicy: _ObservationDeadlinePolicy = .production
  ) {
    didBecomeReady = _visorDidBecomeReady
    didFail = _visorDidFail
    willStartGeneration = _visorWillStartGeneration
    didStopGeneration = _visorDidStopGeneration
    didClaimOwnership = _visorDidClaimOwnership
    didEnterOwnershipWait = _visorDidEnterOwnershipWait
    deadlinePolicy = _visorDeadlinePolicy
  }

  // Works around a Swift 6.2.4 release optimiser crash for explicitly
  // MainActor-isolated classes.
  deinit {}

  package func _visorCanExposeContent(
    for viewModel: VM,
    isEnabled: Bool
  ) -> Bool {
    isEnabled
      && _visorIsReady
      && ownership === viewModel._visorObservationOwnership
      && viewModel._visorObservationOwnership._visorIsActionable(
        ownerID: ObjectIdentifier(self))
  }

  /// Runs the single structured root for one SwiftUI host lifetime.
  ///
  /// Cancellation normally joins the active generation before returning. If
  /// the private teardown deadline expires, the root may return while the one
  /// supervisor retains the graph; the identity lease remains releasing until
  /// that supervisor reports the eventual true join.
  package func _visorRun(
    viewModel: VM,
    initiallyEnabled: Bool
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
        _visorDidEnterWait: didEnterOwnershipWait)
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

  private func runRequestLoop(
    viewModel: VM,
    requests: _ViewModelObservationRequestSignal
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
    requests: _ViewModelObservationRequestSignal
  ) async {
    guard activationPermitsGeneration,
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
          .infrastructure(String(describing: failure)),
          generationID: generationID)
        requests.yield()
      },
      _visorDeadlinePolicy: deadlinePolicy)
    generation = Generation(
      id: generationID,
      activationEpoch: generationActivationEpoch,
      session: session)
    _visorGenerationCount += 1

    do {
      try await session._visorStart()
      try Task.checkCancellation()
      guard generation?.id == generationID,
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
          .infrastructure(String(describing: failure)),
          generationID: generationID)
      }
    } catch is CancellationError {
      // Cancellation is the ordinary owner and scene-pause path.
    } catch {
      recordTerminalFailure(
        .infrastructure(String(describing: error)),
        generationID: generationID)
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
        generationID: generationID)
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
        generationID: generation.id)
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
    generationID: UUID
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
    guard failedGenerationID == generationID,
          reportedGenerationFailureID != generationID,
          let failure = _visorFailure
    else { return }
    reportedGenerationFailureID = generationID
    didFail(failure)
  }

  private func recordTerminalFailure(
    _ failure: _ViewModelObservationOwnerFailure,
    generationID: UUID
  ) {
    guard let generation,
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

  private var activationPermitsGeneration: Bool {
    guard desiredIsEnabled, let activationEpoch else { return false }
    return failedActivationEpoch != activationEpoch
  }
}

/// SwiftUI bridge used by generated `@LazyViewModel` bodies.
///
/// The content closure receives only the ViewModel. It cannot acquire a
/// session, readiness handle, cancellation hook or any other lifecycle
/// capability.
@MainActor
package struct _ViewModelObservationHost<
  VM: ViewModel,
  Content: View,
  Placeholder: View
>: View {
  @State private var owner: _ViewModelObservationOwner<VM>?
  @Environment(\.scenePhase) private var scenePhase

  private let viewModel: VM
  private let observationPolicy: ObservationPolicy
  private let content: (VM) -> Content
  private let placeholder: () -> Placeholder

  package init(
    viewModel: VM,
    observationPolicy: ObservationPolicy,
    @ViewBuilder content: @escaping (VM) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.viewModel = viewModel
    self.observationPolicy = observationPolicy
    self.content = content
    self.placeholder = placeholder
  }

  package var body: some View {
    Group {
      if let owner,
         owner._visorCanExposeContent(
           for: viewModel,
           isEnabled: isEnabled)
      {
        content(viewModel)
      } else {
        placeholder()
      }
    }
    .task {
      // Every SwiftUI task lifetime receives a fresh contender. If a prior
      // lifetime is still joining, the ViewModel token serialises hand-off.
      let activeOwner = _ViewModelObservationOwner<VM>()
      owner = activeOwner
      await activeOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: isEnabled)
    }
    .onChange(of: isEnabled) { _, enabled in
      owner?._visorSetEnabled(enabled)
    }
  }

  private var isEnabled: Bool {
    observationPolicy._visorIsEnabled(in: scenePhase)
  }
}

extension _ViewModelObservationHost where Placeholder == Color {
  package init(
    viewModel: VM,
    observationPolicy: ObservationPolicy,
    @ViewBuilder content: @escaping (VM) -> Content
  ) {
    self.init(
      viewModel: viewModel,
      observationPolicy: observationPolicy,
      content: content,
      placeholder: { Color.clear })
  }
}

/// The only production-owner bridge named by generated downstream code.
/// Its opaque result hides the concrete host and all lifecycle capabilities.
@MainActor
public func _visorOwnedViewModelContent<VM, Content>(
  for viewModel: VM,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  @ViewBuilder content: @escaping (VM) -> Content
) -> some View where VM: ViewModel, Content: View {
  _ViewModelObservationHost(
    viewModel: viewModel,
    observationPolicy: observationPolicy,
    content: content)
    .id(ObjectIdentifier(viewModel._visorObservationOwnership))
}
