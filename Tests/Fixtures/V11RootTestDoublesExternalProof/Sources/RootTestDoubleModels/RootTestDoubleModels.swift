import VISORTestDoubles

// MARK: - CatalogueServing

@GenerateStub
public protocol CatalogueServing {
  @VISORTestDoubles.DefaultValue(["featured"])
  var itemNames: [String] { get }

  @VISORTestDoubles.DefaultReturn("available")

  func currentStatus() -> String
}

// MARK: - QualifiedDefaultServing

@GenerateStub
public protocol QualifiedDefaultServing {
  var isEnabled: Swift.Bool { get }
  var itemIDs: [Swift.Int] { get }

  func selectedID() -> Swift.Int?
}

// MARK: - EventRecording

@GenerateSpy(.sendable)
nonisolated public protocol EventRecording: Sendable {
  func record(_ value: Int)
}

// MARK: - CollidingCatalogueServing

@GenerateStub
public protocol CollidingCatalogueServing {
  var currentStatusReturnValue: Int { get }

  func currentStatus() -> String
}

// MARK: - OverloadedEventRecording

@GenerateSpy
public protocol OverloadedEventRecording {
  var calls: Int { get }

  func record(value: String)
  func record(value: Int)
}

// MARK: - StructuralCollisionRecording

@GenerateSpy(.sendable)
nonisolated public protocol StructuralCollisionRecording: Sendable {
  typealias _Storage = Int

  var _testDoubleStorage: Int { get }
  var calls: Int { get }

  func record(_ value: Int)
}
