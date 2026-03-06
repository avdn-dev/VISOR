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
/// 4. `static var preview` (using `Stub*` types for dependencies)
/// 5. `PreviewProviding` conformance
/// 6. `startObserving()` combining `@Bound`, `@Reaction`, and `deriveState()` observation methods
/// 7. `private(set) var state` + `deriveState()` when `computeState()` is declared
///
/// ## `computeState()` / `deriveState()`
///
/// When state depends on multiple internal properties, define a `computeState()` method
/// returning `ViewModelState<...>` and the macro generates the wiring:
///
/// ```swift
/// @Observable
/// @ViewModel
/// final class ItemsViewModel {
///   private var isLoading = false
///   private var items: [Item] = []
///
///   func computeState() -> ViewModelState<ItemsState> {
///     if isLoading { return .loading }
///     if items.isEmpty { return .empty }
///     return .loaded(state: ItemsState(items: items))
///   }
///
///   private let itemsService: ItemsService
/// }
/// ```
///
/// The macro generates:
/// - `private(set) var state: ViewModelState<ItemsState> = .loading`
/// - `func deriveState() async` — observes `computeState()` via `valuesOf()`, writes to `state`
/// - `startObserving()` includes `deriveState()` alongside any `@Bound`/`@Reaction` observers
///
/// **Requirements:**
/// - `computeState()` must return `ViewModelState<...>` and take no parameters
/// - Cannot coexist with a user-declared `state` property
/// - If you provide a manual `startObserving()`, include `deriveState()` (warning if missing)
///
/// ## Generated `startObserving()` and self-capture
///
/// When multiple `@Bound`/`@Reaction`/`deriveState` methods exist, `startObserving()` uses
/// `withDiscardingTaskGroup` with `group.addTask { await self.observeX() }`.
/// The strong `self` capture is intentional: structured concurrency guarantees all
/// child tasks complete before the group returns, so `self` is never retained beyond
/// `startObserving()`'s lifetime.
///
/// **Important:** Do not store the Task from calling `startObserving()` on `self`
/// (e.g. `self.task = Task { await self.startObserving() }`), as this creates a
/// retain cycle. Use SwiftUI's `.task` modifier or the `observing()` test DSL instead.
@attached(member, names: named(init), named(Factory), named(preview), named(startObserving), arbitrary)
@attached(extension, conformances: ViewModel, PreviewProviding)
public macro ViewModel() = #externalMacro(
  module: "VISORMacros",
  type: "ViewModelMacro")
