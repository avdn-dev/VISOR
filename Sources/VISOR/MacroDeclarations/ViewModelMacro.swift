//
//  ViewModelMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

// MARK: - ViewModel Macro

/// Attach to an explicitly MainActor-isolated, final `@Observable` ViewModel class.
/// Share behaviour through composition and injected protocols, not inheritance.
/// The macro adds VISOR-owned Observation accessors to a plain nested
/// `final class State`, groups `@Bound(source:)` and `@Reaction(source:)`
/// entries into declarative recipes, and synthesises a stable stored `let state`
/// and dependency initialiser when State construction is unambiguous.
/// It also generates `ViewModel` conformance, a stable model-owned `bindings`
/// namespace, and `typealias Factory = ViewModelFactory<ClassName>`.
///
/// ## Source-backed State + Action pattern
///
/// Define a plain nested `final class State` and uninitialised stored `let`
/// dependencies, and use cooperative `ObservationSource` key paths. Omit the
/// ViewModel's `state` property and initialiser to use synthesis:
///
/// ```swift
/// @MainActor
/// @Observable
/// @ViewModel
/// final class ItemsViewModel {
///   final class State {
///     var items: Loadable<[Item], ItemLoadFailure> = .loading
///     @Bound(
///       source: \ItemsViewModel.service.source,
///       selecting: \ItemsSnapshot.isAuthenticated)
///     var isAuthenticated = false
///   }
///
///   enum Action {
///     case refresh
///     case delete(Item.ID)
///   }
///
///   @discardableResult
///   func handle(_ action: Action) -> ActionCompletion {
///     switch action {
///     case .refresh:
///       state[\.items] = .loading
///       return refresh.run(for: self) { [service] in
///         await service.fetchAll()
///       } receive: { model, items in
///         model.updateState(\.items, to: .loaded(items))
///       }.completion
///     case .delete(let id):
///       return deletions.run(for: self) { [service] in
///         try await service.delete(id)
///       } receive: { model, result in
///         if case .failure = result {
///           model.updateState(\.items, to: .failure(.deleteFailed))
///         }
///       }.completion
///     }
///   }
///
///   private let service: ItemsService
///   private let refresh = LatestEffect()
///   private let deletions = ConcurrentEffects()
/// }
/// ```
///
/// See <doc:Architecture#State-initialisation> for construction rules.
@attached(
  member,
  names:
  named(Factory),
  named(bindings),
  named(_visorObservationOwnership),
  named(_visorBuildObservationRecipe),
  arbitrary
)
@attached(memberAttribute)
@attached(extension, conformances: ViewModel)
public macro ViewModel() = #externalMacro(
  module: "VISORMacros",
  type: "ViewModelMacro",
)
