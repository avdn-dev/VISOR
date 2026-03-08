//
//  ViewModel.swift
//  VISOR
//
//  Created by Anh Nguyen on 13/2/2026.
//

@_exported import Observation

// MARK: - ViewModel Protocol

/// The base protocol for all ViewModels in the VISOR architecture.
///
/// Conforming types must be `@Observable` classes with an `Equatable` `State` struct
/// and an optional `Action` enum for user-initiated mutations.
///
/// - State is the complete representation of all view state.
/// - Actions are dispatched via `handle(_:)`. Implement sync or async as needed.
/// - Use `updateState(_:to:)` for keypath-based mutation with deduplication.
///
/// - Note: Requires Swift 6.2+ with `MainActorByDefault` enabled in the consuming target.
public protocol ViewModel: Observable, AnyObject {
  associatedtype State: Equatable
  associatedtype Action = Never

  var state: State { get set }
  func handle(_ action: Action) async
  func startObserving() async
}

extension ViewModel {
  public func startObserving() async {}
}

extension ViewModel where Action == Never {
  public func handle(_ action: Never) async {}
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


