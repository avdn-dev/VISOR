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
/// Conforming types must be `@Observable` classes with a nested `@Observable final class State`
/// and an optional `Action` enum for user-initiated mutations.
///
/// - State is an `@Observable` class for per-field SwiftUI granularity.
/// - Actions are dispatched via `handle(_:)`. Implement sync or async as needed.
/// - `updateState(_:to:)` is macro-generated on each VM using `_state` directly.
///
/// - Note: Requires Swift 6.2+ with `MainActorByDefault` enabled in the consuming target.
public protocol ViewModel: Observable, AnyObject {
  /// The complete representation of all view state. Must be an `@Observable` class.
  associatedtype State: Observable, AnyObject
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
