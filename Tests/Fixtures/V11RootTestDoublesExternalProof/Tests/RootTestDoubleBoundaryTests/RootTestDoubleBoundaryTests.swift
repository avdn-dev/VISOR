import RootTestDoubleModels
import Testing

@Suite("Root VISORTestDoubles external boundary")
struct RootTestDoubleBoundaryTests {
  @Test("A public stub carries qualified custom defaults across the module boundary")
  func publicStubCarriesQualifiedDefaults() {
    let stub = StubCatalogueServing()

    #expect(stub.itemNames == ["featured"])
    #expect(stub.currentStatus() == "available")
  }

  @Test("A public Sendable spy records concurrent calls across the module boundary")
  func publicSendableSpyRecordsConcurrentCalls() async {
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
