import Testing
import VISOR
import VISORTesting

// MARK: - DeadlineLifecycleError

private enum DeadlineLifecycleError: Error {
  case action
  case body
}

// MARK: - NthPauseGate

@MainActor
private final class NthPauseGate {

  // MARK: Lifecycle

  init(target: Int) {
    self.target = target
  }

  deinit { }

  // MARK: Internal

  func visit() async {
    count += 1
    guard count == target else { return }
    await operation.run(operation.prepare())
  }

  func waitUntilStarted() async {
    await operation.waitUntilStarted()
  }

  func open() {
    operation.setTerminalResult(.success(()))
  }

  // MARK: Private

  private let target: Int
  private let operation = ControllableOperation<Void, Never>()
  private var count = 0

}

// MARK: - DeadlineIssueLog

@MainActor
private final class DeadlineIssueLog {

  // MARK: Lifecycle

  deinit { }

  // MARK: Internal

  struct Entry {
    let message: String
    let location: SourceLocation
  }

  private(set) var entries = [Entry]()

  func record(_ message: String, at location: SourceLocation) {
    entries.append(Entry(message: message, location: location))
  }
}

@MainActor
private func testingDeadlinePolicy(
  sleeper: ManualSleeper
) -> _ObservationDeadlinePolicy {
  _ObservationDeadlinePolicy(
    readiness: .seconds(1),
    openingFence: .seconds(2),
    closingFence: .seconds(3),
    fence: .seconds(4),
    teardownJoin: .seconds(5),
    _visorWatchdogFactory: sleeper.makeSleep,
  )
}

// MARK: - DeadlineLifecycleTests

