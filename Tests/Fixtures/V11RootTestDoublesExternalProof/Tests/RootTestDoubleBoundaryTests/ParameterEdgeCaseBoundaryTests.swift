import RootTestDoubleModels
import Testing

@Suite("Generated parameter external boundary")
struct ParameterEdgeCaseBoundaryTests {
  @Test
  func `A public spy binds anonymous and escaped parameters`() {
    let spy = SpyParameterEdgeCaseRecording()

    spy.record(17)
    spy.store(repeat: "ready")

    #expect(spy.recordReceivedArgument1 == 17)
    #expect(spy.storeReceivedDefault == "ready")
    #expect(spy.calls.count == 2)
  }
}
