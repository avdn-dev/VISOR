import Dispatch
import Testing
import VISOR
import VISORObservation
import VISORTesting

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

// MARK: - DeadlineFailureLog

@MainActor
private final class DeadlineFailureLog {

  // MARK: Lifecycle

  deinit { }

  // MARK: Internal

  private(set) var failures = [_ObservationSourceFailure]()

  func record(_ failure: _ObservationSourceFailure) {
    failures.append(failure)
  }
}

// MARK: - ReentrantDeadlineFailureLog

@MainActor
private final class ReentrantDeadlineFailureLog {

  // MARK: Lifecycle

  deinit { }

  // MARK: Internal

  private(set) var failures = [_ObservationSourceFailure]()
  weak var session: _ObservationSession?

  func record(_ failure: _ObservationSourceFailure) {
    failures.append(failure)
    session?.controlPlaneFailed(.failed("re-entrant failure"))
  }
}

// MARK: - DeadlineTaskCanceller

@MainActor
private final class DeadlineTaskCanceller {

  // MARK: Lifecycle

  deinit { }

  // MARK: Internal

  var task: Task<Void, any Error>?

  func cancel() {
    task?.cancel()
  }
}

// MARK: - MainActorDeadlineBlocker

nonisolated private final class MainActorDeadlineBlocker: Sendable {

  // MARK: Internal

  @MainActor
  func block() {
    started.signal()
    release.wait()
  }

  func recordDeadlineResolution() {
    deadlineResolved.signal()
  }

  func startConducting(_ operation: @escaping @Sendable () -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      self.waitUntilStarted()
      operation()
      self.releaseAfterDeadlineResolution()
      self.completion.record()
    }
  }

  func waitUntilConductorFinishes() async {
    await completion.wait()
  }

  // MARK: Private

  private let started = DispatchSemaphore(value: 0)
  private let deadlineResolved = DispatchSemaphore(value: 0)
  private let release = DispatchSemaphore(value: 0)
  private let completion = TestEventCounter()

  private func waitUntilStarted() {
    started.wait()
  }

  private func releaseAfterDeadlineResolution() {
    deadlineResolved.wait()
    release.signal()
  }

}

@MainActor
private func deadlinePolicy(
  _ sleeper: ManualSleeper
) -> _ObservationDeadlinePolicy {
  _ObservationDeadlinePolicy(
    readiness: .zero,
    openingFence: .zero,
    closingFence: .zero,
    fence: .zero,
    teardownJoin: .zero,
    _visorWatchdogFactory: sleeper.makeSleep,
  )
}

// MARK: - ObservationDeadlineTests

