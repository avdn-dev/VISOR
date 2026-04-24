//
//  Loadable.swift
//  VISOR
//
//  Created by Anh Nguyen on 13/2/2026.
//

/// A standalone enum for per-field loading semantics within State classes.
///
/// Use inside a ViewModel's `State` class for any field that has loading/empty/error states:
/// ```swift
/// @Observable
/// final class State {
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
  /// The loaded value, or `nil` if not in the `.loaded` state.
  public var value: Value? { if case .loaded(let v) = self { v } else { nil } }
  /// Whether the state is `.loading`.
  public var isLoading: Bool { if case .loading = self { true } else { false } }
  /// Whether the state is `.empty` (distinct from `.loaded` with an empty collection).
  public var isEmpty: Bool { if case .empty = self { true } else { false } }
  /// Whether the state is `.error`.
  public var isError: Bool { if case .error = self { true } else { false } }
  /// The error message, or `nil` if not in the `.error` state.
  public var error: String? { if case .error(let msg) = self { msg } else { nil } }

  /// Transform the loaded value, preserving `loading`/`empty`/`error` states.
  public func map<U>(_ transform: (Value) -> U) -> Loadable<U> {
    switch self {
    case .loading: .loading
    case .empty: .empty
    case .loaded(let v): .loaded(transform(v))
    case .error(let msg): .error(msg)
    }
  }

  /// Transform the loaded value into another `Loadable`, preserving `loading`/`empty`/`error` states.
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
