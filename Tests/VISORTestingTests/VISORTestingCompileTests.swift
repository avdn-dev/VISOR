import Testing
import VISORTesting

@Suite("VISORTesting package surface")
struct VISORTestingCompileTests {
  @Test
  func `Module imports without default actor isolation`() {
    #expect(Bool(true))
  }
}
