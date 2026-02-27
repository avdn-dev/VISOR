//
//  ViewModel.swift
//  VISOR
//
//  Created by Anh Nguyen on 13/2/2026.
//

@_exported import Observation

/// The base protocol for all ViewModels in the VISOR architecture.
///
/// Conforming types must be `@Observable` classes that expose a `state` property
/// describing the current view state, and optionally implement `startObserving()`
/// to begin async observation of service dependencies.
///
/// - Note: Requires Swift 6.2+ with `MainActorByDefault` enabled in the consuming target.
public protocol ViewModel: Observable, AnyObject {
  associatedtype State

  var state: ViewModelState<State> { get }
  func startObserving() async
}

extension ViewModel {
  public func startObserving() async { }
}

/// The state machine driving a ViewModel's view.
///
/// Transitions: `loading` → `loaded(state:)` | `empty` | `error(_:)`.
/// Use `loadedState` to unwrap the associated value when in the `loaded` case.
public enum ViewModelState<S> {
  case loading
  case empty
  case loaded(state: S)
  case error(String)
}

nonisolated extension ViewModelState {
  public var loadedState: S? {
    if case .loaded(let state) = self { return state }
    return nil
  }
}

nonisolated extension ViewModelState: Equatable where S: Equatable {}
nonisolated extension ViewModelState: Hashable where S: Hashable {}
nonisolated extension ViewModelState: Sendable where S: Sendable {}
