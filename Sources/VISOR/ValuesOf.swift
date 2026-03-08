//
//  ValuesOf.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import Observation

/// Returns an `AsyncStream` that emits the current value produced by `emit` and re-emits on every change.
///
/// This is a closure-based alternative to `Observable.values(of:)` that works with
/// protocol existentials (where `KeyPath<Self, T>` cannot be used due to the `Self` requirement).
///
/// - On iOS 26+: Backed by `Observations` (SE-0475, transactional did-set semantics — the
///   closure is re-evaluated **after** the new value is committed).
/// - On earlier OS versions: Backed by ``ObservationSequence`` using `withObservationTracking`
///   (will-set semantics — the signal fires **before** the new value is committed, so the
///   closure is re-evaluated on the next iteration to capture the updated value).
///
/// The `emit` closure is re-evaluated on **every** change to **any** tracked property,
/// not just the property you care about. Use the `Equatable`-constrained overload to
/// automatically deduplicate consecutive equal values.
///
/// The stream uses `.bufferingNewest(1)` — intermediate values may be dropped if the
/// consumer is slower than the producer. When the observing task is cancelled, the stream
/// finishes cooperatively.
public func valuesOf<T: Sendable>(
  _ emit: @MainActor @Sendable @escaping () -> T
) -> AsyncStream<T> {
  if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, macCatalyst 26, *) {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let observations = Observations { emit() }
      let task = Task { @MainActor in
        for await value in observations {
          guard !Task.isCancelled else { break }
          continuation.yield(value)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  } else {
    ObservationSequence { emit() }.stream
  }
}

/// Equatable-constrained overload that deduplicates consecutive equal values.
///
/// The compiler prefers this more-constrained overload automatically when `T`
/// conforms to `Equatable`. Skips emissions when the new value equals the previous one,
/// which is common when the `emit` closure tracks multiple properties but only one changed.
public func valuesOf<T: Sendable & Equatable>(
  _ emit: @MainActor @Sendable @escaping () -> T
) -> AsyncStream<T> {
  if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, macCatalyst 26, *) {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let observations = Observations { emit() }
      let task = Task { @MainActor in
        var previous: T?
        for await value in observations {
          guard !Task.isCancelled else { break }
          if value != previous {
            previous = value
            continuation.yield(value)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  } else {
    ObservationSequence(deduplicating: emit).stream
  }
}

/// Observes the latest value and runs the handler, cancelling any previous in-flight handler
/// when a new value arrives. Useful for side-effect reactions where only the latest matters.
///
/// - **Cancellation is cooperative**: the previous handler's `Task` is cancelled, but the
///   handler must check `Task.isCancelled` to exit promptly.
/// - **Final handler lifetime**: when the observed stream finishes, the last spawned handler
///   task is cancelled. It may briefly outlive this function if it has in-flight async work.
///   In practice this is safe when used inside `withDiscardingTaskGroup` (as `@ViewModel`
///   generates), since the group cancels all child tasks on exit.
@MainActor
public func latestValuesOf<T: Sendable>(
  _ emit: @MainActor @Sendable @escaping () -> T,
  handler: @MainActor @Sendable @escaping (T) async -> Void
) async {
  var handlerTask: Task<Void, Never>?
  for await value in valuesOf(emit) {
    handlerTask?.cancel()
    handlerTask = Task { await handler(value) }
  }
  handlerTask?.cancel()
}

