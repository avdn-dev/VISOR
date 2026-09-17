import VISORTestDoubles

// MARK: - ActorMeasurementService

/// Exercises Sendable references with caller-owned, non-Sendable work.
@MainActor
@GenerateSpy(.sendable)
public protocol ActorMeasurementService: Sendable {
  func record(_ value: Int)
  func measure<Value>(_ body: () async throws -> Value) async rethrows -> Value
}
