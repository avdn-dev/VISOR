import RootTestDoubleModels
import Testing

@Suite("Root VISORTestDoubles external boundary")
struct RootTestDoubleBoundaryTests {
  @Test
  func `A public stub carries qualified custom defaults across the module boundary`() {
    let stub = StubCatalogueServing()

    #expect(stub.itemNames == ["featured"])
    #expect(stub.currentStatus() == "available")
  }

  @Test
  func `A public Sendable spy records concurrent calls across the module boundary`() async {
    let spy = SpyEventRecording()

    await withTaskGroup(of: Void.self) { group in
      for value in 0..<100 {
        group.addTask {
          spy.record(value)
        }
      }
    }

    #expect(spy.recordCallCount == 100)
    #expect(Set(spy.recordReceivedInvocations) == Set(0..<100))
  }
}
