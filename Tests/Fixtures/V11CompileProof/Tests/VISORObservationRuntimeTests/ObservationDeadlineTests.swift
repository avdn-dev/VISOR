import Dispatch
import os
import Testing
import VISOR
import VISORObservation

@MainActor
private final class DeadlineSleeper {
  struct Arm {
    let order: Int
    let duration: Duration
  }

  private struct Pending {
    let id: Int
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct ArmWaiter {
    let target: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private(set) var arms: [Arm] = []
  private var pending: [Pending] = []
  private var armWaiters: [ArmWaiter] = []
  private var nextID = 0

  func sleep(for duration: Duration) async throws {
    let id = nextID
    nextID += 1
    arms.append(Arm(order: id, duration: duration))
    let completed = armWaiters.filter { $0.target <= arms.count }
    armWaiters.removeAll { $0.target <= arms.count }
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
    guard arms.count < target else { return }
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
private final class DeadlineGate {
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
private final class DeadlineFailureLog {
  private(set) var failures: [_ObservationSourceFailure] = []

  func record(_ failure: _ObservationSourceFailure) {
    failures.append(failure)
  }
}

@MainActor
private final class ReentrantDeadlineFailureLog {
  private(set) var failures: [_ObservationSourceFailure] = []
  weak var session: _ObservationSession?

  func record(_ failure: _ObservationSourceFailure) {
    failures.append(failure)
    session?.controlPlaneFailed(.failed("re-entrant failure"))
  }
}

@MainActor
private final class DeadlineSignal {
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
private final class DeadlineTaskCanceller {
  var task: Task<Void, any Error>?

  func cancel() {
    task?.cancel()
  }
}

nonisolated private final class ConcurrentDeadlineSleeper: Sendable {
  private struct State: Sendable {
    var pending: CheckedContinuation<Void, any Error>?
    var isArmed = false
    var armWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  @concurrent
  func sleep(for _: Duration) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let armWaiters: [CheckedContinuation<Void, Never>] =
          lock.withLock { state in
            if Task.isCancelled {
              return []
            }
            precondition(state.pending == nil)
            state.pending = continuation
            state.isArmed = true
            let waiters = state.armWaiters
            state.armWaiters.removeAll(keepingCapacity: false)
            return waiters
          }
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }
        for waiter in armWaiters { waiter.resume() }
      }
    } onCancel: {
      let continuation = lock.withLock { state in
        state.pending.take()
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  func waitUntilArmed() async {
    await withCheckedContinuation { continuation in
      let isArmed = lock.withLock { state in
        if state.isArmed { return true }
        state.armWaiters.append(continuation)
        return false
      }
      if isArmed { continuation.resume() }
    }
  }

  func fire() {
    let continuation = lock.withLock { state in
      state.pending.take()
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

  private struct ArmWaiter: Sendable {
    let target: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private struct Arm: Sendable {
    var isFired = false
    var continuation: CheckedContinuation<Void, any Error>?
  }

  private struct State: Sendable {
    var nextID = 0
    var arms: [Int: Arm] = [:]
    var armIDs: [Int] = []
    var armWaiters: [ArmWaiter] = []
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  var armCount: Int {
    lock.withLock { $0.armIDs.count }
  }

  func makeWatchdog(
    for _: Duration
  ) -> _ObservationDeadlinePolicy.ArmedWatchdog {
    let registration: (
      id: Int,
      waiters: [CheckedContinuation<Void, Never>]
    ) = lock.withLock { state in
      let id = state.nextID
      state.nextID += 1
      state.arms[id] = Arm()
      state.armIDs.append(id)
      let waiters = state.armWaiters
        .filter { $0.target <= state.armIDs.count }
        .map(\.continuation)
      state.armWaiters.removeAll { $0.target <= state.armIDs.count }
      return (id, waiters)
    }
    for waiter in registration.waiters { waiter.resume() }
    return { try await self.wait(for: registration.id) }
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

  func waitUntilArmed(_ target: Int) async {
    await withCheckedContinuation { continuation in
      let isArmed = lock.withLock { state in
        if state.armIDs.count >= target { return true }
        state.armWaiters.append(ArmWaiter(
          target: target,
          continuation: continuation))
        return false
      }
      if isArmed { continuation.resume() }
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
  private let started = DispatchSemaphore(value: 0)
  private let deadlineResolved = DispatchSemaphore(value: 0)
  private let release = DispatchSemaphore(value: 0)

  @MainActor
  func block() {
    started.signal()
    release.wait()
  }

  func waitUntilStarted() {
    started.wait()
  }

  func recordDeadlineResolution() {
    deadlineResolved.signal()
  }

  func releaseAfterDeadlineResolution() {
    deadlineResolved.wait()
    release.signal()
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

@Suite("Observation control-plane deadlines")
struct ObservationDeadlineTests {
  @Test("A due watchdog wins while MainActor is synchronously occupied")
  @MainActor
  func watchdogExpiryIsIndependentOfMainActorAvailability() async {
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

    let conductor = Task { @concurrent in
      await sleeper.waitUntilArmed()
      blocker.waitUntilStarted()
      sleeper.fire()
      blocker.releaseAfterDeadlineResolution()
    }
    let startup = Task { @MainActor in
      try await session._visorStart()
    }

    await #expect(throws: _ObservationSourceFailure.self) {
      try await startup.value
    }
    await conductor.value
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

  @Test("A due fence deadline skips its synchronous source checkpoint")
  @MainActor
  func checkpointCannotOutrunFenceDeadline() async throws {
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
    let conductor = Task { @concurrent in
      blocker.waitUntilStarted()
      await sleeper.waitUntilArmed(armsBeforeFence + 1)
      let fenceID = sleeper.armID(at: armsBeforeFence)
      sleeper.fire(fenceID)
      blocker.releaseAfterDeadlineResolution()
    }
    let opening = Task { @MainActor in
      try await session._visorWithPause(
        { actionRan = true },
        _visorPhase: .openingFence)
    }

    await #expect(throws: _ObservationSourceFailure.self) {
      try await opening.value
    }
    await conductor.value

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

  @Test("An uncancelled sleeper CancellationError fails closed")
  @MainActor
  func sleeperCancellationErrorIsWatchdogFailure() async {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let failures = DeadlineFailureLog()
    let policy = _ObservationDeadlinePolicy { _ in
      throw CancellationError()
    }
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.suspend() }]
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
        readinessGate.open()
        return
      }
      #expect(detail.contains(
        "private observation watchdog failed while awaiting observation readiness"))
    } catch {
      Issue.record("Expected a typed watchdog failure, got \(error)")
    }

    #expect(failures.failures.count == 1)
    readinessGate.open()
    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    await stopped.wait()
  }

  @Test("Readiness deadline fails closed and eventually completes one teardown")
  @MainActor
  func readinessDeadline() async {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.suspend() }]
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

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    readinessGate.open()
    await stopped.wait()
    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test("Opening fence deadline identifies the opening phase")
  @MainActor
  func openingFenceDeadline() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let fenceGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.suspend() },
      _visorBeforePauseDrain: { await fenceGate.suspend() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.open()
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

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    fenceGate.open()
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test("Closing fence deadline identifies the closing phase")
  @MainActor
  func closingFenceDeadline() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let fenceGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(source: channel.source, handlers: [])._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.suspend() },
      _visorBeforePauseDrain: { await fenceGate.suspend() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.open()
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

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    fenceGate.open()
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test("Teardown deadline returns while one supervisor retains the true join")
  @MainActor
  func teardownDeadline() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let handlerGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let stopped = DeadlineSignal()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.suspend() }
          }]
        )._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.suspend() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.open()
    _ = try await startup.value
    let armsBeforeTeardown = sleeper.arms.count

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

    session._visorWhenStopped { stopped.fire() }
    handlerGate.open()
    await stopped.wait()

    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test("Caller cancellation before expiry stays cancellation")
  @MainActor
  func cancellationPrecedesReadinessDeadline() async {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.suspend() }]
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

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    readinessGate.open()
    await stopped.wait()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test("A latched first cause survives re-entrant caller cancellation")
  @MainActor
  func firstCausePrecedesReentrantCallerCancellation() async {
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

  @Test("Concurrent and repeated stops share one bounded teardown wait")
  @MainActor
  func teardownWaitDoesNotAccumulateObservers() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let handlerGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.suspend() }
          }]
        )._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.suspend() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.open()
    try await startup.value
    let armsBeforeTeardown = sleeper.arms.count

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
    #expect(sleeper.arms.count == armsBeforeTeardown + 1)
    sleeper.fire(armsBeforeTeardown)
    #expect(await firstStop.value == false)
    #expect(await secondStop.value == false)

