import Observation
import SwiftUI
import Testing
import VISORObservation
import VISORTesting
@testable import VISOR

// MARK: - OwnerSnapshot

private struct OwnerSnapshot: Sendable {
  let revision: Int
}

#if os(macOS)
private final class HostLeaseCandidate: Sendable { }

@MainActor
@Observable
private final class HostScenePhase {

  // MARK: Lifecycle

  init(_ value: ScenePhase) {
    self.value = value
  }

  deinit { }

  // MARK: Internal

  var value: ScenePhase

}

@MainActor
private struct ScenePhaseHost<Content: View>: View {
  init(
    phase: HostScenePhase,
    @ViewBuilder content: () -> Content,
  ) {
    self.phase = phase
    self.content = content()
  }

  var body: some View {
    content.environment(\.scenePhase, phase.value)
  }

  private let phase: HostScenePhase
  private let content: Content

}

@MainActor
@LazyViewModel(OwnerSourceBackedViewModel.self)
private struct GeneratedOwnerScreen: View {
  let contentAppeared: TestEventCounter
  let contentDisappeared: TestEventCounter

  var content: some View {
    Text("Revision \(state.revision)")
      .onAppear(perform: contentAppeared.record)
      .onDisappear(perform: contentDisappeared.record)
  }
}

@MainActor
@LazyViewModel(
  OwnerSourceBackedViewModel.self,
  observationPolicy: .pauseWhenInactive,
)
private struct GeneratedScenePhaseOwnerScreen: View {
  let contentAppeared: TestEventCounter
  let contentDisappeared: TestEventCounter

  var content: some View {
    Text("Revision \(state.revision)")
      .onAppear(perform: contentAppeared.record)
      .onDisappear(perform: contentDisappeared.record)
  }
}

extension ViewModelObservationOwnerTests {

