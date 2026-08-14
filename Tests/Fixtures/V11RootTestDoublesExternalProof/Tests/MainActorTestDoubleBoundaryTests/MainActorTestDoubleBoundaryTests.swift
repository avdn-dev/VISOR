import MainActorTestDoubleModels
import Testing

@Suite("MainActor-by-default VISORTestDoubles boundary")
struct MainActorTestDoubleBoundaryTests {
  @Test
  func `Ordinary async peers retain the consumer isolation domain`() async throws {
    let stub = StubMainActorCatalogueServing()
    let spy = SpyMainActorEventRecording()

    #expect(try await stub.currentStatus() == "available")

    await spy.record(42)

    #expect(spy.recordCallCount == 1)
    #expect(spy.recordReceivedValue == 42)
  }
}
