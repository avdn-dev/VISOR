import VISORTestDoubles

@GenerateStub
public protocol MainActorCatalogueServing {
  @VISORTestDoubles.DefaultReturn("available")
  func currentStatus() async throws -> String
}

@GenerateSpy
public protocol MainActorEventRecording {
  func record(_ value: Int) async
}
