//
//  Expectation.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

/// An error thrown by ``Expectation`` streaming assertions when the expected condition
/// is not met.
public enum ExpectationError: Error, CustomStringConvertible {

    /// The value at `keyPath` was already the target before any change occurred.
    case alreadyEqual(keyPath: String, valueDescription: String)

    /// ``becomes`` encountered a non-target intermediate value.
    case unexpectedValue(keyPath: String, expectedDescription: String, actualDescription: String)

    /// The assertion timed out waiting for a change.
    case timedOut(keyPath: String, duration: Duration)

    public var description: String {
        switch self {
        case .alreadyEqual(let keyPath, let value):
            return "Expected \(keyPath) to change from \(value), but it was already \(value)"
        case .unexpectedValue(let keyPath, let expected, let actual):
            return "Expected \(keyPath) to become \(expected), but got \(actual)"
        case .timedOut(let keyPath, let duration):
            return "Expected \(keyPath) to change within \(duration)"
        }
    }
}

/// Test scope bound to an `Observable`, providing streaming assertions via `callAsFunction`.
///
/// Use ``becomes`` for strict streaming (fail on any intermediate deviation)
/// and ``eventually`` for lenient streaming (tolerate intermediate values).
///
/// Both skip the initial emission, so they only return after a genuine change.
/// Use `#expect` for snapshot checks.
///
/// ```swift
/// await observing(vm) { expect in
///     #expect(vm.state.count == 0)
///     source.count = 42
///     try await expect(\.state.count, becomes: 42)
/// }
/// ```
@MainActor
public struct Expectation<O: Observable> {
    fileprivate let observable: O

    // MARK: - Streaming assertions

    /// Awaits until the property at `keyPath` changes to `expected`.
    ///
    /// Skips the initial value. Fails with ``ExpectationError/unexpectedValue`` if any
    /// intermediate emission differs from `expected`. Fails with ``ExpectationError/timedOut``
    /// if `timeout` elapses.
    public func callAsFunction<T: Equatable & Sendable>(
        _ keyPath: KeyPath<O, T>,
        becomes expected: T,
        timeout: Duration = .seconds(2)
    ) async throws {
        let initial = observable[keyPath: keyPath]
        guard initial != expected else {
            throw ExpectationError.alreadyEqual(
                keyPath: "\(keyPath)", valueDescription: "\(initial)")
        }
        try await withStreamingTimeout(timeout, keyPath: keyPath) {
            var first = true
            for await value in valuesOf({ self.observable[keyPath: keyPath] }) {
                if first {
                    first = false
                    if value == initial { continue }
                    // Mutation happened before stream captured initial — treat
                    // this first emission as a real change.
                    guard value == expected else {
                        throw ExpectationError.unexpectedValue(
                            keyPath: "\(keyPath)",
                            expectedDescription: "\(expected)",
                            actualDescription: "\(value)")
                    }
                    return
                }
                guard value == expected else {
                    throw ExpectationError.unexpectedValue(
                        keyPath: "\(keyPath)",
                        expectedDescription: "\(expected)",
                        actualDescription: "\(value)")
                }
                return
            }
        }
    }

    /// Awaits until the property at `keyPath` reaches `expected`, tolerating
    /// intermediate values that differ.
    ///
    /// Skips the initial value. Unlike ``becomes``, does not fail on non-target
    /// intermediate emissions. Fails with ``ExpectationError/timedOut`` if
    /// `timeout` elapses.
    public func callAsFunction<T: Equatable & Sendable>(
        _ keyPath: KeyPath<O, T>,
        eventually expected: T,
        timeout: Duration = .seconds(2)
    ) async throws {
        let initial = observable[keyPath: keyPath]
        guard initial != expected else {
            throw ExpectationError.alreadyEqual(
                keyPath: "\(keyPath)", valueDescription: "\(initial)")
        }
        try await withStreamingTimeout(timeout, keyPath: keyPath) {
            var first = true
            for await value in valuesOf({ self.observable[keyPath: keyPath] }) {
                if first {
                    first = false
                    if value == initial { continue }
                    // Mutation happened before stream captured initial.
                    if value == expected { return }
                    continue
                }
                if value == expected { return }
            }
        }
    }

    // MARK: - Deprecated

    @available(*, deprecated, message: "Use #expect for snapshot checks, or becomes for strict streaming assertions.")
    public func callAsFunction<T: Equatable & Sendable>(
        _ keyPath: KeyPath<O, T>,
        equals expected: T
    ) async {
        for await value in valuesOf({ self.observable[keyPath: keyPath] }) {
            if value == expected { return }
        }
    }

    @available(*, deprecated, message: "Use #expect(… != …) for snapshot checks.")
    public func callAsFunction<T: Equatable & Sendable>(
        _ keyPath: KeyPath<O, T>,
        isNot expected: T
    ) async {
        for await value in valuesOf({ self.observable[keyPath: keyPath] }) {
            if value != expected { return }
        }
    }

    @available(*, deprecated, message: "Use eventually(_:) for lenient value waiting, or a valuesOf loop for predicate-based waiting.")
    public func callAsFunction<T: Sendable>(
        _ keyPath: KeyPath<O, T>,
        satisfies predicate: @escaping @Sendable (T) -> Bool
    ) async {
        for await value in valuesOf({ self.observable[keyPath: keyPath] }) {
            if predicate(value) { return }
        }
    }
}

// MARK: - Timeout helper

/// Runs `body` in a task group that races it against a `Task.sleep` of `timeout`.
/// If the sleep wins, the stream task is cancelled and `ExpectationError.timedOut` is thrown.
@MainActor
private func withStreamingTimeout<T>(
    _ timeout: Duration,
    keyPath: KeyPath<some Observable, T>,
    body: @MainActor @Sendable @escaping () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(operation: body)
        group.addTask {
            try await Task.sleep(for: timeout)
            throw CancellationError()
        }
        do {
            try await group.next()
            group.cancelAll()
        } catch is CancellationError {
            group.cancelAll()
            throw ExpectationError.timedOut(keyPath: "\(keyPath)", duration: timeout)
        } catch {
            group.cancelAll()
            throw error
        }
    }
}

// MARK: - observing overloads

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
    try await body(Expectation(observable: viewModel))
}

/// Provides an ``Expectation`` callable for a plain `@Observable` type.
///
/// Unlike the ``ViewModel`` overload, this does not start or cancel any observation
/// loops — the `@Observable` type manages its own reactivity.
@MainActor
public func observing<O: Observable>(
    _ observable: O,
    body: (Expectation<O>) async throws -> Void
) async rethrows {
    try await body(Expectation(observable: observable))
}
