import VISOR

/// Yields execution so `withObservationTracking` can register its onChange handler
/// after the previous value was consumed. Required because observation tracking is
/// set up asynchronously on @MainActor after `iterator.next()` returns.
func yieldForTracking() async throws {
  try await Task.sleep(for: .milliseconds(50))
}
