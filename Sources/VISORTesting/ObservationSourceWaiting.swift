import VISORObservation

extension ObservationSource {
  /// Suspends until the baseline or a later latest snapshot satisfies
  /// `predicate`.
  ///
  /// This helper does not impose its own deadline. Apply Swift Testing's
  /// `timeLimit(_:)` trait to the enclosing test or suite. Cancelling the test
  /// closes the source subscription and throws `CancellationError`.
  public func waitUntil(
    _ predicate: @escaping @Sendable (Value) throws -> Bool
  ) async throws {
    guard try await first(where: predicate) != nil else {
      throw CancellationError()
    }
  }
}
