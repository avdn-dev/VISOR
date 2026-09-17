import Testing
import VISORTestDoubles

// MARK: - ActorMeasurementService

/// Exercises Sendable references with caller-owned, non-Sendable work.
@MainActor
@GenerateSpy(.sendable)
protocol ActorMeasurementService: Sendable {
  func record(_ value: Int)
  func measure<Value>(_ body: () async throws -> Value) async rethrows -> Value
}

// MARK: - ActorMeasurementBoundaryTests

@MainActor
struct ActorMeasurementBoundaryTests {
  @Test
  func `Sendable spies retain actor owned measurement values`() async {
    // Given
    let spy = SpyActorMeasurementService()
    let service: any ActorMeasurementService = spy
    let value = LocalMeasurementValue()

    // When
    let result = await service.measure {
      value.count += 1
      return value
    }
    await Task.detached { await service.record(7) }.value

    // Then
    #expect(result === value)
    #expect(value.count == 1)
    #expect(spy.measureCallCount == 1)
    #expect(spy.recordReceivedValue == 7)
  }

}

// MARK: - LocalMeasurementValue

private final class LocalMeasurementValue {
  var count = 0
}
