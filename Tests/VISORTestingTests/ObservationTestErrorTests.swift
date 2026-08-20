import Testing
import VISORTesting

@Suite("Observation test errors")
struct ObservationTestErrorTests {
  @Test
  func `Unavailable result has a stable public diagnostic`() {
    let error = ObservationTestError.resultUnavailable

    #expect(error.errorDescription?.contains("State window was unavailable") == true)
  }
}
