import VISORTestDoubles

// MARK: - ActorStatusService

@MainActor
@GenerateSpy
@GenerateStub
public protocol ActorStatusService: Sendable {
  func record(_ value: Int)
}
