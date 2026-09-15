import Observation
import os
import Testing
import VISORObservation

// MARK: - ObservationStateTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ObservationStateTests {
  @Test
  func `Observable State preserves equality and publication across the package boundary`() async throws {
    let producer = Producer()
    let values = producer.valueValues.makeAsyncIterator()
    #expect(try await values.next() == 0)

    let changeCount = OSAllocatedUnfairLock(initialState: 0)
    withObservationTracking {
      _ = producer.value
    } onChange: {
      changeCount.withLock { $0 += 1 }
    }

    producer.value = 0

    #expect(try await values.next() == 0)
    #expect(changeCount.withLock { $0 } == 0)

    producer.value = 1

    #expect(producer.valueValues.currentSnapshot() == 1)
    #expect(try await values.next() == 1)
    #expect(changeCount.withLock { $0 } == 1)
  }
}

// MARK: - Producer

@MainActor
@Observable
private final class Producer {
  @ObservationState(observedAs: .values)
  @ObservationIgnored var value = 0
}
