//
//  ViewModel.swift
//  VISOR
//
//  Created by Anh Nguyen on 13/2/2026.
//

import Observation

// MARK: - ViewModel Protocol

/// The base protocol for all ViewModels in the VISOR architecture.
///
/// Conforming types are explicitly MainActor-isolated `@Observable` classes
/// with a stable routed `State` instance and an optional `Action` enum for
/// user-initiated mutations. `@ViewModel` generates the State gateway,
/// observation recipe and ownership token.
///
/// - ViewModels use a plain nested `final class State` retained by a stored
///   `let state` property.
/// - Actions are dispatched via `handle(_:)`. Implement sync or async as needed.
/// - State changes are routed through generated selectors.
@MainActor
public protocol ViewModel: Observable, AnyObject {
  /// The complete observable representation of all view state.
  associatedtype State: Observable & _ViewModelState
  /// The enum of user-initiated mutations. Defaults to `Never` for read-only ViewModels.
  associatedtype Action = Never

  /// The current stable view state. Conforming models retain this as a stored
  /// `let state` property.
  var state: State { get }
  /// An inert per-instance token used by VISOR's hidden SwiftUI owner to
  /// serialise observation generations for this ViewModel identity.
  var _visorObservationOwnership: _ViewModelObservationOwnership { get }
  /// Describes cooperative observation sources to VISOR's package-owned
  /// runtime. `@ViewModel` generates this hook.
  func _visorBuildObservationRecipe(into visitor: _ObservationRecipeVisitor)
  /// Dispatch an action. Implement sync or async as needed; the protocol requires `async`.
  func handle(_ action: Action) async
}

extension ViewModel {
  public func _visorBuildObservationRecipe(
    into visitor: _ObservationRecipeVisitor
  ) {}

  package func _visorMakeObservationRecipes() -> [_ObservationRecipe] {
    let visitor = _ObservationRecipeVisitor()
    _visorBuildObservationRecipe(into: visitor)
    return visitor.recipes
  }
}

extension ViewModel where Action == Never {
  /// Handles the uninhabited default action without requiring boilerplate.
  public func handle(_ action: Never) async {}
}
