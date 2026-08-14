import Observation
import SwiftUI
import Testing
import VISORObservation
@testable import VISOR

private struct OwnerSnapshot: Sendable {
  let revision: Int
}

#if os(macOS)
@MainActor
private final class HostLifecycleEvent {
  private(set) var count = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

  deinit {}

  func record() {
    count += 1
    let waiters = waiters
    self.waiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }

  func wait() async {
    guard count == 0 else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

private final class HostLeaseCandidate: Sendable {}

@MainActor
@Observable
private final class HostScenePhase {
  var value: ScenePhase

  init(_ value: ScenePhase) {
    self.value = value
  }

  deinit {}
}

@MainActor
private struct ScenePhaseHost<Content: View>: View {
  private let phase: HostScenePhase
  private let content: Content

  init(
    phase: HostScenePhase,
    @ViewBuilder content: () -> Content
  ) {
    self.phase = phase
    self.content = content()
  }

  var body: some View {
    content.environment(\.scenePhase, phase.value)
  }
}

@MainActor
@LazyViewModel(OwnerSourceBackedViewModel.self)
private struct GeneratedOwnerScreen: View {
  let contentAppeared: HostLifecycleEvent
  let contentDisappeared: HostLifecycleEvent

  var content: some View {
    Text("Revision \(state.revision)")
      .onAppear { contentAppeared.record() }
      .onDisappear { contentDisappeared.record() }
  }
}

@MainActor
@LazyViewModel(
  OwnerSourceBackedViewModel.self,
  observationPolicy: .pauseWhenInactive)
private struct GeneratedScenePhaseOwnerScreen: View {
  let contentAppeared: OwnerEventCounter
  let contentDisappeared: OwnerEventCounter

  var content: some View {
    Text("Revision \(state.revision)")
      .onAppear { contentAppeared.record() }
      .onDisappear { contentDisappeared.record() }
  }
}

extension ViewModelObservationOwnerTests {
  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `Generated LazyViewModel waits for readiness and joins on removal`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    statusService.publishSynchronously(.loading)

    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let factory = OwnerSourceBackedViewModel.Factory { viewModel }
    let contentAppeared = HostLifecycleEvent()
    let contentDisappeared = HostLifecycleEvent()
    let root = AnyView(
      GeneratedOwnerScreen(
        contentAppeared: contentAppeared,
        contentDisappeared: contentDisappeared)
        .environment(factory))
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()

    await reactionGate.waitUntilStarted()
    #expect(contentAppeared.count == 0)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    reactionGate.open()
    await contentAppeared.wait()
    #expect(contentAppeared.count == 1)
    #expect(viewModel.state.reactedStatus == .loading)

    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()
    await contentDisappeared.wait()

    let candidate = HostLeaseCandidate()
    let claim = await viewModel._visorObservationOwnership
      ._visorClaim(candidate)
    guard case .claimed = claim else {
      Issue.record(
        "Generated LazyViewModel did not release its joined identity lease")
      return
    }

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    viewModel._visorObservationOwnership._visorRelease(
      ownerID: ObjectIdentifier(candidate))
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `A mounted pause-when-inactive host follows the injected scene phase`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let factory = OwnerSourceBackedViewModel.Factory { viewModel }
    let phase = HostScenePhase(.active)
    let contentAppeared = OwnerEventCounter()
    let contentDisappeared = OwnerEventCounter()
    let root = AnyView(
      ScenePhaseHost(phase: phase) {
        GeneratedScenePhaseOwnerScreen(
          contentAppeared: contentAppeared,
          contentDisappeared: contentDisappeared)
      }
      .environment(factory))
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()
    await contentAppeared.wait(for: 1)

    #expect(contentAppeared.count == 1)
    #expect(contentDisappeared.count == 0)
    #expect(viewModel.state.revision == 0)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    phase.value = .background
    hostingView.layoutSubtreeIfNeeded()
    await contentDisappeared.wait(for: 1)

    #expect(contentAppeared.count == 1)
    #expect(contentDisappeared.count == 1)
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    await service.publish(OwnerSnapshot(revision: 1))
    await statusService.publish(.loading)
    #expect(viewModel.state.revision == 0)
    #expect(viewModel.state.status == .idle)

    phase.value = .active
    hostingView.layoutSubtreeIfNeeded()
    await reactionGate.waitUntilStarted()

    #expect(contentAppeared.count == 1)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    reactionGate.open()
    await contentAppeared.wait(for: 2)

    #expect(contentAppeared.count == 2)
    #expect(contentDisappeared.count == 1)
    #expect(viewModel.state.revision == 1)
    #expect(viewModel.state.reactedRevision == 1)
    #expect(viewModel.state.status == .loading)
    #expect(viewModel.state.reactedStatus == .loading)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    phase.value = .inactive
    hostingView.layoutSubtreeIfNeeded()
    await contentDisappeared.wait(for: 2)

    #expect(contentAppeared.count == 2)
    #expect(contentDisappeared.count == 2)
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    await service.publish(OwnerSnapshot(revision: 2))
    await statusService.publish(.held)
    #expect(viewModel.state.revision == 1)
    #expect(viewModel.state.status == .loading)

    phase.value = .active
    hostingView.layoutSubtreeIfNeeded()
    await contentAppeared.wait(for: 3)

    #expect(contentAppeared.count == 3)
    #expect(contentDisappeared.count == 2)
    #expect(viewModel.state.revision == 2)
    #expect(viewModel.state.reactedRevision == 2)
    #expect(viewModel.state.status == .held)
    #expect(viewModel.state.reactedStatus == .held)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()
    await contentDisappeared.wait(for: 3)

    #expect(contentAppeared.count == 3)
    #expect(contentDisappeared.count == 3)

    let candidate = HostLeaseCandidate()
    let claim = await viewModel._visorObservationOwnership
      ._visorClaim(candidate)
    guard case .claimed = claim else {
      Issue.record(
        "The scene-phase host did not release its joined identity lease")
      return
    }

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    viewModel._visorObservationOwnership._visorRelease(
      ownerID: ObjectIdentifier(candidate))
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `A mounted host gates content and joins observation before release`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    statusService.publishSynchronously(.loading)

    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let contentAppeared = HostLifecycleEvent()
    let contentDisappeared = HostLifecycleEvent()

    let root = AnyView(
      _visorOwnedViewModelContent(for: viewModel) { _ in
        Text("Ready")
          .onAppear { contentAppeared.record() }
          .onDisappear { contentDisappeared.record() }
      })
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()

    await reactionGate.waitUntilStarted()
    #expect(contentAppeared.count == 0)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    reactionGate.open()
    await contentAppeared.wait()
    #expect(contentAppeared.count == 1)

    // Replacing the hosted root destroys the generated host and cancels its
    // single SwiftUI task. Disappearance gives us a lifecycle event rather
    // than a timing assumption about the AppKit run loop.
    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()
    await contentDisappeared.wait()

    // The identity lease is released only after the cancelled owner has joined
    // every session child. Acquiring it is therefore a deterministic teardown
    // barrier, after which no subscription from the removed host can remain.
    let candidate = HostLeaseCandidate()
    let claim = await viewModel._visorObservationOwnership
      ._visorClaim(candidate)
    guard case .claimed = claim else {
      Issue.record("The removed host did not release its joined identity lease")
      return
    }

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    viewModel._visorObservationOwnership._visorRelease(
      ownerID: ObjectIdentifier(candidate))
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `A mounted host replaces readiness progress with terminal failure UI`() async {
    let service = OwnerService()
    service.terminateObservationForProof()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let pendingAppeared = HostLifecycleEvent()
    let failureAppeared = HostLifecycleEvent()
    let contentAppeared = HostLifecycleEvent()

    let root = AnyView(
      _ViewModelObservationHost(
        viewModel: viewModel,
        observationPolicy: .alwaysObserving,
        content: { _ in
          Text("Ready")
            .onAppear { contentAppeared.record() }
        },
        suspended: { Color.clear },
        pending: {
          ProgressView("Preparing Screen")
            .onAppear { pendingAppeared.record() }
        },
        failure: {
          ContentUnavailableView(
            "Unable to Load",
            systemImage: "exclamationmark.triangle")
            .onAppear { failureAppeared.record() }
        }))
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()
    await pendingAppeared.wait()
    await failureAppeared.wait()

    #expect(pendingAppeared.count == 1)
    #expect(failureAppeared.count == 1)
    #expect(contentAppeared.count == 0)

    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()

    let candidate = HostLeaseCandidate()
    let claim = await viewModel._visorObservationOwnership
      ._visorClaim(candidate)
    guard case .claimed = claim else {
      Issue.record("The failed host did not release its identity lease")
      return
    }
    viewModel._visorObservationOwnership._visorRelease(
      ownerID: ObjectIdentifier(candidate))
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `A duplicate mounted owner presents failure instead of content`() async {
    let viewModel = OwnerEmptyViewModel()
    let contentAppeared = OwnerEventCounter()
    let failureAppeared = OwnerEventCounter()

    let root = AnyView(
      VStack {
        duplicateOwnerProofHost(
          viewModel: viewModel,
          contentAppeared: contentAppeared,
          failureAppeared: failureAppeared)
        duplicateOwnerProofHost(
          viewModel: viewModel,
          contentAppeared: contentAppeared,
          failureAppeared: failureAppeared)
      })
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()
    await contentAppeared.wait(for: 1)
    await failureAppeared.wait(for: 1)

    #expect(contentAppeared.count == 1)
    #expect(failureAppeared.count == 1)

    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()

    let candidate = HostLeaseCandidate()
    let claim = await viewModel._visorObservationOwnership
      ._visorClaim(candidate)
    guard case .claimed = claim else {
      Issue.record("The mounted owner did not release its identity lease")
      return
    }
    viewModel._visorObservationOwnership._visorRelease(
      ownerID: ObjectIdentifier(candidate))
  }

  @MainActor
  private func duplicateOwnerProofHost(
    viewModel: OwnerEmptyViewModel,
    contentAppeared: OwnerEventCounter,
    failureAppeared: OwnerEventCounter
  ) -> some View {
    _ViewModelObservationHost(
      viewModel: viewModel,
      observationPolicy: .alwaysObserving,
      content: { _ in
        Text("Ready")
          .onAppear { contentAppeared.record() }
      },
      suspended: { Color.clear },
      pending: { ProgressView("Preparing Screen") },
      failure: {
        ContentUnavailableView(
          "Unable to Load",
          systemImage: "exclamationmark.triangle")
          .onAppear { failureAppeared.record() }
      })
  }
}
#endif

private enum OwnerStatus: Sendable {
  case idle
  case loading
  case ready
  case held
}

private actor OwnerService {
  private let channel: ObservationChannel<OwnerSnapshot>
  nonisolated let source: ObservationSource<OwnerSnapshot>

  nonisolated var activeObservationCountForProof: Int {
    source._visorActiveSubscriptionCount
  }

  init(_ snapshot: OwnerSnapshot = OwnerSnapshot(revision: 0)) {
    let channel = ObservationChannel(snapshot)
    self.channel = channel
    source = channel.source
  }

  func publish(_ snapshot: OwnerSnapshot) {
    channel.publish(snapshot)
  }

  nonisolated func publishSynchronously(_ snapshot: OwnerSnapshot) {
    channel.publish(snapshot)
  }

  nonisolated func terminateObservationForProof() {
    channel._visorTerminate()
  }
}

private actor OwnerStatusService {
  private let channel: ObservationChannel<OwnerStatus>
  nonisolated let source: ObservationSource<OwnerStatus>

  nonisolated var activeObservationCountForProof: Int {
    source._visorActiveSubscriptionCount
  }

  init(_ status: OwnerStatus = .idle) {
    let channel = ObservationChannel(status)
    self.channel = channel
    source = channel.source
  }

  func publish(_ status: OwnerStatus) {
    channel.publish(status)
  }

  nonisolated func publishSynchronously(_ status: OwnerStatus) {
    channel.publish(status)
  }
}

@MainActor
private final class OwnerReactionGate {
  private var isOpen = false
  private var hasStarted = false
  private var openWaiters: [CheckedContinuation<Void, Never>] = []
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []

  deinit {}

  func suspend() async {
    hasStarted = true
    let started = startedWaiters
    startedWaiters.removeAll(keepingCapacity: false)
    for waiter in started {
      waiter.resume()
    }
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      openWaiters.append(continuation)
    }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { continuation in
      startedWaiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let waiters = openWaiters
    openWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }
}

@MainActor
@Observable
@ViewModel
private final class OwnerEmptyViewModel {
  final class State {
    var count = 0

    deinit {}
  }

  let state = State()

  deinit {}
}

@MainActor
@Observable
@ViewModel
private final class OwnerSourceBackedViewModel {
  final class State {
    @Bound(
      source: \OwnerSourceBackedViewModel.service.source,
      selecting: \OwnerSnapshot.revision)
    private(set) var revision = -1

    @Bound(source: \OwnerSourceBackedViewModel.statusService.source)
    private(set) var status = OwnerStatus.idle

    private(set) var reactedRevision = -1
    private(set) var reactedStatus = OwnerStatus.idle

    deinit {}
  }

  let state = State()
  let service: OwnerService
  let statusService: OwnerStatusService
  private let reactionGate: OwnerReactionGate?

  init(
    service: OwnerService,
    statusService: OwnerStatusService = OwnerStatusService(),
    reactionGate: OwnerReactionGate? = nil
  ) {
    self.service = service
    self.statusService = statusService
    self.reactionGate = reactionGate
  }

  @Reaction(
    source: \OwnerSourceBackedViewModel.service.source,
    selecting: \OwnerSnapshot.revision)
  private func revisionChanged(_ revision: Int) {
    updateState(\.reactedRevision, to: revision)
  }

  @Reaction(source: \OwnerSourceBackedViewModel.statusService.source)
  private func statusChanged(_ status: OwnerStatus) async {
    if status == .loading {
      await reactionGate?.suspend()
    }
    updateState(\.reactedStatus, to: status)
  }

  deinit {}
}


@MainActor
private final class OwnerEventCounter {
  private struct Waiter {
    let target: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private(set) var count = 0
  private var waiters: [Waiter] = []

  func record() {
    count += 1
    let completed = waiters.filter { $0.target <= count }
    waiters.removeAll { $0.target <= count }
    for waiter in completed {
      waiter.continuation.resume()
    }
  }

  func wait(for target: Int) async {
    guard count < target else { return }
    await withCheckedContinuation { continuation in
      waiters.append(Waiter(
        target: target,
        continuation: continuation))
    }
  }
}

@MainActor
private final class GenerationStartProbe {
  private(set) var activeSubscriptionCounts: [Int] = []
  private let service: OwnerService

  init(service: OwnerService) {
    self.service = service
  }

  func record() {
    activeSubscriptionCounts.append(
      service.activeObservationCountForProof)
  }
}

@MainActor
private final class OwnershipClaimGate {
  private var isOpen = false
  private var hasStarted = false
  private var openWaiters: [CheckedContinuation<Void, Never>] = []
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    hasStarted = true
    let startedWaiters = startedWaiters
    self.startedWaiters.removeAll()
    for waiter in startedWaiters { waiter.resume() }
    guard !isOpen else { return }
    await withCheckedContinuation { openWaiters.append($0) }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  func open() {
    isOpen = true
    let openWaiters = openWaiters
    self.openWaiters.removeAll()
    for waiter in openWaiters { waiter.resume() }
  }
}

@MainActor
private final class OwnerDeadlineSleeper {
  private struct Pending {
    let id: Int
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct ArmWaiter {
    let target: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private(set) var armCount = 0
  private var pending: [Pending] = []
  private var armWaiters: [ArmWaiter] = []

  func sleep(for _: Duration) async throws {
    let id = armCount
    armCount += 1
    let completed = armWaiters.filter { $0.target <= armCount }
    armWaiters.removeAll { $0.target <= armCount }
    for waiter in completed { waiter.continuation.resume() }

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        pending.append(Pending(id: id, continuation: continuation))
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancel(id: id)
      }
    }
  }

  func waitUntilArmed(_ target: Int) async {
    guard armCount < target else { return }
    await withCheckedContinuation { continuation in
      armWaiters.append(ArmWaiter(
        target: target,
        continuation: continuation))
    }
  }

  func fire(_ id: Int) {
    guard let index = pending.firstIndex(where: { $0.id == id }) else {
      return
    }
    pending.remove(at: index).continuation.resume()
  }

  private func cancel(id: Int) {
    guard let index = pending.firstIndex(where: { $0.id == id }) else {
      return
    }
    pending.remove(at: index).continuation.resume(
      throwing: CancellationError())
  }
}

@Suite("Structured production ViewModel owner", .serialized)
struct ViewModelObservationOwnerTests {
  @Test
  @MainActor
  func `Observation policies map every scene phase to the accepted lifetime`() {
    #expect(ObservationPolicy.alwaysObserving._visorIsEnabled(in: .active))
    #expect(ObservationPolicy.alwaysObserving._visorIsEnabled(in: .inactive))
    #expect(ObservationPolicy.alwaysObserving._visorIsEnabled(in: .background))

    #expect(ObservationPolicy.pauseInBackground._visorIsEnabled(in: .active))
    #expect(ObservationPolicy.pauseInBackground._visorIsEnabled(in: .inactive))
    #expect(!ObservationPolicy.pauseInBackground._visorIsEnabled(in: .background))

    #expect(ObservationPolicy.pauseWhenInactive._visorIsEnabled(in: .active))
    #expect(!ObservationPolicy.pauseWhenInactive._visorIsEnabled(in: .inactive))
    #expect(!ObservationPolicy.pauseWhenInactive._visorIsEnabled(in: .background))
  }

  @Test
  @MainActor
  func `An empty generated recipe crosses readiness without deadlock`() async {
    let viewModel = OwnerEmptyViewModel()
    let ready = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerEmptyViewModel>(
      _visorDidBecomeReady: { ready.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await ready.wait(for: 1)

    #expect(owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(owner._visorGenerationCount == 1)

    hostLifetime.cancel()
    await hostLifetime.value
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
  }

  @Test
  @MainActor
  func `Content remains unavailable until complete session readiness`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    await service.publish(OwnerSnapshot(revision: 4))
    await statusService.publish(.loading)
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidStopGeneration: { stopped.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }

    await reactionGate.waitUntilStarted()
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: false))
    #expect(viewModel.state.revision == 4)
    #expect(viewModel.state.reactedStatus == .idle)

    reactionGate.open()
    await ready.wait(for: 1)
    #expect(owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: false))
    #expect(viewModel.state.reactedStatus == .loading)

    owner._visorSetEnabled(false)
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    await stopped.wait(for: 1)

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    await service.publish(OwnerSnapshot(revision: 5))
    #expect(viewModel.state.revision == 4)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `A replacing host waits for joined teardown before claiming the lease`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let firstReady = OwnerEventCounter()
    let contenderFailed = OwnerEventCounter()
    let contenderReady = OwnerEventCounter()
    let contender = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { contenderReady.record() },
      _visorDidFail: { _ in contenderFailed.record() })

    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() })
    let hostLifetime = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }

