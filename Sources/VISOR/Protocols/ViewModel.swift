//
//  ViewModel.swift
//  VISOR
//
//  Created by Anh Nguyen on 13/2/2026.
//

import Observation

// MARK: - ViewModel

/// The base protocol for all ViewModels in the VISOR architecture.
///
/// Conforming types are explicitly MainActor-isolated, final `@Observable` classes
/// with a stable routed `State` instance and an optional `Action` enum for
/// user-initiated mutations. `@ViewModel` generates the State gateway,
/// observation recipe, ownership token and stable `bindings` namespace.
///
/// - ViewModels use a plain nested `final class State` retained by a stored
///   `let state` property.
/// - Actions dispatch synchronously via `handle(_:)` and return a completion value.
/// - State changes use generated mutation selectors; UI action proposals use `bindings`.
@MainActor
public protocol ViewModel: Observable, AnyObject {
  /// The complete observable representation of all view state.
  associatedtype State: Observable & _ViewModelState
  /// The enum of user-initiated mutations. Defaults to `Never` for read-only ViewModels.
  associatedtype Action = Never

  /// Generated typed binding selectors. Public only for macro expansions.
  associatedtype _VISORBindingSelectors

  /// The generated binding selector namespace.
  static var _visorBindingSelectors: _VISORBindingSelectors { get }

  /// SwiftUI bindings sharing a stable, model-owned reference root.
  var bindings: ViewModelBindings<Self> { get }

  /// The current stable view state. Conforming models retain this as a stored
  /// `let state` property.
  var state: State { get }
  /// An inert per-instance token used by VISOR's hidden SwiftUI owner to
  /// serialise observation generations for this ViewModel identity.
  var _visorObservationOwnership: _ViewModelObservationOwnership { get }

  /// Describes cooperative observation sources to VISOR's package-owned
  /// runtime. `@ViewModel` generates this hook.
  func _visorBuildObservationRecipe(into visitor: _ObservationRecipeVisitor)
  /// Dispatches an action immediately and returns the completion of its work.
  /// Return `.completed` for synchronous work or an effect handle's `completion`.
  /// Callers may ignore the value or explicitly await its `wait()` method.
  @discardableResult
  func handle(_ action: Action) -> ActionCompletion
}

extension ViewModel {

  // MARK: Public

  public func _visorBuildObservationRecipe(
    into _: _ObservationRecipeVisitor
  ) { }

  // MARK: Package

  package func _visorMakeObservationRecipes() -> [_ObservationRecipe] {
    let visitor = _ObservationRecipeVisitor()
    _visorBuildObservationRecipe(into: visitor)
    return visitor.recipes
  }
}

extension ViewModel where Action == Never {
  /// Handles the uninhabited default action without requiring boilerplate.
  @discardableResult
  public func handle(_: Never) -> ActionCompletion { }
}
