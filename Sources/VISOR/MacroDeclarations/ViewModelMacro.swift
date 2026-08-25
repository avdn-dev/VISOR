//
//  ViewModelMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

// MARK: - ViewModel Macro

/// Attach to an explicitly MainActor-isolated, `@Observable` ViewModel class.
/// The macro adds VISOR-owned Observation accessors to a plain nested
/// `final class State`, groups `@Bound(source:)` and `@Reaction(source:)`
/// entries into declarative recipes, and requires a stable stored `let state`.
/// It also generates `ViewModel` conformance and
/// `typealias Factory = ViewModelFactory<ClassName>`.
///
/// ## Source-backed State + Action pattern
///
/// Define a plain nested `final class State`, retain it in `let state`, and use
/// cooperative `ObservationSource` key paths:
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
///   let state = State()
///
///   enum Action {
///     case refresh
///     case delete(Item.ID)
///   }
///
///   func handle(_ action: Action) async {
///     switch action {
///     case .refresh:
///       state[\.items] = .loading
///       let result = await service.fetchAll()
///       state[\.items] = .loaded(result)
///     case .delete(let id):
///       do {
///         try await service.delete(id)
///       } catch {
///         state[\.items] = .failure(.deleteFailed)
///       }
///     }
///   }
///
///   private let service: ItemsService
///
///   init(service: ItemsService) {
///     self.service = service
///   }
/// }
/// ```
@attached(
  member,
  names:
  named(Factory),
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