  // MARK: Internal

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `Generated LazyViewModel waits for readiness and joins on removal`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    statusService.publishSynchronously(.loading)

    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )
    let factory = OwnerSourceBackedViewModel.Factory { viewModel }
    let contentAppeared = TestEventCounter()
    let contentDisappeared = TestEventCounter()
    let root = AnyView(
      GeneratedOwnerScreen(
        contentAppeared: contentAppeared,
        contentDisappeared: contentDisappeared,
      )
      .environment(factory)
    )
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()

    try await reactionGate.waitUntilStarted()
    #expect(contentAppeared.count == 0)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    reactionGate.resolveAllInvocations(with: .success(()))
    try await contentAppeared.wait()
    #expect(contentAppeared.count == 1)
    #expect(viewModel.state.reactedStatus == .loading)

    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()
    try await contentDisappeared.wait()

    let candidate = HostLeaseCandidate()
    let claim = await viewModel._visorObservationOwnership
      ._visorClaim(candidate)
    guard case .claimed = claim else {
      Issue.record(
        "Generated LazyViewModel did not release its joined identity lease"
      )
      return
    }

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    viewModel._visorObservationOwnership._visorRelease(
      ownerID: ObjectIdentifier(candidate)
    )
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `A mounted pause-when-inactive host follows the injected scene phase`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )
    let factory = OwnerSourceBackedViewModel.Factory { viewModel }
    let phase = HostScenePhase(.active)
    let contentAppeared = TestEventCounter()
    let contentDisappeared = TestEventCounter()
    let root = AnyView(
      ScenePhaseHost(phase: phase) {
        GeneratedScenePhaseOwnerScreen(
          contentAppeared: contentAppeared,
          contentDisappeared: contentDisappeared,
        )
      }
      .environment(factory)
    )
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()
    try await contentAppeared.wait(untilEventCount: 1)

    #expect(contentAppeared.count == 1)
    #expect(contentDisappeared.count == 0)
    #expect(viewModel.state.revision == 0)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    phase.value = .background
    hostingView.layoutSubtreeIfNeeded()
    try await contentDisappeared.wait(untilEventCount: 1)

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
    try await reactionGate.waitUntilStarted()

    #expect(contentAppeared.count == 1)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    reactionGate.resolveAllInvocations(with: .success(()))
    try await contentAppeared.wait(untilEventCount: 2)

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
    try await contentDisappeared.wait(untilEventCount: 2)

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
    try await contentAppeared.wait(untilEventCount: 3)

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
    try await contentDisappeared.wait(untilEventCount: 3)

    #expect(contentAppeared.count == 3)
    #expect(contentDisappeared.count == 3)

    let candidate = HostLeaseCandidate()
    let claim = await viewModel._visorObservationOwnership
      ._visorClaim(candidate)
    guard case .claimed = claim else {
      Issue.record(
        "The scene-phase host did not release its joined identity lease"
      )
      return
    }

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    viewModel._visorObservationOwnership._visorRelease(
      ownerID: ObjectIdentifier(candidate)
    )
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `A mounted host gates content and joins observation before release`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    statusService.publishSynchronously(.loading)

    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )
    let contentAppeared = TestEventCounter()
    let contentDisappeared = TestEventCounter()

    let root = AnyView(
      _visorOwnedViewModelContent(for: viewModel) { _ in
        Text("Ready")
          .onAppear(perform: contentAppeared.record)
          .onDisappear(perform: contentDisappeared.record)
      }
    )
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()

    try await reactionGate.waitUntilStarted()
    #expect(contentAppeared.count == 0)
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    reactionGate.resolveAllInvocations(with: .success(()))
    try await contentAppeared.wait()
    #expect(contentAppeared.count == 1)

    // Replacing the hosted root destroys the generated host and cancels its
    // single SwiftUI task. Disappearance gives us a lifecycle event rather
    // than a timing assumption about the AppKit run loop.
    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()
    try await contentDisappeared.wait()

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
      ownerID: ObjectIdentifier(candidate)
    )
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `The custom bridge replaces readiness progress with terminal failure UI`() async throws {
    let service = OwnerService()
    service.terminateObservationForProof()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let pendingAppeared = TestEventCounter()
    let failureAppeared = TestEventCounter()
    let contentAppeared = TestEventCounter()

    let root = AnyView(
      _visorOwnedViewModelContent(
        for: viewModel,
        pending: {
          ProgressView("Preparing profile")
            .onAppear(perform: pendingAppeared.record)
        },
        failure: {
          ContentUnavailableView(
            "Profile Unavailable",
            systemImage: "person.crop.circle.badge.exclamationmark",
          )
          .onAppear(perform: failureAppeared.record)
        },
      ) { _ in
        Text("Ready")
          .onAppear(perform: contentAppeared.record)
      }
    )
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()
    try await pendingAppeared.wait()
    try await failureAppeared.wait()

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
      ownerID: ObjectIdentifier(candidate)
    )
  }

  @Test(.timeLimit(.minutes(1)))
  @MainActor
  func `A duplicate mounted owner presents failure instead of content`() async throws {
    let viewModel = OwnerEmptyViewModel()
    let contentAppeared = TestEventCounter()
    let failureAppeared = TestEventCounter()

    let root = AnyView(
      VStack {
        duplicateOwnerProofHost(
          viewModel: viewModel,
          contentAppeared: contentAppeared,
          failureAppeared: failureAppeared,
        )
        duplicateOwnerProofHost(
          viewModel: viewModel,
          contentAppeared: contentAppeared,
          failureAppeared: failureAppeared,
        )
      }
    )
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

    hostingView.layoutSubtreeIfNeeded()
    try await contentAppeared.wait(untilEventCount: 1)
    try await failureAppeared.wait(untilEventCount: 1)

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
      ownerID: ObjectIdentifier(candidate)
    )
  }

  // MARK: Private

  @MainActor
  private func duplicateOwnerProofHost(
    viewModel: OwnerEmptyViewModel,
    contentAppeared: TestEventCounter,
    failureAppeared: TestEventCounter,
  ) -> some View {
    _ViewModelObservationHost(
      viewModel: viewModel,
      observationPolicy: .alwaysObserving,
      content: { _ in
        Text("Ready")
          .onAppear(perform: contentAppeared.record)
      },
      suspended: { Color.clear },
      pending: { ProgressView("Preparing Screen") },
      failure: {
        ContentUnavailableView(
          "Unable to Load",
          systemImage: "exclamationmark.triangle",
        )
        .onAppear(perform: failureAppeared.record)
      },
    )
  }
}
#endif

// MARK: - OwnerStatus

private enum OwnerStatus: Sendable {
  case idle
  case loading
  case ready
  case held
}

// MARK: - OwnerService

