import ExternalModelsMainActor
import ExternalServices
import Testing
import VISORTesting

@Suite("External source-fenced MainActor consumer")
struct ExternalSourceFencedObservationTests {
  @Test
  @MainActor
  func `Generated recipe remains lifecycle-capability free downstream`() async throws {
    let service = ExternalSyncService()
    await service.publish(4)
    let sut = ExternalSourceBackedViewModel(service: service)

    try await observe(sut) { test in
      #expect(sut.state.revision == 4)
      #expect(sut.state.reactedRevision == 4)

      await test.perform {
        await service.synchronise()
      }

      test.expect(\.revision, hasExactChanges: [5])
      test.expect(\.reactedRevision, hasExactChanges: [5])
    }

    await service.publish(6)
    #expect(sut.state.revision == 5)
  }
}
