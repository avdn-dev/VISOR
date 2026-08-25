import VISORTestDoubles

// MARK: - MainActorCatalogueServing

@GenerateStub
public protocol MainActorCatalogueServing {
  @VISORTestDoubles.DefaultReturn("available")
  func currentStatus() async throws -> String
}

// MARK: - MainActorEventRecording

@GenerateSpy(.sendable)
nonisolated public protocol MainActorEventRecording: Sendable {
  @concurrent
  func record(_ value: Int) async
}