private actor OwnerService {

  // MARK: Lifecycle

  init(_ snapshot: OwnerSnapshot = OwnerSnapshot(revision: 0)) {
    let channel = ObservationChannel(snapshot)
    self.channel = channel
    source = channel.source
  }

  // MARK: Internal

  nonisolated let source: ObservationSource<OwnerSnapshot>

  nonisolated var activeObservationCountForProof: Int {
    source._visorActiveSubscriptionCount
  }

  func publish(_ snapshot: OwnerSnapshot) {
    channel.publish(snapshot)
  }

  nonisolated func terminateObservationForProof() {
    channel._visorTerminate()
  }

  // MARK: Private

  private let channel: ObservationChannel<OwnerSnapshot>

}

// MARK: - OwnerStatusService

private actor OwnerStatusService {

  // MARK: Lifecycle

  init(_ status: OwnerStatus = .idle) {
    let channel = ObservationChannel(status)
    self.channel = channel
    source = channel.source
  }

  // MARK: Internal

  nonisolated let source: ObservationSource<OwnerStatus>

  nonisolated var activeObservationCountForProof: Int {
    source._visorActiveSubscriptionCount
  }

  func publish(_ status: OwnerStatus) {
    channel.publish(status)
  }

  nonisolated func publishSynchronously(_ status: OwnerStatus) {
    channel.publish(status)
  }

  // MARK: Private

  private let channel: ObservationChannel<OwnerStatus>

}

// MARK: - OwnerEmptyViewModel

@MainActor
@Observable
@ViewModel
private final class OwnerEmptyViewModel {

  // MARK: Lifecycle

  deinit { }

  // MARK: Internal

  final class State {

    // MARK: Lifecycle

    deinit { }

    // MARK: Internal

    var count = 0

  }

  let state = State()

}

// MARK: - OwnerSourceBackedViewModel

@MainActor
@Observable
@ViewModel
private final class OwnerSourceBackedViewModel {

  // MARK: Lifecycle

  init(
    service: OwnerService,
    statusService: OwnerStatusService = OwnerStatusService(),
    reactionGate: ControllableOperation<Void, Never>? = nil,
  ) {
    self.service = service
    self.statusService = statusService
    self.reactionGate = reactionGate
  }

  deinit { }

  // MARK: Internal

  final class State {

    // MARK: Lifecycle

    deinit { }

    // MARK: Internal

    @Bound(
      source: \OwnerSourceBackedViewModel.service.source,
      selecting: \OwnerSnapshot.revision,
    )
    private(set) var revision = -1

    @Bound(source: \OwnerSourceBackedViewModel.statusService.source)
    private(set) var status = OwnerStatus.idle

    private(set) var reactedRevision = -1
    private(set) var reactedStatus = OwnerStatus.idle

  }

  let state = State()
  let service: OwnerService
  let statusService: OwnerStatusService

  // MARK: Private

  private let reactionGate: ControllableOperation<Void, Never>?

  @Reaction(
    source: \OwnerSourceBackedViewModel.service.source,
    selecting: \OwnerSnapshot.revision,
  )
  private func revisionChanged(_ revision: Int) {
    updateState(\.reactedRevision, to: revision)
  }

  @Reaction(source: \OwnerSourceBackedViewModel.statusService.source)
  private func statusChanged(_ status: OwnerStatus) async {
    if status == .loading {
      if let reactionGate {
        await reactionGate.run(reactionGate.prepare())
      }
    }
    updateState(\.reactedStatus, to: status)
  }

}

// MARK: - GenerationStartProbe

@MainActor
private final class GenerationStartProbe {

  // MARK: Lifecycle

  init(service: OwnerService) {
    self.service = service
  }

  // MARK: Internal

  private(set) var activeSubscriptionCounts = [Int]()

  func record() {
    activeSubscriptionCounts.append(
      service.activeObservationCountForProof
    )
  }

  // MARK: Private

  private let service: OwnerService

}