@Suite("Observation control-plane deadlines", .timeLimit(.minutes(1)))
struct ObservationDeadlineTests {
  @Test
  @MainActor
  func `A due watchdog wins while MainActor is synchronously occupied`() async {
    let channel = ObservationChannel(0)
    let sleeper = ManualSleeper()
    let blocker = MainActorDeadlineBlocker()
    let failures = DeadlineFailureLog()
    var handlerFinished = false
    let policy = _ObservationDeadlinePolicy(
      readiness: .zero,
      openingFence: .zero,
      closingFence: .zero,
      fence: .zero,
      teardownJoin: .zero,
      _visorWatchdogFactory: sleeper.makeSleep,
      _visorDidResolveDeadline: { phase in
        if phase == .readiness {
          blocker.recordDeadlineResolution()
        }
      },
    )
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in
            blocker.block()
            channel._visorTerminate(with: .failed("late operation failure"))
            handlerFinished = true
          }],
        )._visorErase()
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: policy,
    )

    blocker.startConducting {
      sleeper.wake(sleeper.preparedSleep(at: 0))
    }
    let startup = Task { @MainActor in
      try await session._visorStart()
    }

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    await blocker.waitUntilConductorFinishes()
    #expect(handlerFinished)
    #expect(!session._visorIsReady)
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "observation readiness",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0,
      )
    ])
    #expect(session._visorIsStopped)
  }

  @Test
  @MainActor
  func `A due fence deadline skips its synchronous source checkpoint`() async throws {
    let channel = ObservationChannel(0)
    let sleeper = ManualSleeper()
    let blocker = MainActorDeadlineBlocker()
    let failures = DeadlineFailureLog()
    var actionRan = false
    var checkpointRan = false
    let policy = _ObservationDeadlinePolicy(
      readiness: .seconds(30),
      openingFence: .seconds(10),
      closingFence: .seconds(10),
      fence: .seconds(10),
      teardownJoin: .seconds(10),
      _visorWatchdogFactory: sleeper.makeSleep,
      _visorDidResolveDeadline: { phase in
        if phase == .openingFence {
          blocker.recordDeadlineResolution()
        }
      },
    )
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase()
      ],
      _visorBeforePauseCheckpoint: blocker.block,
      _visorAfterPauseCheckpoint: { checkpointRan = true },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: policy,
    )

    try await session._visorStart()
    let sleepsBeforeFence = sleeper.sleepCount
    blocker.startConducting {
      let fenceSleep = sleeper.preparedSleep(at: sleepsBeforeFence)
      sleeper.wake(fenceSleep)
    }
    let opening = Task { @MainActor in
      try await session._visorWithPause(
        { actionRan = true },
        _visorPhase: .openingFence,
      )
    }

    await #expect(throws: _ObservationSourceFailure.self) {
      try await opening.value
    }
    await blocker.waitUntilConductorFinishes()

    let expected = _ObservationSourceFailure.safetyDeadlineExceeded(
      phase: "opening action fence",
      sourceIDs: [channel.source._visorIdentity],
      omittedSourceCount: 0,
    )
    #expect(!actionRan)
    #expect(!checkpointRan)
    #expect(failures.failures == [expected])
    #expect(session._visorFailure == expected)
    #expect(session._visorIsStopped)
  }

  @Test
  @MainActor
  func `An uncancelled sleeper CancellationError fails closed`() async {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let failures = DeadlineFailureLog()
    let policy = _ObservationDeadlinePolicy { _ in
      throw CancellationError()
    }
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.run(readinessGate.prepare()) }],
        )._visorErase()
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: policy,
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()

    do {
      try await startup.value
      Issue.record("Expected a watchdog failure")
    } catch let failure as _ObservationSourceFailure {
      guard case .failed(let detail) = failure else {
        Issue.record("Expected a typed watchdog failure, got \(failure)")
        readinessGate.setTerminalResult(.success(()))
        return
      }
      #expect(detail.contains(
        "private observation watchdog failed while awaiting observation readiness"
      ))
    } catch {
      Issue.record("Expected a typed watchdog failure, got \(error)")
    }

    #expect(failures.failures.count == 1)
    readinessGate.setTerminalResult(.success(()))
    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    await stopped.wait()
  }

  @Test
  @MainActor
  func `Readiness deadline fails closed and eventually completes one teardown`() async {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.run(readinessGate.prepare()) }],
        )._visorErase()
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    let readinessSleep = await sleeper.waitUntilPrepared(1)
    sleeper.wake(readinessSleep)
    let teardownSleep = await sleeper.waitUntilPrepared(2)
    sleeper.wake(teardownSleep)

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    #expect(!session._visorIsReady)
    #expect(session._visorIsStopping)
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "observation readiness",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0,
      )
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.setTerminalResult(.success(()))
    await stopped.wait()
    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Opening fence deadline identifies the opening phase`() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let fenceGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase()
      ],
      _visorBeforeReady: { await readinessGate.run(readinessGate.prepare()) },
      _visorBeforePauseDrain: { await fenceGate.run(fenceGate.prepare()) },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    _ = await sleeper.waitUntilPrepared(1)
    readinessGate.setTerminalResult(.success(()))
    _ = try await startup.value

    let opening = Task { @MainActor in
      try await session._visorWithPause(
        { 42 },
        _visorPhase: .openingFence,
      )
    }
    await fenceGate.waitUntilStarted()
    let openingSleep = await sleeper.waitUntilPrepared(2)
    sleeper.wake(openingSleep)
    let teardownSleep = await sleeper.waitUntilPrepared(3)
    sleeper.wake(teardownSleep)

    await #expect(throws: _ObservationSourceFailure.self) {
      _ = try await opening.value
    }
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "opening action fence",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0,
      )
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    fenceGate.setTerminalResult(.success(()))
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Closing fence deadline identifies the closing phase`() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let fenceGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase()
      ],
      _visorBeforeReady: { await readinessGate.run(readinessGate.prepare()) },
      _visorBeforePauseDrain: { await fenceGate.run(fenceGate.prepare()) },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    _ = await sleeper.waitUntilPrepared(1)
    readinessGate.setTerminalResult(.success(()))
    _ = try await startup.value

    let closing = Task { @MainActor in
      try await session._visorWithPause(
        { 42 },
        _visorPhase: .closingFence,
      )
    }
    await fenceGate.waitUntilStarted()
    let closingSleep = await sleeper.waitUntilPrepared(2)
    sleeper.wake(closingSleep)
    let teardownSleep = await sleeper.waitUntilPrepared(3)
    sleeper.wake(teardownSleep)

    await #expect(throws: _ObservationSourceFailure.self) {
      _ = try await closing.value
    }
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "closing action fence",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0,
      )
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    fenceGate.setTerminalResult(.success(()))
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Teardown deadline returns while one supervisor retains the true join`() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let handlerGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let stopped = TestEventCounter()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run(handlerGate.prepare()) }
          }],
        )._visorErase()
      ],
      _visorBeforeReady: { await readinessGate.run(readinessGate.prepare()) },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    _ = await sleeper.waitUntilPrepared(1)
    readinessGate.setTerminalResult(.success(()))
    _ = try await startup.value
    let sleepsBeforeTeardown = sleeper.sleepCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let stop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    let teardownSleep = await sleeper.waitUntilPrepared(
      sleepsBeforeTeardown + 1
    )
    sleeper.wake(teardownSleep)

    let didJoin = await stop.value
    #expect(!didJoin)
    #expect(session._visorIsStopping)
    #expect(!session._visorIsStopped)
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "teardown join",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0,
      )
    ])

    session._visorWhenStopped { stopped.record() }
    handlerGate.setTerminalResult(.success(()))
    await stopped.wait()

    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Caller cancellation before expiry stays cancellation`() async {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.run(readinessGate.prepare()) }],
        )._visorErase()
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    _ = await sleeper.waitUntilPrepared(1)
    startup.cancel()
    let teardownSleep = await sleeper.waitUntilPrepared(2)
    sleeper.wake(teardownSleep)

    await #expect(throws: CancellationError.self) {
      try await startup.value
    }
    #expect(failures.failures.isEmpty)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.setTerminalResult(.success(()))
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `A latched first cause survives re-entrant caller cancellation`() async {
    let channel = ObservationChannel(0)
    channel._visorTerminate(with: .failed("first failure"))
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let canceller = DeadlineTaskCanceller()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase()
      ],
      _visorOnFailure: { failure in
        failures.record(failure)
        // Cancellation resolves the outer race before the operation task can
        // publish its failure, exercising caller-cancellation reconciliation.
        canceller.cancel()
      },
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    canceller.task = startup

    do {
      try await startup.value
      Issue.record("Expected the first infrastructure failure")
    } catch let failure as _ObservationSourceFailure {
      #expect(failure == .failed("first failure"))
    } catch {
      Issue.record("Expected the typed infrastructure failure, got \(error)")
    }
    #expect(failures.failures == [.failed("first failure")])
    #expect(session._visorFailure == .failed("first failure"))
    #expect(session._visorIsStopped)
  }

  @Test
  @MainActor
  func `Concurrent and repeated stops share one bounded teardown wait`() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let handlerGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run(handlerGate.prepare()) }
          }],
        )._visorErase()
      ],
      _visorBeforeReady: { await readinessGate.run(readinessGate.prepare()) },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    _ = await sleeper.waitUntilPrepared(1)
    readinessGate.setTerminalResult(.success(()))
    try await startup.value
    let sleepsBeforeTeardown = sleeper.sleepCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let firstStop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    let secondStop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    let teardownSleep = await sleeper.waitUntilPrepared(
      sleepsBeforeTeardown + 1
    )

    // Both callers use the one session coordinator: there is one watchdog and
    // one true-join callback, not one observer task per caller.
    #expect(sleeper.sleepCount == sleepsBeforeTeardown + 1)
    sleeper.wake(teardownSleep)
    #expect(await firstStop.value == false)
    #expect(await secondStop.value == false)

    let sleepsAfterDeadline = sleeper.sleepCount
    #expect(await session._visorStopWithinDeadline() == false)
    #expect(sleeper.sleepCount == sleepsAfterDeadline)
    #expect(failures.failures.count == 1)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    handlerGate.setTerminalResult(.success(()))
    await stopped.wait()
    #expect(session._visorIsStopped)
  }

  @Test
  @MainActor
  func `Many teardown waiters share one deadline under mixed cancellation`() async throws {
    let waiterCount = 64
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let handlerGate = ControllableOperation<Void, Never>()
    let arrivalBarrier = TestEventCounter()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run(handlerGate.prepare()) }
          }],
        )._visorErase()
      ],
      _visorBeforeReady: { await readinessGate.run(readinessGate.prepare()) },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    _ = await sleeper.waitUntilPrepared(1)
    readinessGate.setTerminalResult(.success(()))
    try await startup.value
    let sleepsBeforeTeardown = sleeper.sleepCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let stops: [Task<Bool, Never>] = (0..<waiterCount).map { _ in
      Task { @MainActor in
        arrivalBarrier.record()
        return await session._visorStopWithinDeadline()
      }
    }
    await arrivalBarrier.wait(for: waiterCount)
    let teardownSleep = await sleeper.waitUntilPrepared(
      sleepsBeforeTeardown + 1
    )

    for index in stops.indices where index.isMultiple(of: 3) {
      stops[index].cancel()
    }

    #expect(sleeper.sleepCount == sleepsBeforeTeardown + 1)
    sleeper.wake(teardownSleep)
    for stop in stops {
      #expect(await stop.value == false)
    }

    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "teardown join",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0,
      )
    ])

    let sleepsAfterDeadline = sleeper.sleepCount
    #expect(await session._visorStopWithinDeadline() == false)
    #expect(sleeper.sleepCount == sleepsAfterDeadline)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    handlerGate.setTerminalResult(.success(()))
    await stopped.wait()
    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Cancelling the last teardown waiter before expiry suppresses timeout`() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let handlerGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run(handlerGate.prepare()) }
          }],
        )._visorErase()
      ],
      _visorBeforeReady: { await readinessGate.run(readinessGate.prepare()) },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    _ = await sleeper.waitUntilPrepared(1)
    readinessGate.setTerminalResult(.success(()))
    try await startup.value
    let sleepsBeforeTeardown = sleeper.sleepCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let stop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    let teardownSleep = await sleeper.waitUntilPrepared(
      sleepsBeforeTeardown + 1
    )

    // Task.cancel() runs registered cancellation handlers before returning;
    // firing afterwards deterministically linearises cancellation first.
    stop.cancel()
    sleeper.wake(teardownSleep)
    #expect(await stop.value == false)
    #expect(failures.failures.isEmpty)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    handlerGate.setTerminalResult(.success(()))
    await stopped.wait()
    #expect(session._visorIsStopped)
  }

  @Test
  @MainActor
  func `A re-entrant callback cannot replace or duplicate the first cause`() async {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = ReentrantDeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.run(readinessGate.prepare()) }],
        )._visorErase()
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )
    failures.session = session

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    let readinessSleep = await sleeper.waitUntilPrepared(1)
    sleeper.wake(readinessSleep)
    let teardownSleep = await sleeper.waitUntilPrepared(2)
    sleeper.wake(teardownSleep)

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    let expected = _ObservationSourceFailure.safetyDeadlineExceeded(
      phase: "observation readiness",
      sourceIDs: [channel.source._visorIdentity],
      omittedSourceCount: 0,
    )
    #expect(failures.failures == [expected])
    #expect(session._visorFailure == expected)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.setTerminalResult(.success(()))
    await stopped.wait()
  }

  @Test
  @MainActor
  func `Deadline diagnostics retain a bounded source prefix`() async {
    let channels = (0..<10).map { ObservationChannel($0) }
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = ManualSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: channels.map { channel in
        _ObservationLane(
          source: channel.source,
          handlers: [],
        )
        ._visorErase()
      },
      _visorBeforeReady: { await readinessGate.run(readinessGate.prepare()) },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper),
    )

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    let readinessSleep = await sleeper.waitUntilPrepared(1)
    sleeper.wake(readinessSleep)
    let teardownSleep = await sleeper.waitUntilPrepared(2)
    sleeper.wake(teardownSleep)

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "observation readiness",
        sourceIDs: channels.prefix(8).map { $0.source._visorIdentity },
        omittedSourceCount: 2,
      )
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.setTerminalResult(.success(()))
    await stopped.wait()
  }
}
