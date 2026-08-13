import ConsumerModelsNonisolated
import ConsumerServices
import SwiftUI
import Testing
@testable import VISOR

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
  private let service: SyncingService

  init(service: SyncingService) {
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
  @Test("Observation policies map every scene phase to the accepted lifetime")
  @MainActor
  func observationPolicyMapping() {
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

  @Test("An empty generated recipe crosses readiness without deadlock")
  @MainActor
  func emptyRecipeBecomesReady() async {
    let viewModel = CompileProofViewModel()
    let ready = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<CompileProofViewModel>(
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

  @Test("Content remains unavailable until complete session readiness")
  @MainActor
  func readinessPrecedesContentAndTeardownJoins() async {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    await service.publish(SyncSnapshot(revision: 4))
    await statusService.publish(.loading)
    let viewModel = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

    await service.publish(SyncSnapshot(revision: 5))
    #expect(viewModel.state.revision == 4)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test("A replacing host waits for joined teardown before claiming the lease")
  @MainActor
  func cancellationRetainsOwnerThroughJoinedTeardown() async {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    let viewModel = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let firstReady = OwnerEventCounter()
    let contenderFailed = OwnerEventCounter()
    let contenderReady = OwnerEventCounter()
    let contender = _ViewModelObservationOwner<SourceBackedViewModel>(
      _visorDidBecomeReady: { contenderReady.record() },
      _visorDidFail: { _ in contenderFailed.record() })

    let firstOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test(
    "A teardown deadline keeps the owner lease releasing until the true join")
  @MainActor
  func deadlineDoesNotReleaseOwnerBeforeEventualJoin() async {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    let viewModel = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let sleeper = OwnerDeadlineSleeper()
    let firstReady = OwnerEventCounter()
    let firstStopped = OwnerEventCounter()
    let firstOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
    let replacement = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test(
    "Scene disable reports its deadline and restarts only after the true join")
  @MainActor
  func sceneDisableWaitsForEventualJoinBeforeRestarting() async {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    let viewModel = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let sleeper = OwnerDeadlineSleeper()
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let failed = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test(
    "A cancelled replacement relinquishes a newly claimed lease before the next hand-off")
  @MainActor
  func cancellationBetweenClaimAndRootSetupCannotStrandTheLease() async {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    let viewModel = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)

    let firstReady = OwnerEventCounter()
    let firstOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
    let secondOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
    let thirdOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test("Startup failure never exposes content or retries")
  @MainActor
  func startupFailureIsFailClosed() async {
    let service = SyncingService()
    service.terminateObservationForProof()
    let viewModel = SourceBackedViewModel(service: service)
    let failed = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
    guard case .infrastructure = owner._visorFailure else {
      Issue.record("Expected an infrastructure failure")
      return
    }

    // Reasserting the current active state is not a lifecycle edge and must
    // not create an immediate retry loop.
    owner._visorSetEnabled(true)
    #expect(owner._visorGenerationCount == 1)
    #expect(failed.count == 1)

    hostLifetime.cancel()
    await hostLifetime.value
  }

  @Test("A fresh generation reconciles the latest complete snapshots")
  @MainActor
  func freshGenerationReconcilesBeforeReadiness() async {
    let service = SyncingService()
    let statusService = StatusService()
    await service.publish(SyncSnapshot(revision: 1))
    await statusService.publish(.ready)
    let viewModel = SourceBackedViewModel(
      service: service,
      statusService: statusService)
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
    await service.publish(SyncSnapshot(revision: 2))
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

  @Test("Rapid restart joins the old generation before opening the new one")
  @MainActor
  func rapidRestartDoesNotOverlapGenerations() async {
    let service = SyncingService()
    let viewModel = SourceBackedViewModel(service: service)
    let ready = OwnerEventCounter()
    let starts = GenerationStartProbe(service: service)
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test("Latest disabled request wins rapid false-true-false churn")
  @MainActor
  func rapidPolicyChurnRemainsStopped() async {
    let service = SyncingService()
    let viewModel = SourceBackedViewModel(service: service)
    let ready = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test("A second owner for one ViewModel identity is rejected")
  @MainActor
  func duplicateOwnerIsRejected() async {
    let service = SyncingService()
    let viewModel = SourceBackedViewModel(service: service)
    let firstReady = OwnerEventCounter()
    let secondFailed = OwnerEventCounter()
    let firstOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
      _visorDidBecomeReady: { firstReady.record() })
    let secondOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test("A new owner can claim the identity after joined hand-off")
  @MainActor
  func sequentialOwnerHandOff() async {
    let service = SyncingService()
    let viewModel = SourceBackedViewModel(service: service)
    let firstReady = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
    let secondOwner = _ViewModelObservationOwner<SourceBackedViewModel>(
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

  @Test(
    "Infrastructure failure waits for a later activation edge before retrying")
  @MainActor
  func infrastructureFailureEndsTheGeneration() async {
    let service = SyncingService()
    let viewModel = SourceBackedViewModel(service: service)
    let ready = OwnerEventCounter()
    let failed = OwnerEventCounter()
    let stopped = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
    guard case .infrastructure = owner._visorFailure else {
      Issue.record("Expected an infrastructure failure")
      return
    }

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

  @Test("Readiness cannot cross a ViewModel identity boundary")
  @MainActor
  func readinessIsScopedToViewModelIdentity() async {
    let firstViewModel = SourceBackedViewModel(service: SyncingService())
    let secondViewModel = SourceBackedViewModel(service: SyncingService())
    let ready = OwnerEventCounter()
    let owner = _ViewModelObservationOwner<SourceBackedViewModel>(
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