// MARK: - ViewModelObservationOwnerTests

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
  func `An empty generated recipe crosses readiness without deadlock`() async throws {
    let viewModel = OwnerEmptyViewModel()
    let ready = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerEmptyViewModel>(
      _visorDidBecomeReady: { ready.record() }
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await ready.wait(untilEventCount: 1)

    #expect(owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(owner._visorGenerationCount == 1)

    hostLifetime.cancel()
    await hostLifetime.value
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
  }

  @Test
  @MainActor
  func `Content remains unavailable until complete session readiness`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    await service.publish(OwnerSnapshot(revision: 4))
    await statusService.publish(.loading)
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )
    let ready = TestEventCounter()
    let stopped = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidStopGeneration: { stopped.record() },
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }

    try await reactionGate.waitUntilStarted()
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: false,
    ))
    #expect(viewModel.state.revision == 4)
    #expect(viewModel.state.reactedStatus == .idle)

    reactionGate.resolveAllInvocations(with: .success(()))
    try await ready.wait(untilEventCount: 1)
    #expect(owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: false,
    ))
    #expect(viewModel.state.reactedStatus == .loading)

    owner._visorSetEnabled(false)
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    try await stopped.wait(untilEventCount: 1)

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)

    await service.publish(OwnerSnapshot(revision: 5))
    #expect(viewModel.state.revision == 4)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `A replacing host waits for joined teardown before claiming the lease`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )
    let firstReady = TestEventCounter()
    let contenderFailed = TestEventCounter()
    let contenderReady = TestEventCounter()
    let contender = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { contenderReady.record() },
      _visorDidFail: { _ in contenderFailed.record() },
    )

    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() }
    )
    let hostLifetime = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }

    try await firstReady.wait(untilEventCount: 1)
    await statusService.publish(.loading)
    try await reactionGate.waitUntilStarted()
    #expect(firstOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    hostLifetime.cancel()
    #expect(!firstOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(statusService.activeObservationCountForProof == 1)

    let replacementLifetime = Task { @MainActor in
      await contender._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    #expect(contenderFailed.count == 0)
    #expect(contenderReady.count == 0)
    #expect(service.activeObservationCountForProof == 1)

    reactionGate.resolveAllInvocations(with: .success(()))
    await hostLifetime.value
    try await contenderReady.wait(untilEventCount: 1)
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
  func `A teardown deadline keeps the owner lease releasing until the true join`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )
    let sleeper = ManualSleeper()
    let firstReady = TestEventCounter()
    let firstStopped = TestEventCounter()
    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() },
      _visorDidStopGeneration: { firstStopped.record() },
      _visorDeadlinePolicy: _ObservationDeadlinePolicy(
        readiness: .zero,
        openingFence: .zero,
        closingFence: .zero,
        fence: .zero,
        teardownJoin: .zero,
        _visorWatchdogFactory: sleeper.makeSleep,
      ),
    )

    let firstLifetime = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await firstReady.wait(untilEventCount: 1)
    let sleepsBeforeTeardown = sleeper.sleepCount

    await statusService.publish(.loading)
    try await reactionGate.waitUntilStarted()
    firstLifetime.cancel()
    let teardownSleep = try await sleeper.waitUntilPrepared(
      sleepsBeforeTeardown + 1
    )
    sleeper.wake(teardownSleep)
    await firstLifetime.value

    #expect(firstStopped.count == 0)
    #expect(!firstOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))

    let replacementWaited = TestEventCounter()
    let replacementReady = TestEventCounter()
    let replacementFailed = TestEventCounter()
    let replacement = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { replacementReady.record() },
      _visorDidFail: { _ in replacementFailed.record() },
      _visorDidEnterOwnershipWait: { replacementWaited.record() },
    )
    let replacementLifetime = Task { @MainActor in
      await replacement._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await replacementWaited.wait(untilEventCount: 1)

    #expect(replacementReady.count == 0)
    #expect(replacementFailed.count == 0)
    #expect(firstStopped.count == 0)

    reactionGate.resolveAllInvocations(with: .success(()))
    try await firstStopped.wait(untilEventCount: 1)
    try await replacementReady.wait(untilEventCount: 1)

    #expect(replacementFailed.count == 0)
    #expect(replacement._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(service.activeObservationCountForProof == 1)
    #expect(statusService.activeObservationCountForProof == 1)

    replacementLifetime.cancel()
    await replacementLifetime.value
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Scene disable reports its deadline and restarts only after the true join`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )
    let sleeper = ManualSleeper()
    let ready = TestEventCounter()
    let stopped = TestEventCounter()
    let failed = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidFail: { _ in failed.record() },
      _visorDidStopGeneration: { stopped.record() },
      _visorDeadlinePolicy: _ObservationDeadlinePolicy(
        readiness: .zero,
        openingFence: .zero,
        closingFence: .zero,
        fence: .zero,
        teardownJoin: .zero,
        _visorWatchdogFactory: sleeper.makeSleep,
      ),
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await ready.wait(untilEventCount: 1)
    let sleepsBeforeTeardown = sleeper.sleepCount

    await statusService.publish(.loading)
    try await reactionGate.waitUntilStarted()
    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)

    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(stopped.count == 0)
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
    #expect(owner._visorGenerationCount == 1)
    #expect(ready.count == 1)

    let teardownSleep = try await sleeper.waitUntilPrepared(
      sleepsBeforeTeardown + 1
    )
    sleeper.wake(teardownSleep)
    try await failed.wait(untilEventCount: 1)

    #expect(owner._visorGenerationCount == 1)
    #expect(stopped.count == 0)
    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
    #expect(owner._visorGenerationCount == 1)
    #expect(ready.count == 1)
    #expect(stopped.count == 0)

    reactionGate.resolveAllInvocations(with: .success(()))
    try await stopped.wait(untilEventCount: 1)
    try await ready.wait(untilEventCount: 2)

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
  func `A cancelled replacement relinquishes a newly claimed lease before the next hand-off`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    let reactionGate = ControllableOperation<Void, Never>()
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate,
    )

    let firstReady = TestEventCounter()
    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() }
    )
    let firstLifetime = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await firstReady.wait(untilEventCount: 1)
    await statusService.publish(.loading)
    try await reactionGate.waitUntilStarted()

    firstLifetime.cancel()

    let secondWaited = TestEventCounter()
    let secondClaimGate = ControllableOperation<Void, Never>()
    let secondFailed = TestEventCounter()
    let secondOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidFail: { _ in secondFailed.record() },
      _visorDidClaimOwnership: { await secondClaimGate.run(secondClaimGate.prepare()) },
      _visorDidEnterOwnershipWait: { secondWaited.record() },
    )
    let secondLifetime = Task { @MainActor in
      await secondOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await secondWaited.wait(untilEventCount: 1)

    reactionGate.resolveAllInvocations(with: .success(()))
    await firstLifetime.value
    try await secondClaimGate.waitUntilStarted()

    // The cancellation handler already covers the acquired lease even though
    // this contender is still suspended immediately after its async claim.
    secondLifetime.cancel()

    let thirdWaited = TestEventCounter()
    let thirdReady = TestEventCounter()
    let thirdFailed = TestEventCounter()
    let thirdOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { thirdReady.record() },
      _visorDidFail: { _ in thirdFailed.record() },
      _visorDidEnterOwnershipWait: { thirdWaited.record() },
    )
    let thirdLifetime = Task { @MainActor in
      await thirdOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await thirdWaited.wait(untilEventCount: 1)

    #expect(secondFailed.count == 0)
    #expect(thirdFailed.count == 0)
    #expect(thirdReady.count == 0)
    #expect(service.activeObservationCountForProof == 0)

    secondClaimGate.resolveAllInvocations(with: .success(()))
    await secondLifetime.value
    try await thirdReady.wait(untilEventCount: 1)

    #expect(secondOwner._visorFailure == nil)
    #expect(thirdOwner._visorFailure == nil)
    #expect(thirdOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(service.activeObservationCountForProof == 1)

    thirdLifetime.cancel()
    await thirdLifetime.value
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Startup failure never exposes content or retries`() async throws {
    let service = OwnerService()
    service.terminateObservationForProof()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let failed = TestEventCounter()
    let stopped = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidFail: { _ in failed.record() },
      _visorDidStopGeneration: { stopped.record() },
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await failed.wait(untilEventCount: 1)
    try await stopped.wait(untilEventCount: 1)

    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
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
  func `A fresh generation reconciles the latest complete snapshots`() async throws {
    let service = OwnerService()
    let statusService = OwnerStatusService()
    await service.publish(OwnerSnapshot(revision: 1))
    await statusService.publish(.ready)
    let viewModel = OwnerSourceBackedViewModel(
      service: service,
      statusService: statusService,
    )
    let ready = TestEventCounter()
    let stopped = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidStopGeneration: { stopped.record() },
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await ready.wait(untilEventCount: 1)
    #expect(viewModel.state.revision == 1)
    #expect(viewModel.state.status == .ready)

    owner._visorSetEnabled(false)
    try await stopped.wait(untilEventCount: 1)
    await service.publish(OwnerSnapshot(revision: 2))
    await statusService.publish(.held)
    #expect(viewModel.state.revision == 1)
    #expect(viewModel.state.status == .ready)

    owner._visorSetEnabled(true)
    try await ready.wait(untilEventCount: 2)
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
  func `Rapid restart joins the old generation before opening the new one`() async throws {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let ready = TestEventCounter()
    let starts = GenerationStartProbe(service: service)
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorWillStartGeneration: { starts.record() },
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await ready.wait(untilEventCount: 1)
    #expect(service.activeObservationCountForProof == 1)

    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)

    try await ready.wait(untilEventCount: 2)
    #expect(starts.activeSubscriptionCounts == [0, 0])
    #expect(service.activeObservationCountForProof == 1)
    #expect(owner._visorGenerationCount == 2)

    hostLifetime.cancel()
    await hostLifetime.value
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Latest disabled request wins rapid false-true-false churn`() async throws {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let ready = TestEventCounter()
    let stopped = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidStopGeneration: { stopped.record() },
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await ready.wait(untilEventCount: 1)

    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)
    owner._visorSetEnabled(false)
    try await stopped.wait(untilEventCount: 1)

    #expect(owner._visorGenerationCount == 1)
    #expect(service.activeObservationCountForProof == 0)
    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `A second owner for one ViewModel identity is rejected`() async throws {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let firstReady = TestEventCounter()
    let secondFailed = TestEventCounter()
    let firstOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() }
    )
    let secondOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidFail: { _ in secondFailed.record() }
    )

    let first = Task { @MainActor in
      await firstOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await firstReady.wait(untilEventCount: 1)

    await secondOwner._visorRun(
      viewModel: viewModel,
      initiallyEnabled: true,
    )
    try await secondFailed.wait(untilEventCount: 1)

    #expect(secondOwner._visorFailure == .duplicateOwner)
    #expect(!secondOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(secondOwner._visorGenerationCount == 0)
    #expect(service.activeObservationCountForProof == 1)

    first.cancel()
    await first.value
  }

  @Test
  @MainActor
  func `A new owner can claim the identity after joined hand-off`() async throws {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let firstReady = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() }
    )
    let first = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await firstReady.wait(untilEventCount: 1)
    first.cancel()
    await first.value

    // Keep the retired owner strongly alive: the hand-off must depend on the
    // explicit post-join release, not a weak-reference side effect.
    #expect(service.activeObservationCountForProof == 0)

    let secondReady = TestEventCounter()
    let secondOwner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { secondReady.record() }
    )
    let second = Task { @MainActor in
      await secondOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await secondReady.wait(untilEventCount: 1)

    #expect(secondOwner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    withExtendedLifetime(owner) { }
    #expect(service.activeObservationCountForProof == 1)

    second.cancel()
    await second.value
  }

  @Test
  @MainActor
  func `Infrastructure failure waits for a later activation edge before retrying`() async throws {
    let service = OwnerService()
    let viewModel = OwnerSourceBackedViewModel(service: service)
    let ready = TestEventCounter()
    let failed = TestEventCounter()
    let stopped = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidFail: { _ in failed.record() },
      _visorDidStopGeneration: { stopped.record() },
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: true,
      )
    }
    try await ready.wait(untilEventCount: 1)

    service.terminateObservationForProof()
    try await failed.wait(untilEventCount: 1)
    try await stopped.wait(untilEventCount: 1)

    #expect(!owner._visorCanExposeContent(
      for: viewModel,
      isEnabled: true,
    ))
    #expect(service.activeObservationCountForProof == 0)
    #expect(owner._visorGenerationCount == 1)
    #expect(owner._visorFailure == .infrastructure(.unexpectedTermination))

    owner._visorSetEnabled(true)
    #expect(owner._visorGenerationCount == 1)
    #expect(failed.count == 1)

    owner._visorSetEnabled(false)
    owner._visorSetEnabled(true)
    try await failed.wait(untilEventCount: 2)
    try await stopped.wait(untilEventCount: 2)
    #expect(owner._visorGenerationCount == 2)
    #expect(failed.count == 2)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test
  @MainActor
  func `Readiness cannot cross a ViewModel identity boundary`() async throws {
    let firstViewModel = OwnerSourceBackedViewModel(service: OwnerService())
    let secondViewModel = OwnerSourceBackedViewModel(service: OwnerService())
    let ready = TestEventCounter()
    let owner = _ViewModelObservationOwner<OwnerSourceBackedViewModel>(
      _visorDidBecomeReady: { ready.record() }
    )

    let hostLifetime = Task { @MainActor in
      await owner._visorRun(
        viewModel: firstViewModel,
        initiallyEnabled: true,
      )
    }
    try await ready.wait(untilEventCount: 1)

    #expect(owner._visorCanExposeContent(
      for: firstViewModel,
      isEnabled: true,
    ))
    #expect(!owner._visorCanExposeContent(
      for: secondViewModel,
      isEnabled: true,
    ))

    hostLifetime.cancel()
    await hostLifetime.value
  }
}