    await firstReady.wait(for: 1)
    await statusService.publish(.loading)
    await reactionGate.waitUntilStarted()
    #expect(firstOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    hostLifetime.cancel()
    #expect(!firstOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(statusService.activeObservationCountForProof == 1)

    let replacementLifetime = Task { @MainActor in
      await contender._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    #expect(contenderFailed.count == 0)
    #expect(contenderReady.count == 0)
    #expect(service.activeObservationCountForProof == 1)

    reactionGate.open()
    await hostLifetime.value
    await contenderReady.wait(for: 1)
    #expect(contenderFailed.count == 0)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    replacementLifetime.cancel()
    await replacementLifetime.value
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `A teardown deadline keeps the owner lease releasing until the true join`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let sleeper = OwnerDeadlineSleeper()
    let firstReady = OwnerEventCounter()
    let firstStopped = OwnerEventCounter()
    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() },
      _visorDidStopGeneration: { firstStopped.record() },
      _visorDeadlinePolicy: _ObservationDeadlinePolicy { duration in
        try await sleeper.sleep(for: duration)
      })

    let firstLifetime = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await firstReady.wait(for: 1)
    let armsBeforeTeardown = sleeper.armCount

    await statusService.publish(.loading)
    await reactionGate.waitUntilStarted()
    firstLifetime.cancel()
    await sleeper.waitUntilArmed(armsBeforeTeardown + 1)
    sleeper.fire(armsBeforeTeardown)
    await firstLifetime.value

    #expect(firstStopped.count == 0)
    #expect(!firstOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))

    let replacementWaited = OwnerEventCounter()
    let replacementReady = OwnerEventCounter()
    let replacementFailed = OwnerEventCounter()
    let replacement = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { replacementReady.record() },
      _visorDidFail: { _ in replacementFailed.record() },
      _visorDidEnterOwnershipWait: { replacementWaited.record() })
    let replacementLifetime = Task { @MainActor in
      await replacement._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await replacementWaited.wait(for: 1)

    #expect(replacementReady.count == 0)
    #expect(replacementFailed.count == 0)
    #expect(firstStopped.count == 0)

    reactionGate.open()
    await firstStopped.wait(for: 1)
    await replacementReady.wait(for: 1)

    #expect(replacementFailed.count == 0)
    #expect(replacement._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    replacementLifetime.cancel()
    await replacementLifetime.value
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Scene disable reports its deadline and restarts only after the true join`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let sleeper = OwnerDeadlineSleeper()
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let failed = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidFail: { _ in failed.record() },
      _visorDidStopGeneration: { stopped.record() },
      _visorDeadlinePolicy: _ObservationDeadlinePolicy { duration in
        try await sleeper.sleep(for: duration)
      })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await ready.wait(for: 1)
    let armsBeforeTeardown = sleeper.armCount

    await statusService.publish(.loading)
    await reactionGate.waitUntilStarted()
    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)

    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(stopped.count == 0)
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
    #expect(owner._visorGenerationCount == 1)
    #expect(ready.count == 1)

    await sleeper.waitUntilArmed(armsBeforeTeardown + 1)
    sleeper.fire(armsBeforeTeardown)
    await failed.wait(for: 1)

    #expect(owner._visorGenerationCount == 1)
    #expect(stopped.count == 0)
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
    #expect(owner._visorGenerationCount == 1)
    #expect(ready.count == 1)
    #expect(stopped.count == 0)

    reactionGate.open()
    await stopped.wait(for: 1)
    await ready.wait(for: 2)

    #expect(owner._visorGenerationCount == 2)
    #expect(failed.count == 1)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    hostLifetime.cancel()
    await hostLifetime.value
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `A cancelled replacement relinquishes a newly claimed lease before the next hand-off`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = OwnerReactionGate()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)

    let firstReady = OwnerEventCounter()
    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() })
    let firstLifetime = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await firstReady.wait(for: 1)
    await statusService.publish(.loading)
    await reactionGate.waitUntilStarted()

    firstLifetime.cancel()

    let secondWaited = OwnerEventCounter()
    let secondClaimGate = OwnershipClaimGate()
    let secondFailed = OwnerEventCounter()
    let secondOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidFail: { _ in secondFailed.record() },
      _visorDidClaimOwnership: { await secondClaimGate.suspend() },
      _visorDidEnterOwnershipWait: { secondWaited.record() })
    let secondLifetime = Task { @MainActor in
      await secondOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await secondWaited.wait(for: 1)

    reactionGate.open()
    await firstLifetime.value
    await secondClaimGate.waitUntilStarted()

    // The cancellation handler already covers the acquired lease even though
    // this contender is still suspended immediately after its async claim.
    secondLifetime.cancel()

    let thirdWaited = OwnerEventCounter()
    let thirdReady = OwnerEventCounter()
    let thirdFailed = OwnerEventCounter()
    let thirdOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { thirdReady.record() },
      _visorDidFail: { _ in thirdFailed.record() },
      _visorDidEnterOwnershipWait: { thirdWaited.record() })
    let thirdLifetime = Task { @MainActor in
      await thirdOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await thirdWaited.wait(for: 1)

    #expect(secondFailed.count == 0)
    #expect(thirdFailed.count == 0)
    #expect(thirdReady.count == 0)
    #expect(service.activeObservationCountForProof == 0)

    secondClaimGate.open()
    await secondLifetime.value
    await thirdReady.wait(for: 1)

    #expect(secondOwner._visorFailure == nil)
    #expect(thirdOwner._visorFailure == nil)
    #expect(thirdOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(service.activeObservationCountForProof == 1)

    thirdLifetime.cancel()
    await thirdLifetime.value
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Startup failure never exposes content or retries`() async {
    let service = OwnerService()
    service.terminateObservationForProof()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let failed = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidFail: { _ in failed.record() },
      _visorDidStopGeneration: { stopped.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await failed.wait(for: 1)
    await stopped.wait(for: 1)

    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(service.activeObservationCountForProof == 0)
    #expect(owner._visorGenerationCount == 1)
    #expect(owner._visorFailure == .infrastructure(.unexpectedTermination))

    // Reasserting the current active state is not a lifecycle edge and must
    // not create an immediate retry loop.
    owner._visorSetEnabled(true)
    #expect(owner._visorGenerationCount == 1)
    #expect(failed.count == 1)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `A fresh generation reconciles the latest complete snapshots`() async {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    await service.publish(OwnerSnapshot(revision: 1))
    await statusService.publish(.ready)
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService)
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidStopGeneration: { stopped.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await ready.wait(for: 1)
    #expect(viewModel.state.revision == 1)
    #expect(viewModel.state.status == .ready)

    owner._visorSetEnabled(false)
    await stopped.wait(for: 1)
    await service.publish(OwnerSnapshot(revision: 2))
    await statusService.publish(.held)
    #expect(viewModel.state.revision == 1)
    #expect(viewModel.state.status == .ready)

    owner._visorSetEnabled(true)
    await ready.wait(for: 2)
    #expect(viewModel.state.revision == 2)
    #expect(viewModel.state.reactedRevision == 2)
    #expect(viewModel.state.status == .held)
    #expect(viewModel.state.reactedStatus == .held)
    #expect(owner._visorGenerationCount == 2)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `Rapid restart joins the old generation before opening the new one`() async {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let ready = OwnerEventCounter()
    let starts = GenerationStartProbe(service: service)
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorWillStartGeneration: { starts.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await ready.wait(for: 1)
    #expect(service.activeObservationCountForProof == 1)

    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)

    await ready.wait(for: 2)
    #expect(starts.activeSubscriptionCounts == [0, 0])
    #expect(service.activeObservationCountForProof == 1)
    #expect(owner._visorGenerationCount == 2)

    hostLifetime.cancel()
    await hostLifetime.value
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Latest disabled request wins rapid false-true-false churn`() async {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidStopGeneration: { stopped.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await ready.wait(for: 1)

    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)
    owner._visorSetEnabled(false)
    await stopped.wait(for: 1)

    #expect(owner._visorGenerationCount == 1)
    #expect(service.activeObservationCountForProof == 0)
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `A second owner for one ViewModel identity is rejected`() async {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let firstReady = OwnerEventCounter()
    let secondFailed = OwnerEventCounter()
    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() })
    let secondOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidFail: { _ in secondFailed.record() })

    let first = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await firstReady.wait(for: 1)

    await secondOwner._visorRun(
      viewModel: viewModel,
      initiallyEnabled: true)
    await secondFailed.wait(for: 1)

    #expect(secondOwner._visorFailure == .duplicateOwner)
    #expect(!secondOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(secondOwner._visorGenerationCount == 0)
    #expect(service.activeObservationCountForProof == 1)

    first.cancel()
    await first.value
  }

  @Test
  @MainActor
  func `A new owner can claim the identity after joined hand-off`() async {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let firstReady = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() })
    let first = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await firstReady.wait(for: 1)
    first.cancel()
    await first.value

    // Keep the retired owner strongly alive: the hand-off must depend on the
    // explicit post-join release, not a weak-reference side effect.
    #expect(service.activeObservationCountForProof == 0)

    let secondReady = OwnerEventCounter()
    let secondOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { secondReady.record() })
    let second = Task { @MainActor in
      await secondOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await secondReady.wait(for: 1)

    #expect(secondOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    withExtendedLifetime(owner) {}
    #expect(service.activeObservationCountForProof == 1)

    second.cancel()
    await second.value
  }

  @Test
  @MainActor
  func `Infrastructure failure waits for a later activation edge before retrying`() async {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let ready = OwnerEventCounter()
    let failed = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidFail: { _ in failed.record() },
      _visorDidStopGeneration: { stopped.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true)
    }
    await ready.wait(for: 1)

    service.terminateObservationForProof()
    await failed.wait(for: 1)
    await stopped.wait(for: 1)

    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true))
    #expect(service.activeObservationCountForProof == 0)
    #expect(owner._visorGenerationCount == 1)
    #expect(owner._visorFailure == .infrastructure(.unexpectedTermination))

    owner._visorSetEnabled(true)
    #expect(owner._visorGenerationCount == 1)
    #expect(failed.count == 1)

    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)
    await failed.wait(for: 2)
    await stopped.wait(for: 2)
    #expect(owner._visorGenerationCount == 2)
    #expect(failed.count == 2)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `Readiness cannot cross a ViewModel identity boundary`() async {
    let firstViewModel = OwnerSourceBackedViewModel(service: OwnerService())
    let secondViewModel = OwnerSourceBackedViewModel(service: OwnerService())
    let ready = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() })

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: firstViewModel,
        initiallyEnabled: true)
    }
    await ready.wait(for: 1)

    #expect(owner._visorCanExposeContent(
      for: firstViewModel,
      isEnabled: true))
    #expect(!owner._visorCanExposeContent(
      for: secondViewModel,
      isEnabled: true))

    hostLifetime.cancel()
    await hostLifetime.value
  }
}
