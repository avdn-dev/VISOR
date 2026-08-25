import Testing
import VISOR
import VISORObservation
import VISORTesting

// MARK: - ObservationFailureWaitOutcome

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

nonisolated private enum ObservationFailureWaitOutcome: Equatable, Sendable {
  case failure(_ObservationSourceFailure)
  case cancelled
  case unexpected(String)
}

// MARK: - ObservationSessionStressTests

@Suite("Observation session waiter stress", .timeLimit(.minutes(1)))
struct ObservationSessionStressTests {

  // MARK: Internal

  @Test
  @MainActor
  func `Many failure waiters preserve cancellation and the first cause`() async throws {
    let channel = ObservationChannel(0)
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [],
      )._visorErase()
    ])
    try await session._visorStart()

    let barrier = TestEventCounter()
    let waiters: [Task<ObservationFailureWaitOutcome, Never>] =
      (0..<Self.waiterCount).map { _ in
        Task { @MainActor in
          barrier.record()
          do {
            return .failure(try await session._visorWaitForFailure())
          } catch is CancellationError {
            return .cancelled
          } catch {
            return .unexpected(String(describing: error))
          }
        }
      }

    try await barrier.wait(for: Self.waiterCount)
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
      returning: [ObservationFailureWaitOutcome].self,
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

      var outcomes = [ObservationFailureWaitOutcome]()
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
        handlers: [],
      )._visorErase()
    ])
    try await session._visorStart()

    let barrier = TestEventCounter()
    let waiters: [Task<ObservationFailureWaitOutcome, Never>] =
      (0..<Self.waiterCount).map { _ in
        Task { @MainActor in
          barrier.record()
          do {
            return .failure(try await session._visorWaitForFailure())
          } catch is CancellationError {
            return .cancelled
          } catch {
            return .unexpected(String(describing: error))
          }
        }
      }

    try await barrier.wait(for: Self.waiterCount)
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

  // MARK: Private

  private static let waiterCount = 64

}
