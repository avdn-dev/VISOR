import PackageTestDoubleModels
import Testing

@Suite("Package test-double boundary")
struct PackageTestDoubleConsumerTests {
  @Test
  func `Ordinary package peer can be constructed across targets`() {
    let stub = StubPackageCatalogueServing()
    stub.countReturnValue = 42

    #expect(stub.count() == 42)
  }

  @Test
  func `Sendable package peer can be constructed across targets`() {
    let spy = SpyPackageEventRecording()

    spy.record(42)

    #expect(spy.recordCallCount == 1)
    #expect(spy.recordReceivedValue == 42)
  }
}
