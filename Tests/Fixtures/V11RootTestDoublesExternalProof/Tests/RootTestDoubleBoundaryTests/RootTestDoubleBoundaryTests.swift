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
  func `A public stub defaults canonical Swift spellings across the module boundary`() {
    let stub = StubQualifiedDefaultServing()

    #expect(stub.isEnabled == false)
    #expect(stub.itemIDs.isEmpty)
    #expect(stub.selectedID() == nil)
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

  @Test
  func `A public stub avoids protocol return-storage collisions`() {
    let stub = StubCollidingCatalogueServing()

    stub.currentStatusReturnValue = 7
    stub.currentStatusReturnValueGenerated = "ready"

    #expect(stub.currentStatusReturnValue == 7)
    #expect(stub.currentStatus() == "ready")
  }

  @Test
  func `A public spy separates same-label overloads and its call log`() {
    let spy = SpyOverloadedEventRecording()

    spy.record(value: "event")
    spy.record(value: 9)

    #expect(spy.calls == 0)
    #expect(spy.recordValueReturningVoidWithStringCallCount == 1)
    #expect(spy.recordValueReturningVoidWithIntCallCount == 1)
    #expect(spy.recordedCalls.count == 2)
  }

  @Test
  func `A public Sendable spy avoids structural storage collisions`() {
    let spy = SpyStructuralCollisionRecording()

    spy.record(11)

    #expect(spy._testDoubleStorage == 0)
    #expect(spy.calls == 0)
    #expect(spy.recordCallCount == 1)
    #expect(spy.recordedCalls.count == 1)
  }
}
