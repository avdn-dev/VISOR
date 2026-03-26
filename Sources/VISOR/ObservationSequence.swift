//
//  ObservationSequence.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//


/// Custom `AsyncSequence` for pre-iOS 26, wrapping `withObservationTracking` in an `AsyncStream`.
///
/// Emits the initial value immediately, then re-emits whenever a tracked property changes.
/// Uses will-set semantics (fires before the new value is committed), so the closure
/// is re-evaluated after the signal resumes to capture the updated value.
///
/// ## Design: Nested AsyncStream
///
/// Uses an internal `AsyncStream<Void>` signal channel instead of `withCheckedContinuation`
/// so that task cancellation is prompt — `AsyncStream.Iterator.next()` cooperatively returns
/// `nil` on cancellation, allowing the inner task to exit immediately without waiting for
/// a property change. The extra allocation is a deliberate trade-off for correct cancellation
/// behaviour. On iOS 26+, `valuesOf()` uses `Observations` (SE-0475) instead.
package struct ObservationSequence<Element: Sendable>: AsyncSequence, Sendable {
  package typealias AsyncIterator = AsyncStream<Element>.AsyncIterator
  package let stream: AsyncStream<Element>

  package init(_ emit: @MainActor @Sendable @escaping () -> Element) {
    self.stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task { @MainActor in
        // Signal channel: onChange yields Void, for-await wakes the loop.
        // When the inner task is cancelled, `for await` returns nil promptly.
        let (signal, signalContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

        // Fused: withObservationTracking returns emit()'s value, registering
        // tracking and reading the value in a single call (not two).
        let initial = withObservationTracking { emit() } onChange: {
          signalContinuation.yield()
        }
        continuation.yield(initial)

        // When the task is cancelled, signal.next() returns nil — the loop exits.
        for await _ in signal {
          guard !Task.isCancelled else { break }
          let value = withObservationTracking { emit() } onChange: {
            signalContinuation.yield()
          }
          continuation.yield(value)
        }

        signalContinuation.finish()
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Deduplicating initialiser that skips emissions when the new value equals the previous one.
  /// Eliminates the extra AsyncStream + Task wrapper that the Equatable `valuesOf()` overload
  /// would otherwise need for pre-iOS 26.
  package init(
    deduplicating emit: @MainActor @Sendable @escaping () -> Element
  ) where Element: Equatable {
    self.stream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task { @MainActor in
        let (signal, signalContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

        let initial = withObservationTracking { emit() } onChange: {
          signalContinuation.yield()
        }
        continuation.yield(initial)
        var previous = initial

        // When the task is cancelled, signal.next() returns nil — the loop exits.
        for await _ in signal {
          guard !Task.isCancelled else { break }
          let value = withObservationTracking { emit() } onChange: {
            signalContinuation.yield()
          }
          if value != previous {
            previous = value
            continuation.yield(value)
          }
        }

        signalContinuation.finish()
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  package func makeAsyncIterator() -> AsyncIterator {
    stream.makeAsyncIterator()
  }
}
