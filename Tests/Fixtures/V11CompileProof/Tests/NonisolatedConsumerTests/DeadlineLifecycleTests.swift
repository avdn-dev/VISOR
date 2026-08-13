import ConsumerModelsNonisolated
import ConsumerServices
import Testing
import VISOR
import VISORTesting

private enum DeadlineLifecycleError: Error {
  case action
  case body
}

@MainActor
private final class TestingDeadlineSleeper {
  private struct Pending {
    let id: Int
    let duration: Duration
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct ArmWaiter {
    let duration: Duration
    let continuation: CheckedContinuation<Int, Never>
  }

  private var nextID = 0
  private var pending: [Pending] = []
  private var waiters: [ArmWaiter] = []

  func sleep(for duration: Duration) async throws {
    let id = nextID
    nextID += 1
    let matching = waiters.filter { $0.duration == duration }
    waiters.removeAll { $0.duration == duration }
    for waiter in matching {
      waiter.continuation.resume(returning: id)
    }

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        pending.append(Pending(
          id: id,
          duration: duration,
          continuation: continuation))
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.cancel(id: id)
      }
    }
  }

  func waitUntilArmed(for duration: Duration) async -> Int {
    if let pending = pending.last(where: { $0.duration == duration }) {
      return pending.id
    }
    return await withCheckedContinuation { continuation in
      waiters.append(ArmWaiter(
        duration: duration,
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

@MainActor
private final class DeadlineActionGate {
  private var hasStarted = false
  private var isOpen = false
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    hasStarted = true
    let started = startedWaiters
    startedWaiters.removeAll()
    for waiter in started { waiter.resume() }
    guard !isOpen else { return }
    await withCheckedContinuation { openWaiters.append($0) }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  func open() {
    isOpen = true
    let waiters = openWaiters
    openWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

@MainActor
private final class NthPauseGate {
  private let target: Int
  private var count = 0
  private var hasStarted = false
  private var isOpen = false
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  init(target: Int) {
    self.target = target
  }

  func visit() async {
    count += 1
    guard count == target else { return }
    hasStarted = true
    let started = startedWaiters
    startedWaiters.removeAll()
    for waiter in started { waiter.resume() }
    guard !isOpen else { return }
    await withCheckedContinuation { openWaiters.append($0) }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  func open() {
    isOpen = true
    let waiters = openWaiters
    openWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

@MainActor
private final class DeadlineIssueLog {
  struct Entry {
    let message: String
    let location: SourceLocation
  }

  private(set) var entries: [Entry] = []

  func record(_ message: String, at location: SourceLocation) {
    entries.append(Entry(message: message, location: location))
  }
}

@MainActor
private final class TestingDeadlineSignal {
  private var hasFired = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !hasFired else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func fire() {
    guard !hasFired else { return }
    hasFired = true
    let waiters = waiters
    self.waiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

@MainActor
private func testingDeadlinePolicy(
  sleeper: TestingDeadlineSleeper
) -> _ObservationDeadlinePolicy {
  _ObservationDeadlinePolicy(
    readiness: .seconds(1),
    openingFence: .seconds(2),
    closingFence: .seconds(3),
    fence: .seconds(4),
    teardownJoin: .seconds(5),
    sleeper: { duration in
      try await sleeper.sleep(for: duration)
    })
}

@Suite("Testing DSL control-plane deadlines")
struct DeadlineLifecycleTests {
  @Test
  @MainActor
  func `Readiness deadline reports at observe and withholds the body`() async throws {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    await statusService.publish(.loading)
    let sut = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let sleeper = TestingDeadlineSleeper()
    let issues = DeadlineIssueLog()
    let observeLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/startup",
      filePath: "/DeadlineLifecycleTests/startup.swift",
      line: 123,
      column: 4)
    var enteredBody = false

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        sourceLocation: observeLocation,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        infrastructureIssueRecorder: issues.record
      ) { _ in
        enteredBody = true
      }
    }

    await reactionGate.waitUntilStarted()
    let readinessWatchdog = await sleeper.waitUntilArmed(for: .seconds(1))
    sleeper.fire(readinessWatchdog)
    let teardownWatchdog = await sleeper.waitUntilArmed(for: .seconds(5))
    sleeper.fire(teardownWatchdog)
    try await observation.value

    #expect(!enteredBody)
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == observeLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while starting observation:") == true)

    reactionGate.open()
  }

  @Test
  @MainActor
  func `A suspended user action receives no VISOR deadline`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    let sleeper = TestingDeadlineSleeper()
    let actionGate = DeadlineActionGate()
    let issues = DeadlineIssueLog()
    var actionCompleted = false

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        infrastructureIssueRecorder: issues.record
      ) { test in
        await test.perform {
          await actionGate.suspend()
          actionCompleted = true
        }
        test.expect(\.revision, hasExactChanges: [])
      }
    }

    await actionGate.waitUntilStarted()
    #expect(!actionCompleted)
    #expect(issues.entries.isEmpty)

    actionGate.open()
    try await observation.value
    #expect(actionCompleted)
    #expect(issues.entries.isEmpty)
  }

  @Test
  @MainActor
  func `Opening deadline reports at perform and suppresses the action`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    let sleeper = TestingDeadlineSleeper()
    let openingGate = NthPauseGate(target: 1)
    let issues = DeadlineIssueLog()
    let performLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/opening",
      filePath: "/DeadlineLifecycleTests/opening.swift",
      line: 234,
      column: 5)
    var actionRan = false

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        beforePauseDrain: openingGate.visit,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        infrastructureIssueRecorder: issues.record
      ) { test in
        await test.perform({ actionRan = true }, sourceLocation: performLocation)
      }
    }

    await openingGate.waitUntilStarted()
    let openingWatchdog = await sleeper.waitUntilArmed(for: .seconds(2))
    sleeper.fire(openingWatchdog)
    let teardownWatchdog = await sleeper.waitUntilArmed(for: .seconds(5))
    sleeper.fire(teardownWatchdog)
    try await observation.value

    #expect(!actionRan)
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == performLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while opening an action window:") == true)

    openingGate.open()
  }

  @Test
  @MainActor
  func `Closing deadline preserves a produced result at perform`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    let sleeper = TestingDeadlineSleeper()
    let closingGate = NthPauseGate(target: 2)
    let issues = DeadlineIssueLog()
    let performLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/result",
      filePath: "/DeadlineLifecycleTests/result.swift",
      line: 321,
      column: 9)
    var result: Int?

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        beforePauseDrain: closingGate.visit,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        infrastructureIssueRecorder: issues.record
      ) { test in
        result = try await test.perform(
          { 42 },
          sourceLocation: performLocation)
      }
    }

    await closingGate.waitUntilStarted()
    let closingWatchdog = await sleeper.waitUntilArmed(for: .seconds(3))
    sleeper.fire(closingWatchdog)
    let teardownWatchdog = await sleeper.waitUntilArmed(for: .seconds(5))
    sleeper.fire(teardownWatchdog)
    try await observation.value

    #expect(result == 42)
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == performLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while closing an action window:") == true)

    closingGate.open()
  }

  @Test
  @MainActor
  func `Closing deadline preserves the exact action error`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    let sleeper = TestingDeadlineSleeper()
    let closingGate = NthPauseGate(target: 2)
    let issues = DeadlineIssueLog()

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        beforePauseDrain: closingGate.visit,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        infrastructureIssueRecorder: issues.record
      ) { test in
        await #expect(throws: DeadlineLifecycleError.action) {
          try await test.perform {
            throw DeadlineLifecycleError.action
          }
        }
      }
    }

    await closingGate.waitUntilStarted()
    let closingWatchdog = await sleeper.waitUntilArmed(for: .seconds(3))
    sleeper.fire(closingWatchdog)
    let teardownWatchdog = await sleeper.waitUntilArmed(for: .seconds(5))
    sleeper.fire(teardownWatchdog)
    try await observation.value

    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while closing an action window:") == true)

    closingGate.open()
  }

  @Test
  @MainActor
  func `Teardown deadline preserves body error and observe attribution`() async {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    let sut = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let sleeper = TestingDeadlineSleeper()
    let issues = DeadlineIssueLog()
    let observeLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/body",
      filePath: "/DeadlineLifecycleTests/body.swift",
      line: 654,
      column: 7)

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        sourceLocation: observeLocation,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        infrastructureIssueRecorder: issues.record
      ) { _ in
        await statusService.publish(.loading)
        await reactionGate.waitUntilStarted()
        throw DeadlineLifecycleError.body
      }
    }

    await reactionGate.waitUntilStarted()
    let teardownWatchdog = await sleeper.waitUntilArmed(for: .seconds(5))
    sleeper.fire(teardownWatchdog)

    await #expect(throws: DeadlineLifecycleError.body) {
      try await observation.value
    }
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == observeLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while running the observation session:") == true)

    reactionGate.open()
  }

  @Test
  @MainActor
  func `A timed-out scope reserves State until its old handler truly joins`() async throws {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    let sut = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)
    let firstSleeper = TestingDeadlineSleeper()
    let firstIssues = DeadlineIssueLog()
    let trueJoin = TestingDeadlineSignal()
    var firstBodyRan = false

    let firstObservation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        deadlinePolicy: testingDeadlinePolicy(sleeper: firstSleeper),
        _visorDidFinishTeardown: trueJoin.fire,
        infrastructureIssueRecorder: firstIssues.record
      ) { _ in
        firstBodyRan = true
        await statusService.publish(.loading)
        await reactionGate.waitUntilStarted()
      }
    }

    await reactionGate.waitUntilStarted()
    let teardownWatchdog = await firstSleeper.waitUntilArmed(
      for: .seconds(5))
    firstSleeper.fire(teardownWatchdog)
    try await firstObservation.value

    #expect(firstBodyRan)
    #expect(firstIssues.entries.count == 1)
    #expect(firstIssues.entries.first?.message.hasPrefix(
      "VISOR failed while running the observation session:") == true)

    let rejectedIssues = DeadlineIssueLog()
    var rejectedBodyRan = false
    try await _observeWithDeadlinePolicyForProof(
      sut,
      deadlinePolicy: testingDeadlinePolicy(
        sleeper: TestingDeadlineSleeper()),
      infrastructureIssueRecorder: rejectedIssues.record
    ) { _ in
      rejectedBodyRan = true
    }

    #expect(!rejectedBodyRan)
    #expect(rejectedIssues.entries.count == 1)
    #expect(rejectedIssues.entries.first?.message ==
      "This State already has an active observation scope")

    // The retired handler now completes its final State write. The finished
    // journal ignores it, and only the session's true-join callback releases
    // the reservation for a later clean scope.
    reactionGate.open()
    await trueJoin.wait()
    #expect(sut.state.reactedStatus == .loading)

    let laterIssues = DeadlineIssueLog()
    var laterBodyRan = false
    try await _observeWithDeadlinePolicyForProof(
      sut,
      deadlinePolicy: testingDeadlinePolicy(
        sleeper: TestingDeadlineSleeper()),
      infrastructureIssueRecorder: laterIssues.record
    ) { test in
      laterBodyRan = true
      await test.perform {}
      test.expect(\.revision, hasExactChanges: [])
    }

    #expect(laterBodyRan)
    #expect(laterIssues.entries.isEmpty)
  }
}
