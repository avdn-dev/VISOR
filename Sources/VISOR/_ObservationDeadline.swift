import Foundation
import os
import VISORObservation

// MARK: - _ObservationDeadlinePhase

nonisolated package enum _ObservationDeadlinePhase: Equatable, Sendable {
  case readiness
  case openingFence
  case closingFence
  case fence
  case teardownJoin

  // MARK: Internal

  var diagnosticName: String {
    switch self {
    case .readiness:
      "observation readiness"
    case .openingFence:
      "opening action fence"
    case .closingFence:
      "closing action fence"
    case .fence:
      "observation fence"
    case .teardownJoin:
      "teardown join"
    }
  }
}

// MARK: - _ObservationDeadlinePolicy

/// Package-only policy seam for deterministic control-plane deadline proofs.
/// Consumer domain clocks never enter this policy.
nonisolated package struct _ObservationDeadlinePolicy: Sendable {

  // MARK: Lifecycle

  package init(
    readiness: Duration,
    openingFence: Duration,
    closingFence: Duration,
    fence: Duration,
    teardownJoin: Duration,
    sleeper: @escaping Sleeper,
    _visorDidResolveDeadline:
    @escaping @Sendable (_ phase: _ObservationDeadlinePhase) -> Void = { _ in },
  ) {
    self.readiness = readiness
    self.openingFence = openingFence
    self.closingFence = closingFence
    self.fence = fence
    self.teardownJoin = teardownJoin
    makeWatchdog = { duration in
      { try await sleeper(duration) }
    }
    didResolveDeadline = _visorDidResolveDeadline
  }

  package init(
    readiness: Duration,
    openingFence: Duration,
    closingFence: Duration,
    fence: Duration,
    teardownJoin: Duration,
    _visorWatchdogFactory: @escaping WatchdogFactory,
    _visorDidResolveDeadline:
    @escaping @Sendable (_ phase: _ObservationDeadlinePhase) -> Void = { _ in },
  ) {
    self.readiness = readiness
    self.openingFence = openingFence
    self.closingFence = closingFence
    self.fence = fence
    self.teardownJoin = teardownJoin
    makeWatchdog = _visorWatchdogFactory
    didResolveDeadline = _visorDidResolveDeadline
  }

  package init(
    duration: Duration = .zero,
    sleeper: @escaping Sleeper,
    _visorDidResolveDeadline:
    @escaping @Sendable (_ phase: _ObservationDeadlinePhase) -> Void = { _ in },
  ) {
    self.init(
      readiness: duration,
      openingFence: duration,
      closingFence: duration,
      fence: duration,
      teardownJoin: duration,
      sleeper: sleeper,
      _visorDidResolveDeadline: _visorDidResolveDeadline,
    )
  }

  // MARK: Package

  package typealias Sleeper =
    @concurrent @Sendable (_ duration: Duration) async throws -> Void
  package typealias ArmedWatchdog =
    @concurrent @Sendable () async throws -> Void
  package typealias WatchdogFactory =
    @Sendable (_ duration: Duration) -> ArmedWatchdog

  package static let production: Self = {
    // Production liveness is deliberately independent of every consumer or
    // domain clock. ContinuousClock is monotonic and cannot be advanced by a
    // test double supplied to application code.
    let clock = ContinuousClock()
    return Self(
      readiness: .seconds(30),
      openingFence: .seconds(10),
      closingFence: .seconds(10),
      fence: .seconds(10),
      teardownJoin: .seconds(10),
      _visorWatchdogFactory: { duration in
        // Capture an absolute monotonic deadline synchronously. The watchdog
        // cannot gain extra time merely because its concurrent Task is
        // scheduled after MainActor begins synchronous control-plane work.
        let deadline = clock.now.advanced(by: duration)
        return {
          try await clock.sleep(until: deadline)
        }
      },
    )
  }()

  // MARK: Internal

  let readiness: Duration
  let openingFence: Duration
  let closingFence: Duration
  let fence: Duration
  let teardownJoin: Duration
  let makeWatchdog: WatchdogFactory
  let didResolveDeadline:
    @Sendable (_ phase: _ObservationDeadlinePhase) -> Void

  func duration(for phase: _ObservationDeadlinePhase) -> Duration {
    switch phase {
    case .readiness:
      readiness
    case .openingFence:
      openingFence
    case .closingFence:
      closingFence
    case .fence:
      fence
    case .teardownJoin:
      teardownJoin
    }
  }

}

