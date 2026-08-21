import Dispatch
import os
import Testing
import VISOR
import VISORObservation
import VISORTesting

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

@MainActor
private final class DeadlineSleeper {
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
  private var nextID = 0

  deinit {}

  func sleep(for _: Duration) async throws {
    let id = nextID
    nextID += 1
    armCount += 1
    let completed = armWaiters.filter { $0.target <= armCount }
    armWaiters.removeAll { $0.target <= armCount }
    for waiter in completed {
      waiter.continuation.resume()
    }

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
    let continuation = pending.remove(at: index).continuation
    continuation.resume()
  }

  private func cancel(id: Int) {
    guard let index = pending.firstIndex(where: { $0.id == id }) else {
      return
    }
    let continuation = pending.remove(at: index).continuation
    continuation.resume(throwing: CancellationError())
  }
}

@MainActor
private final class DeadlineFailureLog {
  private(set) var failures: [_ObservationSourceFailure] = []

  deinit {}

  func record(_ failure: _ObservationSourceFailure) {
    failures.append(failure)
  }
}

@MainActor
private final class ReentrantDeadlineFailureLog {
  private(set) var failures: [_ObservationSourceFailure] = []
  weak var session: _ObservationSession?

  deinit {}

  func record(_ failure: _ObservationSourceFailure) {
    failures.append(failure)
    session?.controlPlaneFailed(.failed("re-entrant failure"))
  }
}

@MainActor
private final class DeadlineTaskCanceller {
  var task: Task<Void, any Error>?

  deinit {}

  func cancel() {
    task?.cancel()
  }
}

