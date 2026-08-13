import Testing
import VISOR
import VISORObservation

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

@MainActor
private final class ObservationSessionStressBarrier {
  private struct Waiter {
    let target: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private var arrivalCount = 0
  private var waiters: [Waiter] = []

  deinit {}

  func arrive() {
    arrivalCount += 1
    let ready = waiters.filter { $0.target <= arrivalCount }
    waiters.removeAll { $0.target <= arrivalCount }
    for waiter in ready {
      waiter.continuation.resume()
    }
  }

  func waitUntilArrived(_ target: Int) async {
    guard arrivalCount < target else { return }
    await withCheckedContinuation { continuation in
      waiters.append(Waiter(target: target, continuation: continuation))
    }
  }
}

nonisolated private enum ObservationFailureWaitOutcome: Equatable, Sendable {
  case failure(_ObservationSourceFailure)
  case cancelled
  case unexpected(String)
}

@Suite("Observation session waiter stress", .timeLimit(.minutes(1)))
struct ObservationSessionStressTests {
  private static let waiterCount = 64

  @Test
  @MainActor
  func `Many failure waiters preserve cancellation and the first cause`() async throws {
    let channel = ObservationChannel(0)
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [])._visorErase(),
    ])
    try await session._visorStart()

    let barrier = ObservationSessionStressBarrier()
    let waiters: [Task<ObservationFailureWaitOutcome, Never>] =
      (0..<Self.waiterCount).map { _ in
        Task { @MainActor in
          barrier.arrive()
          do {
            return .failure(try await session._visorWaitForFailure())
          } catch is CancellationError {
            return .cancelled
          } catch {
            return .unexpected(String(describing: error))
          }
        }
      }

    await barrier.waitUntilArrived(Self.waiterCount)
    for index in waiters.indices where index.isMultiple(of: 2) {
      waiters[index].cancel()
    }

    let expected = _ObservationSourceFailure.failed("stress failure")
    channel._visorTerminate(with: expected)

    for (index, waiter) in waiters.enumerated() {
      let outcome = await waiter.value
      if index.isMultiple(of: 2) {
        #expect(outcome == .cancelled)
      } else {
        #expect(outcome == .failure(expected))
      }
    }

    let lateOutcomes = await withTaskGroup(
      of: ObservationFailureWaitOutcome.self,
      returning: [ObservationFailureWaitOutcome].self
    ) { group in
      for _ in 0..<Self.waiterCount {
        group.addTask {
          do {
            return .failure(try await session._visorWaitForFailure())
          } catch is CancellationError {
            return .cancelled
          } catch {
            return .unexpected(String(describing: error))
          }
        }
      }

      var outcomes: [ObservationFailureWaitOutcome] = []
      for await outcome in group {
        outcomes.append(outcome)
      }
      return outcomes
    }
    #expect(lateOutcomes.count == Self.waiterCount)
    #expect(lateOutcomes.allSatisfy { $0 == .failure(expected) })

    await session._visorStop()
    #expect(session._visorFailure == expected)
    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  @MainActor
  func `Clean stop cancels every pending failure waiter`() async throws {
    let channel = ObservationChannel(0)
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [])._visorErase(),
    ])
    try await session._visorStart()

    let barrier = ObservationSessionStressBarrier()
    let waiters: [Task<ObservationFailureWaitOutcome, Never>] =
      (0..<Self.waiterCount).map { _ in
        Task { @MainActor in
          barrier.arrive()
          do {
            return .failure(try await session._visorWaitForFailure())
          } catch is CancellationError {
            return .cancelled
          } catch {
            return .unexpected(String(describing: error))
          }
        }
      }

    await barrier.waitUntilArrived(Self.waiterCount)
    await session._visorStop()

    for waiter in waiters {
      #expect(await waiter.value == .cancelled)
    }
    await #expect(throws: CancellationError.self) {
      try await session._visorWaitForFailure()
    }
    #expect(session._visorFailure == nil)
    #expect(session._visorIsStopped)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }
}
