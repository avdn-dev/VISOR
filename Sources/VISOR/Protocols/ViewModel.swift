//
//  ViewModel.swift
//  VISOR
//
//  Created by Anh Nguyen on 13/2/2026.
//

@_exported import Observation
// MARK: - Loadable

/// A standalone enum for per-field loading semantics within State structs.
///
/// Use inside a ViewModel's `State` struct for any field that has loading/empty/error states:
/// ```swift
/// struct State: Equatable {
///     var items: Loadable<[Item]> = .loading
///     var filter: Filter = .all
/// }
/// ```
public enum Loadable<Value> {
  case loading
  case empty
  case loaded(Value)
  case error(String)
}

nonisolated extension Loadable {
  public var value: Value? { if case .loaded(let v) = self { v } else { nil } }
  public var isLoading: Bool { if case .loading = self { true } else { false } }
  public var isEmpty: Bool { if case .empty = self { true } else { false } }
  public var isError: Bool { if case .error = self { true } else { false } }
  public var error: String? { if case .error(let msg) = self { msg } else { nil } }

  public func map<U>(_ transform: (Value) -> U) -> Loadable<U> {
    switch self {
    case .loading: .loading
    case .empty: .empty
    case .loaded(let v): .loaded(transform(v))
    case .error(let msg): .error(msg)
    }
  }

  public func flatMap<U>(_ transform: (Value) -> Loadable<U>) -> Loadable<U> {
    switch self {
    case .loading: .loading
    case .empty: .empty
    case .loaded(let v): transform(v)
    case .error(let msg): .error(msg)
    }
  }
}

nonisolated extension Loadable: Equatable where Value: Equatable {}
nonisolated extension Loadable: Hashable where Value: Hashable {}
nonisolated extension Loadable: Sendable where Value: Sendable {}

// MARK: - ViewModel Protocol

/// The base protocol for all ViewModels in the VISOR architecture.
///
/// Conforming types must be `@Observable` classes with an `Equatable` `State` struct
/// and an optional `Action` enum for user-initiated mutations.
///
/// - State is the complete representation of all view state.
/// - Actions are dispatched via `send(_:)` (sync) or `perform(_:)` (async).
/// - Use `updateState(_:to:)` for keypath-based mutation with deduplication.
///
/// - Note: Requires Swift 6.2+ with `MainActorByDefault` enabled in the consuming target.
public protocol ViewModel: Observable, AnyObject {
  associatedtype State: Equatable
  associatedtype Action = Never

  var state: State { get set }
  func perform(_ action: Action) async
  func startObserving() async
}

extension ViewModel {
  public func startObserving() async {}
}

extension ViewModel where Action == Never {
  public func perform(_ action: Never) async {}
}

// MARK: - updateState (keypath mutation with deduplication)

extension ViewModel {
  /// Equatable overload: skips write if value unchanged (prevents observation trigger).
  public func updateState<V: Equatable>(
    _ keyPath: WritableKeyPath<State, V>,
    to value: V
  ) {
    guard state[keyPath: keyPath] != value else { return }
    state[keyPath: keyPath] = value
  }

  /// Non-Equatable fallback: always writes.
  public func updateState<V>(
    _ keyPath: WritableKeyPath<State, V>,
    to value: V
  ) {
    state[keyPath: keyPath] = value
  }
}

// MARK: - send (sync convenience for views)

extension ViewModel {
  /// Sync dispatch for use in button closures and other synchronous view contexts.
  /// For async contexts (`.task`, `.refreshable`), call `await perform(_:)` directly.
  public func send(_ action: Action) {
    Task { await perform(action) }
  }
}

