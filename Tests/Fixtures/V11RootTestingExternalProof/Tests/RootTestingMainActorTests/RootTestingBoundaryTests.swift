import RootTestingModelsMainActor
import RootTestingSupport
import Testing
import VISORTesting

@Suite("Root VISORTesting from a MainActor-by-default target")
struct RootTestingBoundaryTests {
  @Test
  func `Controllable operations remain isolation-neutral and Sendable`() async throws {
    // Given
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare(metadata: "request")

    // When
    operation.resolveAllInvocations(with: .success(7))
    let result = await Task.detached {
      await operation.run(invocation)
    }.value
    try await operation.waitUntilStarted(count: 1)
    try await operation.waitUntilFinished(count: 1)

    // Then
    #expect(invocation.ordinal == 1)
    #expect(invocation.metadata == "request")
    #expect(result == 7)
    #expect(operation.finishedCount == 1)
  }

  @Test
  func `The generated model supports source-fenced public testing APIs`() async throws {
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
