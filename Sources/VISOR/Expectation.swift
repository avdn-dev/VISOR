//
//  Expectation.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

/// Test scope bound to a ViewModel, providing observation assertions via `callAsFunction`.
///
/// Used inside ``observing(_:body:)`` to await property changes on a ViewModel:
/// ```swift
/// await observing(vm) { expect in
///   source.count = 42
///   await expect(\.count, equals: 42)
/// }
/// ```
///
/// Each assertion spins a `valuesOf()` loop that terminates as soon as the condition is met.
/// Use Swift Testing's `@Test(.timeLimit(...))` to bound execution if the expected value
/// never arrives — the DSL itself does not impose a timeout.
@MainActor
public struct Expectation<VM: Observable> {
  package let viewModel: VM

  /// Awaits until the property at `keyPath` equals `expected`.
  public func callAsFunction<T: Equatable & Sendable>(
    _ keyPath: KeyPath<VM, T>,
    equals expected: T
  ) async {
    for await value in valuesOf({ self.viewModel[keyPath: keyPath] }) {
      if value == expected { return }
    }
  }

  /// Awaits until the property at `keyPath` does NOT equal `expected`.
  public func callAsFunction<T: Equatable & Sendable>(
    _ keyPath: KeyPath<VM, T>,
    isNot expected: T
  ) async {
    for await value in valuesOf({ self.viewModel[keyPath: keyPath] }) {
      if value != expected { return }
    }
  }

  /// Awaits until the property at `keyPath` satisfies `predicate`.
  public func callAsFunction<T: Sendable>(
    _ keyPath: KeyPath<VM, T>,
    satisfies predicate: @escaping @Sendable (T) -> Bool
  ) async {
    for await value in valuesOf({ self.viewModel[keyPath: keyPath] }) {
      if predicate(value) { return }
    }
  }
}

/// Starts observation on the ViewModel, provides an ``Expectation`` callable to the body,
/// and cancels observation when the body returns.
///
/// The ViewModel's `startObserving()` runs in a child task that is cancelled when `body`
/// returns or throws. This ensures observation is scoped to the test assertion block.
@MainActor
public func observing<VM: ViewModel>(
  _ viewModel: VM,
  body: (Expectation<VM>) async throws -> Void
) async rethrows {
  let task = Task { await viewModel.startObserving() }
  defer { task.cancel() }
  try await body(Expectation(viewModel: viewModel))
}