// MARK: - _ObservationControlCompletion

nonisolated enum _ObservationControlCompletion<Value: Sendable>:
  Sendable
{
  case success(Value)
  case failure(_ObservationSourceFailure)
  case cancelled
}

// MARK: - _ObservationDeadlineRaceOutcome

nonisolated enum _ObservationDeadlineRaceOutcome<Value: Sendable>:
  Sendable
{
  case operation(_ObservationControlCompletion<Value>)
  case deadline
  case watchdogFailure(_ObservationSourceFailure)
  case callerCancellation
}

// MARK: - _ObservationDeadlineRaceLatch

/// A one-shot race latch. Its lock protects only non-suspending state changes;
/// continuations are removed while locked and always resumed after unlocking.
nonisolated private final class _ObservationDeadlineRaceLatch<Value: Sendable>:
  Sendable
{

  // MARK: Internal

  typealias Outcome = _ObservationDeadlineRaceOutcome<Value>

  @discardableResult
  func resolve(_ outcome: Outcome) -> Bool {
    let resolution: (didWin: Bool, waiters: [Waiter]) =
      lock.withLock { state in
        guard state.outcome == nil else { return (false, []) }
        state.outcome = outcome
        let waiters = Array(state.waiters.values)
        state.waiters.removeAll(keepingCapacity: false)
        return (true, waiters)
      }
    for waiter in resolution.waiters {
      waiter.resume(returning: outcome)
    }
    return resolution.didWin
  }

  func wait() async -> Outcome {
    let id = UUID()
    return await withCheckedContinuation { continuation in
      let immediate: Outcome? = lock.withLock { state in
        if let outcome = state.outcome {
          return outcome
        }
        state.waiters[id] = continuation
        return nil
      }
      if let immediate {
        continuation.resume(returning: immediate)
      }
    }
  }

  func hasResolved() -> Bool {
    lock.withLock { $0.outcome != nil }
  }

  // MARK: Private

  private typealias Waiter = CheckedContinuation<Outcome, Never>

  private struct State: Sendable {
    var outcome: Outcome?
    var waiters = [UUID: Waiter]()
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

}

// MARK: - _ObservationDeadlinePreparationAborted

nonisolated struct _ObservationDeadlinePreparationAborted: Error { }

// MARK: - _ObservationTeardownDeadlineCoordinator

/// Coordinates every concurrent wait on one teardown deadline. Only one true
/// join callback and one watchdog are retained, while all active callers are
/// released together when that shared race resolves.
nonisolated final class _ObservationTeardownDeadlineCoordinator: Sendable {

  // MARK: Internal

  typealias Outcome = _ObservationDeadlineRaceOutcome<Void>

  func registerWaiter(isCancelled: Bool) -> UUID {
    let id = UUID()
    lock.withLock { state in
      guard state.outcome == nil else { return }
      state.waiters[id] = WaiterState(
        isCancelled: isCancelled,
        continuation: nil,
      )
    }
    return id
  }

  func wait(for id: UUID) async -> Outcome {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let immediate: Outcome? = lock.withLock { state in
          if let outcome = state.outcome {
            return outcome
          }
          guard var waiter = state.waiters[id] else {
            preconditionFailure("A teardown waiter must register before waiting")
          }
          waiter.continuation = continuation
          state.waiters[id] = waiter
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      lock.withLock { state in
        guard var waiter = state.waiters[id] else { return }
        waiter.isCancelled = true
        state.waiters[id] = waiter
      }
    }
  }

  @discardableResult
  func resolveJoined() -> Bool {
    resolve(.operation(.success(())), reportsDeadline: false).didWin
  }

  func resolveDeadline() -> (didWin: Bool, shouldReport: Bool) {
    resolve(.deadline, reportsDeadline: true)
  }

  func resolveWatchdogFailure(
    _ failure: _ObservationSourceFailure
  ) -> (didWin: Bool, shouldReport: Bool) {
    resolve(.watchdogFailure(failure), reportsDeadline: true)
  }

  // MARK: Private

  private typealias Waiter = CheckedContinuation<Outcome, Never>

  private struct WaiterState: Sendable {
    var isCancelled: Bool
    var continuation: Waiter?
  }

  private struct State: Sendable {
    var outcome: Outcome?
    var waiters = [UUID: WaiterState]()
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  private func resolve(
    _ outcome: Outcome,
    reportsDeadline: Bool,
  ) -> (didWin: Bool, shouldReport: Bool) {
    let resolution: (
      didWin: Bool,
      shouldReport: Bool,
      waiters: [Waiter],
    ) = lock.withLock { state in
      guard state.outcome == nil else { return (false, false, []) }
      // Deadline eligibility and outcome publication share this one
      // linearisation point. Cancellation can be wholly before or after it,
      // never in a stale snapshot gap between two locks.
      let shouldReport = reportsDeadline
        && state.waiters.values.contains { !$0.isCancelled }
      state.outcome = outcome
      let waiters = state.waiters.values.compactMap(\.continuation)
      state.waiters.removeAll(keepingCapacity: false)
      return (true, shouldReport, waiters)
    }
    for waiter in resolution.waiters {
      waiter.resume(returning: outcome)
    }
    return (resolution.didWin, resolution.shouldReport)
  }
}

@MainActor
extension _ObservationSession {
  func runWithDeadline<Value: Sendable>(
    phase: _ObservationDeadlinePhase,
    operation: @escaping @MainActor () async throws -> Value,
  ) async -> _ObservationControlCompletion<Value> {
    await runWithDeadline(
      phase: phase,
      synchronousPreparation: { _ in () },
      operation: { _ in try await operation() },
    )
  }

  func runWithDeadline<Preparation: Sendable, Value: Sendable>(
    phase: _ObservationDeadlinePhase,
    synchronousPreparation:
    @MainActor (_ deadlineHasResolved: @Sendable () -> Bool) throws
      -> Preparation,
    operation:
    @escaping @MainActor (Preparation) async throws -> Value,
  ) async -> _ObservationControlCompletion<Value> {
    let race = _ObservationDeadlineRaceLatch<Value>()
    let duration = deadlinePolicy.duration(for: phase)
    let armedWatchdog = deadlinePolicy.makeWatchdog(duration)
    let didResolveDeadline = deadlinePolicy.didResolveDeadline
    // The factory has synchronously captured the production clock's absolute
    // deadline before any control-plane preparation. The isolation-neutral
    // watchdog may therefore publish expiry while MainActor is occupied.
    let watchdog = Task { @concurrent in
      do {
        try await armedWatchdog()
        guard race.resolve(.deadline) else { return }
        didResolveDeadline(phase)
        await self.deadlineDidFire(phase: phase)
      } catch is CancellationError where Task.isCancelled {
        // The operation or its caller cancelled this losing watchdog.
      } catch {
        let failure = _ObservationSourceFailure.failed(
          "The private observation watchdog failed while awaiting \(phase.diagnosticName): \(String(describing: error))"
        )
        guard race.resolve(.watchdogFailure(failure)) else { return }
        didResolveDeadline(phase)
        await self.controlPlaneFailed(failure)
      }
    }

    let preparation: _ObservationControlCompletion<Preparation>
    do {
      preparation = .success(
        try synchronousPreparation { race.hasResolved() }
      )
    } catch is _ObservationDeadlinePreparationAborted {
      // The watchdog already owns the race. Do not publish a second outcome or
      // enter the asynchronous operation after synchronous preparation exits.
      preparation = .cancelled
    } catch is CancellationError {
      preparation = .cancelled
    } catch let failure as _ObservationSourceFailure {
      preparation = .failure(failure)
    } catch {
      preparation = .failure(.failed(String(describing: error)))
    }

    switch preparation {
    case .failure(let failure):
      // Synchronous preparation participates in the same occurrence-order
      // race. If an off-actor expiry already won while MainActor was blocked,
      // this later failure cannot replace it.
      if race.resolve(.operation(.failure(failure))) {
        controlPlaneFailed(failure)
      }

    case .cancelled:
      race.resolve(.operation(.cancelled))

    case .success:
      break
    }

    let operationID = UUID()
    let operationTask = Task { @MainActor in
      guard case .success(let prepared) = preparation else { return }
      let completion: _ObservationControlCompletion<Value>
      do {
        completion = .success(try await operation(prepared))
      } catch is CancellationError {
        completion = .cancelled
      } catch let failure as _ObservationSourceFailure {
        completion = .failure(failure)
      } catch {
        completion = .failure(.failed(String(describing: error)))
      }
      if case .failure(let failure) = completion {
        // The race itself defines occurrence order against an off-actor
        // watchdog. A losing operation must not replace an expiry that became
        // due while MainActor was unavailable.
        guard race.resolve(.operation(completion)) else { return }
        self.controlPlaneFailed(failure)
        return
      }
      race.resolve(.operation(completion))
    }
    installControlTask(operationTask, id: operationID)

    let outcome = await withTaskCancellationHandler {
      await race.wait()
    } onCancel: {
      guard race.resolve(.callerCancellation) else { return }
      operationTask.cancel()
      watchdog.cancel()
    }

    switch outcome {
    case .operation(let completion):
      watchdog.cancel()
      await operationTask.value
      clearControlTask(id: operationID)
      switch completion {
      case .cancelled:
        if let failure {
          return .failure(failure)
        }
        return .cancelled

      case .failure(let operationFailure):
        return .failure(failure ?? operationFailure)

      case .success:
        if let failure {
          return .failure(failure)
        }
        return completion
      }

    case .callerCancellation:
      operationTask.cancel()
      watchdog.cancel()
      beginTeardownForDeadlineSupport()
      if let failure {
        return .failure(failure)
      }
      return .cancelled

    case .deadline:
      operationTask.cancel()
      await watchdog.value
      return .failure(
        failure ?? deadlineFailure(for: phase)
      )

    case .watchdogFailure(let watchdogFailure):
      operationTask.cancel()
      await watchdog.value
      return .failure(failure ?? watchdogFailure)
    }
  }

  func awaitTeardownWithinDeadline() async -> Bool {
    let coordinator: _ObservationTeardownDeadlineCoordinator
    let shouldStartWatchdog: Bool
    if let activeCoordinator = teardownDeadlineCoordinator {
      coordinator = activeCoordinator
      shouldStartWatchdog = false
    } else {
      let newCoordinator = _ObservationTeardownDeadlineCoordinator()
      coordinator = newCoordinator
      shouldStartWatchdog = true
      teardownDeadlineCoordinator = newCoordinator
      _visorWhenStopped {
        newCoordinator.resolveJoined()
      }
    }

    // Register the live caller before an injected zero-duration sleeper can
    // publish expiry; deadline reporting eligibility is then never sampled
    // from an artificially empty waiter set.
    let waiterID = coordinator.registerWaiter(
      isCancelled: Task.isCancelled
    )

    if shouldStartWatchdog {
      let duration = deadlinePolicy.duration(for: .teardownJoin)
      let armedWatchdog = deadlinePolicy.makeWatchdog(duration)
      let didResolveDeadline = deadlinePolicy.didResolveDeadline
      teardownDeadlineWatchdog = Task { @concurrent [weak self] in
        do {
          try await armedWatchdog()
          let resolution = coordinator.resolveDeadline()
          guard resolution.didWin else { return }
          didResolveDeadline(.teardownJoin)
          await self?.markTeardownDeadlineWaitEnded()
          guard resolution.shouldReport else { return }
          await self?.deadlineDidFire(phase: .teardownJoin)
        } catch is CancellationError where Task.isCancelled {
          // Joined teardown cancels this losing watchdog.
        } catch {
          let failure = _ObservationSourceFailure.failed(
            "The private observation watchdog failed while awaiting teardown join: \(String(describing: error))"
          )
          let resolution = coordinator.resolveWatchdogFailure(failure)
          guard resolution.didWin else { return }
          didResolveDeadline(.teardownJoin)
          await self?.markTeardownDeadlineWaitEnded()
          guard resolution.shouldReport else { return }
          await self?.controlPlaneFailed(failure)
        }
      }
    }

    let outcome = await coordinator.wait(for: waiterID)

    switch outcome {
    case .operation:
      finishTeardownDeadlineWait(coordinator)
      return true

    case .deadline, .watchdogFailure:
      if let watchdog = teardownDeadlineWatchdog {
        await watchdog.value
      }
      finishTeardownDeadlineWait(coordinator)
      markTeardownDeadlineWaitEnded()
      return false

    case .callerCancellation:
      preconditionFailure("Teardown races do not resolve as caller cancellation")
    }
  }
}
