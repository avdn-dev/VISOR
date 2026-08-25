//
//  Loadable.swift
//  VISOR
//
//  Created by Anh Nguyen on 13/2/2026.
//

// MARK: - Loadable

/// A standalone enum for typed per-field loading semantics within State classes.
///
/// Use inside a ViewModel's `State` class for any field that has loading, empty,
/// loaded, and failure states:
/// ```swift
/// final class State {
///     var items: Loadable<[Item], ItemLoadFailure> = .loading
///     var filter: Filter = .all
/// }
/// ```
public enum Loadable<Value, Failure: Error> {
  /// Work is in progress and no value is available.
  case loading
  /// Work completed successfully without a value to display.
  case empty
  /// Work completed successfully with a value.
  case loaded(Value)
  /// Work failed with a typed domain error.
  case failure(Failure)
}

nonisolated extension Loadable {
  /// The loaded value, or `nil` if not in the `.loaded` state.
  public var value: Value? {
    if case .loaded(let v) = self { v } else { nil }
  }

  /// Whether the state is `.loading`.
  public var isLoading: Bool {
    if case .loading = self { true } else { false }
  }

  /// Whether the state is `.empty` (distinct from `.loaded` with an empty collection).
  public var isEmpty: Bool {
    if case .empty = self { true } else { false }
  }

  /// Whether the state is `.failure`.
  public var isFailure: Bool {
    if case .failure = self { true } else { false }
  }

  /// The typed failure, or `nil` if not in the `.failure` state.
  public var failure: Failure? {
    if case .failure(let failure) = self { failure } else { nil }
  }

  /// Transform the loaded value, preserving `loading`/`empty`/`failure` states.
  public func map<NewValue>(_ transform: (Value) -> NewValue) -> Loadable<NewValue, Failure> {
    switch self {
    case .loading: .loading
    case .empty: .empty
    case .loaded(let value): .loaded(transform(value))
    case .failure(let failure): .failure(failure)
    }
  }

  /// Transform the failure while preserving the loading state and loaded value.
  public func mapFailure<NewFailure: Error>(
    _ transform: (Failure) -> NewFailure
  ) -> Loadable<Value, NewFailure> {
    switch self {
    case .loading: .loading
    case .empty: .empty
    case .loaded(let value): .loaded(value)
    case .failure(let failure): .failure(transform(failure))
    }
  }

  /// Transform the loaded value into another `Loadable`, preserving non-loaded states.
  public func flatMap<NewValue>(
    _ transform: (Value) -> Loadable<NewValue, Failure>
  ) -> Loadable<NewValue, Failure> {
    switch self {
    case .loading: .loading
    case .empty: .empty
    case .loaded(let value): transform(value)
    case .failure(let failure): .failure(failure)
    }
  }
}

// MARK: Equatable

nonisolated extension Loadable: Equatable where Value: Equatable, Failure: Equatable { }

// MARK: Hashable

nonisolated extension Loadable: Hashable where Value: Hashable, Failure: Hashable { }

// MARK: Sendable

nonisolated extension Loadable: Sendable where Value: Sendable, Failure: Sendable { }
