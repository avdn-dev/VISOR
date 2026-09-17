import RootTestDoubleModels
import Testing

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
