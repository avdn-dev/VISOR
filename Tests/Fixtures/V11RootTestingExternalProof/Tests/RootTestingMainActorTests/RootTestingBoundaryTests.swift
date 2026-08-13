import RootTestingModelsMainActor
import RootTestingSupport
import VISORTesting

@Suite("Root VISORTesting from a MainActor-by-default target")
struct RootTestingBoundaryTests {
  @Test("The generated model supports source-fenced public testing APIs")
  func generatedModelSupportsSourceFencedPublicTestingAPIs() async throws {
    let service = RootTestingService(initialValue: 4)
    let sut = MainActorRootTestingViewModel(service: service)

    try await observe(sut) { test in
      #expect(sut.state.sourceValue == 4)
      #expect(sut.state.reactedValue == 4)

      await test.perform(.setCount(5))
      test.expect(\.count, hasExactChanges: [5])
      test.expect(\.count, alwaysSatisfies: { (0...5).contains($0) })

      await test.perform {
        service.publish(6)
      }
      test.expect(\.sourceValue, hasExactChanges: [6])
      test.expect(\.reactedValue, alwaysSatisfies: { $0 > 0 })
    }
  }
}
