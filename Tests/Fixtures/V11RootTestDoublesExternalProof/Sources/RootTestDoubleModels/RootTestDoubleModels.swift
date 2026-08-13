import VISORTestDoubles

@GenerateStub
public protocol CatalogueServing {
  @VISORTestDoubles.DefaultValue(["featured"])
  var itemNames: [String] { get }

  @VISORTestDoubles.DefaultReturn("available")
  func currentStatus() -> String
}

@GenerateSpy(.sendable)
nonisolated public protocol EventRecording: Sendable {
  func record(_ value: Int)
}
