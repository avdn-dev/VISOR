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
/// 6. `startObserving()` combining `@Bound` and `@Reaction` observation methods
///
/// ## Generated `startObserving()` and self-capture
///
/// When multiple `@Bound`/`@Reaction` properties exist, `startObserving()` uses
/// `withDiscardingTaskGroup` with `group.addTask { await self.observeX() }`.
/// The strong `self` capture is intentional: structured concurrency guarantees all
/// child tasks complete before the group returns, so `self` is never retained beyond
/// `startObserving()`'s lifetime.
///
/// **Important:** Do not store the Task from calling `startObserving()` on `self`
/// (e.g. `self.task = Task { await self.startObserving() }`), as this creates a
/// retain cycle. Use SwiftUI's `.task` modifier or the `observing()` test DSL instead.
///
/// Usage:
/// ```swift
/// @ViewModel
/// final class MyViewModel {
///   struct State { ... }
///   var state: ViewModelState<State> { ... }
///   private let myService: MyService
/// }
/// ```
///
/// Generates `MyViewModel.Factory` as a typealias for `ViewModelFactory<MyViewModel>`,
/// and `static var preview` for `#Preview` support.
@attached(member, names: named(init), named(Factory), named(preview), named(startObserving), arbitrary)
@attached(extension, conformances: ViewModel, PreviewProviding)
public macro ViewModel() = #externalMacro(
  module: "VISORMacros",
  type: "ViewModelMacro")
