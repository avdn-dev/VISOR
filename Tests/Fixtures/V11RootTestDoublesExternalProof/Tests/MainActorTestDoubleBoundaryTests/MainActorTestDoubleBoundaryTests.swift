import MainActorTestDoubleModels
import Testing

@Suite("MainActor-by-default VISORTestDoubles boundary")
struct MainActorTestDoubleBoundaryTests {
  @Test
  func `An ordinary async stub retains the consumer isolation domain`() async throws {
    let stub = StubMainActorCatalogueServing()

    #expect(try await stub.currentStatus() == "available")
  }

  @Test
  func `A Sendable concurrent spy crosses a MainActor-default boundary`() async {
    let spy = SpyMainActorEventRecording()

    await spy.record(42)

    #expect(spy.recordCallCount == 1)
    #expect(spy.recordReceivedValue == 42)
  }
}
