import RootTestingModelsNonisolated
import RootTestingSupport
import Testing
import VISORTesting

@Suite("Root VISORTesting from a nonisolated target")
struct RootTestingBoundaryTests {
  @Test
  func `Public observation errors can be handled downstream`() {
    let error = ObservationTestError.resultUnavailable

    #expect(error.errorDescription?.contains("State window was unavailable") == true)
  }

  @Test
  @MainActor
  func `The generated model supports source-fenced public testing APIs`() async throws {
    let service = RootTestingService(initialValue: 1)
    let sut = NonisolatedRootTestingViewModel(service: service)

    try await observe(sut) { test in
      #expect(sut.state.sourceValue == 1)
      #expect(sut.state.reactedValue == 1)

      await test.perform(.setCount(2))
      test.expect(\.count, hasExactChanges: [2])
      test.expect(\.count, alwaysSatisfies: { (0...2).contains($0) })

      await test.perform {
        service.publish(3)
      }
      test.expect(\.sourceValue, hasExactChanges: [3])
      test.expect(\.reactedValue, alwaysSatisfies: { $0 > 0 })
    }
  }
}
