import ConsumerModelsNonisolated
import ConsumerServices
import SwiftUI
import Testing
@testable import VISOR

@MainActor
private final class HostLifecycleEvent {
  private(set) var count = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

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

extension ViewModelObservationOwnerTests {
  @Test(
    "A mounted host gates content and joins observation before release",
    .timeLimit(.minutes(1)))
  @MainActor
  func mountedHostReadinessAndTeardown() async {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    statusService.publishSynchronously(.loading)

    let viewModel = SourceBackedViewModel(
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
}