@Suite("VISORTesting control-plane deadlines")
struct DeadlineLifecycleTests {
  @Test
  @MainActor
  func `Readiness reports at observe and withholds the body`() async throws {
    let service = TestingService(10)
    let reactionGate = ControllableOperation<Void, Never>()
    let sut = TestingViewModel(
      service: service,
      reactionGate: reactionGate,
    )
    let sleeper = ManualSleeper()
    let issues = DeadlineIssueLog()
    let observeLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/startup",
      filePath: "/DeadlineLifecycleTests/startup.swift",
      line: 123,
      column: 4,
    )
    var enteredBody = false

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        sourceLocation: observeLocation,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        issueRecorder: issues.record,
      ) { _ in
        enteredBody = true
      }
    }

    await reactionGate.waitUntilStarted()
    let readinessWatchdog = await sleeper.waitUntilPrepared(for: .seconds(1))
    sleeper.wake(readinessWatchdog)
    let teardownWatchdog = await sleeper.waitUntilPrepared(for: .seconds(5))
    sleeper.wake(teardownWatchdog)
    try await observation.value

    #expect(!enteredBody)
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == observeLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while starting observation:"
    ) == true)

    reactionGate.setTerminalResult(.success(()))
  }

  @Test
  @MainActor
  func `A suspended user action receives no VISOR deadline`() async throws {
    let sut = TestingViewModel()
    let sleeper = ManualSleeper()
    let actionGate = ControllableOperation<Void, Never>()
    let issues = DeadlineIssueLog()
    var actionCompleted = false

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        issueRecorder: issues.record,
      ) { test in
        await test.perform {
          await actionGate.run(actionGate.prepare())
          actionCompleted = true
        }
        test.expect(\.count, hasExactChanges: [])
      }
    }

    await actionGate.waitUntilStarted()
    #expect(!actionCompleted)
    #expect(issues.entries.isEmpty)

    actionGate.setTerminalResult(.success(()))
    try await observation.value
    #expect(actionCompleted)
    #expect(issues.entries.isEmpty)
  }

  @Test
  @MainActor
  func `Opening reports at perform and suppresses the action`() async throws {
    let sut = TestingViewModel()
    let sleeper = ManualSleeper()
    let openingGate = NthPauseGate(target: 1)
    let issues = DeadlineIssueLog()
    let performLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/opening",
      filePath: "/DeadlineLifecycleTests/opening.swift",
      line: 234,
      column: 5,
    )
    var actionRan = false

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        beforePauseDrain: openingGate.visit,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        issueRecorder: issues.record,
      ) { test in
        await test.perform({ actionRan = true }, sourceLocation: performLocation)
      }
    }

    await openingGate.waitUntilStarted()
    let openingWatchdog = await sleeper.waitUntilPrepared(for: .seconds(2))
    sleeper.wake(openingWatchdog)
    let teardownWatchdog = await sleeper.waitUntilPrepared(for: .seconds(5))
    sleeper.wake(teardownWatchdog)
    try await observation.value

    #expect(!actionRan)
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == performLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while opening an action window:"
    ) == true)

    openingGate.open()
  }

  @Test
  @MainActor
  func `Closing preserves a produced result and reports at perform`() async throws {
    let sut = TestingViewModel()
    let sleeper = ManualSleeper()
    let closingGate = NthPauseGate(target: 2)
    let issues = DeadlineIssueLog()
    let performLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/result",
      filePath: "/DeadlineLifecycleTests/result.swift",
      line: 321,
      column: 9,
    )
    var result: Int?

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        beforePauseDrain: closingGate.visit,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        issueRecorder: issues.record,
      ) { test in
        result = try await test.perform(
          { 42 },
          sourceLocation: performLocation,
        )
      }
    }

    await closingGate.waitUntilStarted()
    let closingWatchdog = await sleeper.waitUntilPrepared(for: .seconds(3))
    sleeper.wake(closingWatchdog)
    let teardownWatchdog = await sleeper.waitUntilPrepared(for: .seconds(5))
    sleeper.wake(teardownWatchdog)
    try await observation.value

    #expect(result == 42)
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == performLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while closing an action window:"
    ) == true)

    closingGate.open()
  }

  @Test
  @MainActor
  func `Closing preserves the exact action error`() async throws {
    let sut = TestingViewModel()
    let sleeper = ManualSleeper()
    let closingGate = NthPauseGate(target: 2)
    let issues = DeadlineIssueLog()

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        beforePauseDrain: closingGate.visit,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        issueRecorder: issues.record,
      ) { test in
        await #expect(throws: DeadlineLifecycleError.action) {
          try await test.perform {
            throw DeadlineLifecycleError.action
          }
        }
      }
    }

    await closingGate.waitUntilStarted()
    let closingWatchdog = await sleeper.waitUntilPrepared(for: .seconds(3))
    sleeper.wake(closingWatchdog)
    let teardownWatchdog = await sleeper.waitUntilPrepared(for: .seconds(5))
    sleeper.wake(teardownWatchdog)
    try await observation.value

    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while closing an action window:"
    ) == true)

    closingGate.open()
  }

  @Test
  @MainActor
  func `Teardown preserves the body error and reports at observe`() async {
    let service = TestingService()
    let reactionGate = ControllableOperation<Void, Never>()
    let sut = TestingViewModel(
      service: service,
      reactionGate: reactionGate,
    )
    let sleeper = ManualSleeper()
    let issues = DeadlineIssueLog()
    let observeLocation = SourceLocation(
      fileID: "DeadlineLifecycleTests/body",
      filePath: "/DeadlineLifecycleTests/body.swift",
      line: 654,
      column: 7,
    )

    let observation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        sourceLocation: observeLocation,
        deadlinePolicy: testingDeadlinePolicy(sleeper: sleeper),
        issueRecorder: issues.record,
      ) { _ in
        await service.publish(10)
        await reactionGate.waitUntilStarted()
        throw DeadlineLifecycleError.body
      }
    }

    await reactionGate.waitUntilStarted()
    let teardownWatchdog = await sleeper.waitUntilPrepared(for: .seconds(5))
    sleeper.wake(teardownWatchdog)

    await #expect(throws: DeadlineLifecycleError.body) {
      try await observation.value
    }
    #expect(issues.entries.count == 1)
    #expect(issues.entries.first?.location == observeLocation)
    #expect(issues.entries.first?.message.hasPrefix(
      "VISOR failed while running the observation session:"
    ) == true)

    reactionGate.setTerminalResult(.success(()))
  }

  @Test
  @MainActor
  func `A timed-out scope reserves State until its handler truly joins`() async throws {
    let service = TestingService()
    let reactionGate = ControllableOperation<Void, Never>()
    let sut = TestingViewModel(
      service: service,
      reactionGate: reactionGate,
    )
    let firstSleeper = ManualSleeper()
    let firstIssues = DeadlineIssueLog()
    let trueJoin = TestEventCounter()
    var firstBodyRan = false

    let firstObservation = Task { @MainActor in
      try await _observeWithDeadlinePolicyForProof(
        sut,
        deadlinePolicy: testingDeadlinePolicy(sleeper: firstSleeper),
        _visorDidFinishTeardown: trueJoin.record,
        issueRecorder: firstIssues.record,
      ) { _ in
        firstBodyRan = true
        await service.publish(10)
        await reactionGate.waitUntilStarted()
      }
    }

    await reactionGate.waitUntilStarted()
    let teardownWatchdog = await firstSleeper.waitUntilPrepared(
      for: .seconds(5)
    )
    firstSleeper.wake(teardownWatchdog)
    try await firstObservation.value

    #expect(firstBodyRan)
    #expect(firstIssues.entries.count == 1)
    #expect(firstIssues.entries.first?.message.hasPrefix(
      "VISOR failed while running the observation session:"
    ) == true)

    let rejectedIssues = DeadlineIssueLog()
    var rejectedBodyRan = false
    try await _observeWithDeadlinePolicyForProof(
      sut,
      deadlinePolicy: testingDeadlinePolicy(
        sleeper: ManualSleeper()
      ),
      issueRecorder: rejectedIssues.record,
    ) { _ in
      rejectedBodyRan = true
    }

    #expect(!rejectedBodyRan)
    #expect(rejectedIssues.entries.count == 1)
    #expect(rejectedIssues.entries.first?.message ==
      "This State already has an active observation scope")

    // The retired handler completes its final State write. The finished
    // journal ignores it, and only true join releases the reservation.
    reactionGate.setTerminalResult(.success(()))
    await trueJoin.wait()
    #expect(sut.state.reactedValue == 10)

    let laterIssues = DeadlineIssueLog()
    var laterBodyRan = false
    try await _observeWithDeadlinePolicyForProof(
      sut,
      deadlinePolicy: testingDeadlinePolicy(
        sleeper: ManualSleeper()
      ),
      issueRecorder: laterIssues.record,
    ) { test in
      laterBodyRan = true
      await test.perform { }
      test.expect(\.sourceValue, hasExactChanges: [])
    }

    #expect(laterBodyRan)
    #expect(laterIssues.entries.isEmpty)
  }
}