nonisolated private final class ConcurrentDeadlineSleeper: Sendable {
  private struct State: Sendable {
    var pending: CheckedContinuation<Void, any Error>?
    var isFired = false
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  @concurrent
  func sleep(for _: Duration) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let registration: (
          isCancelled: Bool,
          isFired: Bool
        ) =
          lock.withLock { state in
            if Task.isCancelled {
              return (true, false)
            }
            if state.isFired {
              state.isFired = false
              return (false, true)
            }
            precondition(state.pending == nil)
            state.pending = continuation
            return (false, false)
          }
        if registration.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        if registration.isFired {
          continuation.resume()
        }
      }
    } onCancel: {
      let continuation = lock.withLock { state in
        state.pending.take()
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  func fire() {
    let continuation: CheckedContinuation<Void, any Error>? =
      lock.withLock { state in
      guard let continuation = state.pending.take() else {
        state.isFired = true
        return nil
      }
      return continuation
      }
    continuation?.resume()
  }
}

nonisolated private final class ArmedWatchdogController: Sendable {
  private enum Registration {
    case suspended
    case fired
    case cancelled
  }

  private struct Arm: Sendable {
    var isFired = false
    var continuation: CheckedContinuation<Void, any Error>?
  }

  private struct State: Sendable {
    var nextID = 0
    var arms: [Int: Arm] = [:]
    var armIDs: [Int] = []
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  var armCount: Int {
    lock.withLock { $0.armIDs.count }
  }

  func makeWatchdog(
    for _: Duration
  ) -> _ObservationDeadlinePolicy.ArmedWatchdog {
    let id = lock.withLock { state in
      let id = state.nextID
      state.nextID += 1
      state.arms[id] = Arm()
      state.armIDs.append(id)
      return id
    }
    return { try await self.wait(for: id) }
  }

  @concurrent
  private func wait(for id: Int) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let registration: Registration = lock.withLock { state in
          if Task.isCancelled {
            state.arms.removeValue(forKey: id)
            return .cancelled
          }
          guard var arm = state.arms[id] else { return .cancelled }
          if arm.isFired {
            state.arms.removeValue(forKey: id)
            return .fired
          }
          arm.continuation = continuation
          state.arms[id] = arm
          return .suspended
        }
        switch registration {
        case .suspended:
          break
        case .fired:
          continuation.resume()
        case .cancelled:
          continuation.resume(throwing: CancellationError())
        }
      }
    } onCancel: {
      let continuation = lock.withLock { state in
        state.arms.removeValue(forKey: id)?.continuation
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  func armID(at index: Int) -> Int {
    lock.withLock { state in
      precondition(state.armIDs.indices.contains(index))
      return state.armIDs[index]
    }
  }

  func fire(_ id: Int) {
    let continuation: CheckedContinuation<Void, any Error>? =
      lock.withLock { state in
        guard var arm = state.arms[id] else { return nil }
        guard let continuation = arm.continuation else {
          arm.isFired = true
          state.arms[id] = arm
          return nil
        }
        state.arms.removeValue(forKey: id)
        return continuation
      }
    continuation?.resume()
  }
}

nonisolated private final class MainActorDeadlineBlocker: Sendable {
  private struct CompletionState: Sendable {
    var didFinish = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let started = DispatchSemaphore(value: 0)
  private let deadlineResolved = DispatchSemaphore(value: 0)
  private let release = DispatchSemaphore(value: 0)
  private let completion = OSAllocatedUnfairLock(
    initialState: CompletionState())

  @MainActor
  func block() {
    started.signal()
    release.wait()
  }

  private func waitUntilStarted() {
    started.wait()
  }

  func recordDeadlineResolution() {
    deadlineResolved.signal()
  }

  private func releaseAfterDeadlineResolution() {
    deadlineResolved.wait()
    release.signal()
  }

  func startConducting(_ operation: @escaping @Sendable () -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      self.waitUntilStarted()
      operation()
      self.releaseAfterDeadlineResolution()
      let waiters = self.completion.withLock { state in
        state.didFinish = true
        let waiters = state.waiters
        state.waiters.removeAll(keepingCapacity: false)
        return waiters
      }
      for waiter in waiters { waiter.resume() }
    }
  }

  func waitUntilConductorFinishes() async {
    await withCheckedContinuation { continuation in
      let didFinish = completion.withLock { state in
        if state.didFinish { return true }
        state.waiters.append(continuation)
        return false
      }
      if didFinish { continuation.resume() }
    }
  }
}

@MainActor
private func deadlinePolicy(
  _ sleeper: DeadlineSleeper
) -> _ObservationDeadlinePolicy {
  _ObservationDeadlinePolicy { duration in
    try await sleeper.sleep(for: duration)
  }
}

@Suite("Observation control-plane deadlines", .timeLimit(.minutes(1)))
struct ObservationDeadlineTests {
  @Test
  @MainActor
  func `A due watchdog wins while MainActor is synchronously occupied`() async {
    let channel = ObservationChannel(0)
    let sleeper = ConcurrentDeadlineSleeper()
    let blocker = MainActorDeadlineBlocker()
    let failures = DeadlineFailureLog()
    var handlerFinished = false
    let policy = _ObservationDeadlinePolicy(
      sleeper: { duration in
        try await sleeper.sleep(for: duration)
      },
      _visorDidResolveDeadline: { phase in
        if phase == .readiness {
          blocker.recordDeadlineResolution()
        }
      })
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in
            blocker.block()
            channel._visorTerminate(with: .failed("late operation failure"))
            handlerFinished = true
          }]
        )._visorErase(),
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: policy)

    blocker.startConducting { sleeper.fire() }
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
        omittedSourceCount: 0),
    ])
    #expect(session._visorIsStopped)
  }

  @Test
  @MainActor
  func `A due fence deadline skips its synchronous source checkpoint`() async throws {
    let channel = ObservationChannel(0)
    let sleeper = ArmedWatchdogController()
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
      _visorWatchdogFactory: sleeper.makeWatchdog,
      _visorDidResolveDeadline: { phase in
        if phase == .openingFence {
          blocker.recordDeadlineResolution()
        }
      })
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase(),
      ],
      _visorBeforePauseCheckpoint: blocker.block,
      _visorAfterPauseCheckpoint: { checkpointRan = true },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: policy)

    try await session._visorStart()
    let armsBeforeFence = sleeper.armCount
    blocker.startConducting {
      let fenceID = sleeper.armID(at: armsBeforeFence)
      sleeper.fire(fenceID)
    }
    let opening = Task { @MainActor in
      try await session._visorWithPause(
        { actionRan = true },
        _visorPhase: .openingFence)
    }

    await #expect(throws: _ObservationSourceFailure.self) {
      try await opening.value
    }
    await blocker.waitUntilConductorFinishes()

    let expected = _ObservationSourceFailure.safetyDeadlineExceeded(
      phase: "opening action fence",
      sourceIDs: [channel.source._visorIdentity],
      omittedSourceCount: 0)
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
          handlers: [{ _ in await readinessGate.run() }]
        )._visorErase(),
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: policy)

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
        readinessGate.finish()
        return
      }
      #expect(detail.contains(
        "private observation watchdog failed while awaiting observation readiness"))
    } catch {
      Issue.record("Expected a typed watchdog failure, got \(error)")
    }

    #expect(failures.failures.count == 1)
    readinessGate.finish()
    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    await stopped.wait()
  }

  @Test
  @MainActor
  func `Readiness deadline fails closed and eventually completes one teardown`() async {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.run() }]
        )._visorErase(),
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    sleeper.fire(0)
    await sleeper.waitUntilArmed(2)
    sleeper.fire(1)

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    #expect(!session._visorIsReady)
    #expect(session._visorIsStopping)
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "observation readiness",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0),
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.finish()
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
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.run() },
      _visorBeforePauseDrain: { await fenceGate.run() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.finish()
    _ = try await startup.value

    let opening = Task { @MainActor in
      try await session._visorWithPause(
        { 42 },
        _visorPhase: .openingFence)
    }
    await fenceGate.waitUntilStarted()
    await sleeper.waitUntilArmed(2)
    sleeper.fire(1)
    await sleeper.waitUntilArmed(3)
    sleeper.fire(2)

    await #expect(throws: _ObservationSourceFailure.self) {
      _ = try await opening.value
    }
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "opening action fence",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0),
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    fenceGate.finish()
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Closing fence deadline identifies the closing phase`() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let fenceGate = ControllableOperation<Void, Never>()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.run() },
      _visorBeforePauseDrain: { await fenceGate.run() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.finish()
    _ = try await startup.value

    let closing = Task { @MainActor in
      try await session._visorWithPause(
        { 42 },
        _visorPhase: .closingFence)
    }
    await fenceGate.waitUntilStarted()
    await sleeper.waitUntilArmed(2)
    sleeper.fire(1)
    await sleeper.waitUntilArmed(3)
    sleeper.fire(2)

    await #expect(throws: _ObservationSourceFailure.self) {
      _ = try await closing.value
    }
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "closing action fence",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0),
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    fenceGate.finish()
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Teardown deadline returns while one supervisor retains the true join`() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let handlerGate = ControllableOperation<Void, Never>()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let stopped = TestEventCounter()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run() }
          }]
        )._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.run() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.finish()
    _ = try await startup.value
    let armsBeforeTeardown = sleeper.armCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let stop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    await sleeper.waitUntilArmed(armsBeforeTeardown + 1)
    sleeper.fire(armsBeforeTeardown)

    let didJoin = await stop.value
    #expect(!didJoin)
    #expect(session._visorIsStopping)
    #expect(!session._visorIsStopped)
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "teardown join",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0),
    ])

    session._visorWhenStopped { stopped.record() }
    handlerGate.finish()
    await stopped.wait()

    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Caller cancellation before expiry stays cancellation`() async {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.run() }]
        )._visorErase(),
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    startup.cancel()
    await sleeper.waitUntilArmed(2)
    sleeper.fire(1)

    await #expect(throws: CancellationError.self) {
      try await startup.value
    }
    #expect(failures.failures.isEmpty)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.finish()
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `A latched first cause survives re-entrant caller cancellation`() async {
    let channel = ObservationChannel(0)
    channel._visorTerminate(with: .failed("first failure"))
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let canceller = DeadlineTaskCanceller()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase(),
      ],
      _visorOnFailure: { failure in
        failures.record(failure)
        // Cancellation resolves the outer race before the operation task can
        // publish its failure, exercising caller-cancellation reconciliation.
        canceller.cancel()
      },
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

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
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run() }
          }]
        )._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.run() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.finish()
    try await startup.value
    let armsBeforeTeardown = sleeper.armCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let firstStop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    let secondStop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    await sleeper.waitUntilArmed(armsBeforeTeardown + 1)

    // Both callers use the one session coordinator: there is one watchdog and
    // one true-join callback, not one observer task per caller.
    #expect(sleeper.armCount == armsBeforeTeardown + 1)
    sleeper.fire(armsBeforeTeardown)
    #expect(await firstStop.value == false)
    #expect(await secondStop.value == false)

    let armsAfterDeadline = sleeper.armCount
    #expect(await session._visorStopWithinDeadline() == false)
    #expect(sleeper.armCount == armsAfterDeadline)
    #expect(failures.failures.count == 1)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    handlerGate.finish()
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
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run() }
          }]
        )._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.run() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.finish()
    try await startup.value
    let armsBeforeTeardown = sleeper.armCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let stops: [Task<Bool, Never>] = (0..<waiterCount).map { _ in
      Task { @MainActor in
        arrivalBarrier.record()
        return await session._visorStopWithinDeadline()
      }
    }
    await arrivalBarrier.wait(for: waiterCount)
    await sleeper.waitUntilArmed(armsBeforeTeardown + 1)

    for index in stops.indices where index.isMultiple(of: 3) {
      stops[index].cancel()
    }

    #expect(sleeper.armCount == armsBeforeTeardown + 1)
    sleeper.fire(armsBeforeTeardown)
    for stop in stops {
      #expect(await stop.value == false)
    }

    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "teardown join",
        sourceIDs: [channel.source._visorIdentity],
        omittedSourceCount: 0),
    ])

    let armsAfterDeadline = sleeper.armCount
    #expect(await session._visorStopWithinDeadline() == false)
    #expect(sleeper.armCount == armsAfterDeadline)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    handlerGate.finish()
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
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.run() }
          }]
        )._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.run() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.finish()
    try await startup.value
    let armsBeforeTeardown = sleeper.armCount

    channel.publish(1)
    await handlerGate.waitUntilStarted()
    let stop = Task { @MainActor in
      await session._visorStopWithinDeadline()
    }
    await sleeper.waitUntilArmed(armsBeforeTeardown + 1)

    // Task.cancel() runs registered cancellation handlers before returning;
    // firing afterwards deterministically linearises cancellation first.
    stop.cancel()
    sleeper.fire(armsBeforeTeardown)
    #expect(await stop.value == false)
    #expect(failures.failures.isEmpty)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    handlerGate.finish()
    await stopped.wait()
    #expect(session._visorIsStopped)
  }

  @Test
  @MainActor
  func `A re-entrant callback cannot replace or duplicate the first cause`() async {
    let channel = ObservationChannel(0)
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = DeadlineSleeper()
    let failures = ReentrantDeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.run() }]
        )._visorErase(),
      ],
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))
    failures.session = session

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    sleeper.fire(0)
    await sleeper.waitUntilArmed(2)
    sleeper.fire(1)

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    let expected = _ObservationSourceFailure.safetyDeadlineExceeded(
      phase: "observation readiness",
      sourceIDs: [channel.source._visorIdentity],
      omittedSourceCount: 0)
    #expect(failures.failures == [expected])
    #expect(session._visorFailure == expected)

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.finish()
    await stopped.wait()
  }

  @Test
  @MainActor
  func `Deadline diagnostics retain a bounded source prefix`() async {
    let channels = (0..<10).map { ObservationChannel($0) }
    let readinessGate = ControllableOperation<Void, Never>()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: channels.map { channel in
        _ObservationLane(
          source: channel.source,
          handlers: [])
          ._visorErase()
      },
      _visorBeforeReady: { await readinessGate.run() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    sleeper.fire(0)
    await sleeper.waitUntilArmed(2)
    sleeper.fire(1)

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    #expect(failures.failures == [
      .safetyDeadlineExceeded(
        phase: "observation readiness",
        sourceIDs: channels.prefix(8).map { $0.source._visorIdentity },
        omittedSourceCount: 2),
    ])

    let stopped = TestEventCounter()
    session._visorWhenStopped { stopped.record() }
    readinessGate.finish()
    await stopped.wait()
  }
}
