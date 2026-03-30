//
//  PolledValues.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/3/2026.
//

/// Returns an `AsyncStream` that periodically reads a value on a timer.
///
/// This is the pull-based counterpart to ``valuesOf(_:)``. Use it for
/// non-observable sources (hardware sensors, system APIs, computed properties)
/// where the source doesn't participate in `@Observable`.
///
/// - Emits immediately on start (same as `valuesOf` first emission).
/// - Then sleeps for `interval` between reads.
/// - Cancellation breaks the loop cooperatively.
/// - Uses `.bufferingNewest(1)` policy.
public func polledValuesOf<T: Sendable>(
  _ read: @MainActor @Sendable @escaping () -> T,
  every interval: Duration
) -> AsyncStream<T> {
  precondition(interval > .zero, "polledValuesOf interval must be positive")
  return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
    let task = Task { @MainActor in
      // Emit immediately
      continuation.yield(read())
      do {
        while !Task.isCancelled {
          try await Task.sleep(for: interval)
          continuation.yield(read())
        }
      } catch {
        // CancellationError — exit loop
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
  }
}

/// Equatable-constrained overload that deduplicates consecutive equal values.
public func polledValuesOf<T: Sendable & Equatable>(
  _ read: @MainActor @Sendable @escaping () -> T,
  every interval: Duration
) -> AsyncStream<T> {
  precondition(interval > .zero, "polledValuesOf interval must be positive")
  return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
    let task = Task { @MainActor in
      var previous: T?
      // Emit immediately
      let initial = read()
      previous = initial
      continuation.yield(initial)
      do {
        while !Task.isCancelled {
          try await Task.sleep(for: interval)
          let value = read()
          if value != previous {
            previous = value
            continuation.yield(value)
          }
        }
      } catch {
        // CancellationError — exit loop
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
  }
}
