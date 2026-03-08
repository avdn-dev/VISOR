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
  /// The complete representation of all view state. Must be `Equatable` to enable deduplication.
  associatedtype State: Equatable
  /// The enum of user-initiated mutations. Defaults to `Never` for read-only ViewModels.
  associatedtype Action = Never

  /// The current view state. Mutate via `updateState(_:to:)` for deduplication.
  var state: State { get set }
  /// Dispatch an action. Implement sync or async as needed; the protocol requires `async`.
  func handle(_ action: Action) async
  /// Called by the `@LazyViewModel` macro's `.task` modifier to begin observation loops.
  /// Override to run custom observation; the default implementation is a no-op.
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
  /// Mutate a single state field by key path. Skips the write if the new value equals the
  /// current one, preventing unnecessary observation triggers.
  ///
  /// - Parameters:
  ///   - keyPath: A writable key path into `State`.
  ///   - value: The new value to set.
  public func updateState<V: Equatable>(
    _ keyPath: WritableKeyPath<State, V>,
    to value: V
  ) {
    guard state[keyPath: keyPath] != value else { return }
    state[keyPath: keyPath] = value
  }

  /// Non-Equatable fallback — always writes (no deduplication possible).
  public func updateState<V>(
    _ keyPath: WritableKeyPath<State, V>,
    to value: V
  ) {
    state[keyPath: keyPath] = value
  }
}


