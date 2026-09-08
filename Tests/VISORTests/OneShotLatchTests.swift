import Testing
import VISOR
import VISORTesting

@Suite(.timeLimit(.minutes(1)))
struct OneShotLatchTests {

  @Test
  func `First resolution remains available to every later waiter`() async {
    // Given
    let latch = OneShotLatch<Int>()
    #expect(latch.resolvedValue == nil)

    // When
    let firstWon = latch.resolve(42)
    let secondWon = latch.resolve(99)

    // Then
    #expect(firstWon)
    #expect(!secondWon)
    #expect(latch.resolvedValue == 42)
    #expect(await latch.wait() == 42)
    #expect(await latch.wait() == 42)
  }

  @Test
  func `An optional nil value is a completed resolution`() async {
    // Given
    let latch = OneShotLatch<Int?>()

    // When
    let firstWon = latch.resolve(nil)
    let secondWon = latch.resolve(42)

    // Then
    #expect(firstWon)
    #expect(!secondWon)
    #expect(latch.resolvedValue != nil)
    #expect(latch.resolvedValue == .some(nil))
    #expect(await latch.wait() == nil)
  }

  @Test
  @MainActor
  func `One resolution releases every suspended waiter`() async throws {
    // Given
    let latch = OneShotLatch<Int>()
    let entered = TestEventCounter()
    let waiters = (0..<8).map { _ in
      Task { @MainActor in
        entered.record()
        return await latch.wait()
      }
    }
    // wait() stays on this actor through continuation registration, so all
    // recorded waiters are suspended before this actor resumes the test.
    try await entered.wait(untilEventCount: waiters.count)

    // When
    let won = latch.resolve(42)

    // Then
    #expect(won)
    for waiter in waiters {
      #expect(await waiter.value == 42)
    }
    #expect(await latch.wait() == 42)
  }

  @Test
  func `Concurrent resolvers agree on exactly one winner`() async {
    // Given
    let latch = OneShotLatch<Int>()

    // When
    let outcomes = await withTaskGroup(of: (candidate: Int, won: Bool, value: Int).self) { group in
      for candidate in 0..<64 {
        group.addTask {
          let won = latch.resolve(candidate)
          return (candidate, won, await latch.wait())
        }
      }
      var outcomes = [(candidate: Int, won: Bool, value: Int)]()
      for await outcome in group {
        outcomes.append(outcome)
      }
      return outcomes
    }

    // Then
    let winners = outcomes.filter(\.won)
    #expect(winners.count == 1)
    #expect(outcomes.allSatisfy { $0.value == winners.first?.candidate })
    #expect(latch.resolvedValue == winners.first?.candidate)
  }

  @Test
  @MainActor
  func `Cancelling a waiter leaves resolution with the owner`() async throws {
    // Given
    let latch = OneShotLatch<Int>()
    let entered = TestEventCounter()
    let waiter = Task { @MainActor in
      entered.record()
      let value = await latch.wait()
      return (value: value, cancelled: Task.isCancelled)
    }
    try await entered.wait()

    // When
    waiter.cancel()

    // Then
    #expect(latch.resolvedValue == nil)

    // When
    latch.resolve(42)
    let outcome = await waiter.value

    // Then
    #expect(outcome.value == 42)
    #expect(outcome.cancelled)
  }

  @Test
  @MainActor
  func `Cancellation before waiting does not replace the owners value`() async {
    // Given
    let latch = OneShotLatch<Int>()
    let waiter = Task { @MainActor in
      let wasCancelled = Task.isCancelled
      return (value: await latch.wait(), cancelled: wasCancelled)
    }

    // When
    waiter.cancel()
    latch.resolve(42)
    let outcome = await waiter.value

    // Then
    #expect(outcome.cancelled)
    #expect(outcome.value == 42)
  }
}
