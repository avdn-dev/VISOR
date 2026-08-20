import Observation
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

@GenerateStub
public protocol CollidingCatalogueServing {
  var currentStatusReturnValue: Int { get }
  func currentStatus() -> String
}

@GenerateSpy
public protocol OverloadedEventRecording {
  var calls: Int { get }
  func record(value: String)
  func record(value: Int)
}

@GenerateSpy(.sendable)
nonisolated public protocol StructuralCollisionRecording: Sendable {
  typealias _Storage = Int
  var _testDoubleStorage: Int { get }
  var calls: Int { get }
  func record(_ value: Int)
}