    let armsAfterDeadline = sleeper.arms.count
    #expect(await session._visorStopWithinDeadline() == false)
    #expect(sleeper.arms.count == armsAfterDeadline)
    #expect(failures.failures.count == 1)

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    handlerGate.open()
    await stopped.wait()
    #expect(session._visorIsStopped)
  }

  @Test("Cancelling the last teardown waiter before expiry suppresses timeout")
  @MainActor
  func cancelledTeardownWaiterSuppressesDeadlineFailure() async throws {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let handlerGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ value in
            if value == 1 { await handlerGate.suspend() }
          }]
        )._visorErase(),
      ],
      _visorBeforeReady: { await readinessGate.suspend() },
      _visorOnFailure: failures.record,
      _visorDeadlinePolicy: deadlinePolicy(sleeper))

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()
    await sleeper.waitUntilArmed(1)
    readinessGate.open()
    try await startup.value
    let armsBeforeTeardown = sleeper.arms.count

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

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    handlerGate.open()
    await stopped.wait()
    #expect(session._visorIsStopped)
  }

  @Test("A re-entrant callback cannot replace or duplicate the first cause")
  @MainActor
  func reentrantFailurePreservesFirstCause() async {
    let channel = ObservationChannel(0)
    let readinessGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = ReentrantDeadlineFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [{ _ in await readinessGate.suspend() }]
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

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    readinessGate.open()
    await stopped.wait()
  }

  @Test("Deadline diagnostics retain a bounded source prefix")
  @MainActor
  func deadlineDiagnosticsAreBounded() async {
    let channels = (0..<10).map { ObservationChannel($0) }
    let readinessGate = DeadlineGate()
    let sleeper = DeadlineSleeper()
    let failures = DeadlineFailureLog()
    let session = _ObservationSession(
      lanes: channels.map { channel in
        _ObservationLane(
          source: channel.source,
          handlers: [])
          ._visorErase()
      },
      _visorBeforeReady: { await readinessGate.suspend() },
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

    let stopped = DeadlineSignal()
    session._visorWhenStopped { stopped.fire() }
    readinessGate.open()
    await stopped.wait()
  }
}
