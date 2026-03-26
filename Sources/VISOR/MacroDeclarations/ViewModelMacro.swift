//
//  ViewModelMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

// MARK: - ViewModel Macro

/// Attach to a ViewModel class to auto-generate:
/// 1. Memberwise `init` from stored `let` properties (skipped if init already exists)
/// 2. `ViewModel` protocol conformance via extension
/// 3. `typealias Factory = ViewModelFactory<ClassName>`
/// 4. `@ObservationIgnored private var _state` + computed `var state` with manual observation
/// 5. `updateState(_:to:)` writing to `_state` directly for per-field granularity
/// 6. `startObserving()` combining `@Bound` and `@Reaction` observation methods
/// 7. `startObserving()` combining `@Bound` and `@Reaction` observation methods
///
/// ## State + Action pattern
///
/// Define a nested `@Observable final class State` with all view state, and an optional
/// `enum Action` with a `handle(_ action: Action) async` method:
///
/// ```swift
/// @Observable
/// @ViewModel
/// final class ItemsViewModel {
///   @Observable
///   final class State {
///     var items: Loadable<[Item]> = .loading
///     @Bound(\ItemsViewModel.service.isAuthenticated) var isAuthenticated: Bool
///   }
///
///   enum Action {
///     case refresh
///     case delete(Item.ID)
///   }
///
///   func handle(_ action: Action) async {
///     switch action {
///     case .refresh:
///       updateState(\.items, to: .loading)
///       let result = await service.fetchAll()
///       updateState(\.items, to: .loaded(result))
///     case .delete(let id):
///       try? await service.delete(id)
///     }
///   }
///
///   private let service: ItemsService
/// }
/// ```
///
/// ## @Bound inside State
///
/// `@Bound` annotations on State class properties generate observe methods that
/// use `updateState` for deduplication:
/// ```swift
/// func observeIsAuthenticated() async {
///   for await value in VISOR.valuesOf({ self.service.isAuthenticated }) {
///     self.updateState(\.isAuthenticated, to: value)
///   }
/// }
/// ```
///
/// ## Generated `startObserving()` and self-capture
///
/// When multiple `@Bound`/`@Reaction` methods exist, `startObserving()` uses
/// `withDiscardingTaskGroup` with `group.addTask { await self.observeX() }`.
/// The strong `self` capture is intentional: structured concurrency guarantees all
/// child tasks complete before the group returns, so `self` is never retained beyond
/// `startObserving()`'s lifetime.
///
/// **Important:** Do not store the Task from calling `startObserving()` on `self`
/// (e.g. `self.task = Task { await self.startObserving() }`), as this creates a
/// retain cycle. Use SwiftUI's `.task` modifier or the `observing()` test DSL instead.
@attached(member, names: named(init), named(Factory), named(startObserving), named(updateState), arbitrary)
@attached(extension, conformances: ViewModel)
public macro ViewModel() = #externalMacro(
  module: "VISORMacros",
  type: "ViewModelMacro")
