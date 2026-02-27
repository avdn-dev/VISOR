//
//  LazyViewModelMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

import Observation

// MARK: - Single ViewModel Macro

/// Attach to a View struct to enable lazy view model initialization.
/// Auto-generates factory environment, viewModel property, and body.
///
/// The generated `body` includes a `.task(id:)` modifier that calls
/// `viewModel.startObserving()`. SwiftUI owns the task lifetime —
/// cancellation happens automatically when the view disappears.
///
/// **Mode A — `loadedView(state:)`:** Full loading/empty/loaded/error state switch.
/// Conforms the view to `LazyViewModelView` (provides default loading/empty/error views).
/// ```swift
/// @LazyViewModel(MyViewModel.self)
/// struct MyView: View {
///   func loadedView(state: MyViewModel.State) -> some View { ... }
/// }
/// ```
///
/// **Mode B — `content`:** Simplified body for VMs that are always `.loaded`.
/// No state switch, no `makeViewModel()`, no `LazyViewModelView` conformance.
/// ```swift
/// @LazyViewModel(MyViewModel.self)
/// struct MyView: View {
///   var content: some View { ... }
/// }
/// ```
///
/// Provide exactly one of `loadedView(state:)` or `content` — not both.
@attached(member, names: named(body), named(_viewModel), named(viewModel), named(factory), named(makeViewModel), named(containerRouter))
@attached(extension, conformances: LazyViewModelView)
public macro LazyViewModel<VM: ViewModel>(_: VM.Type) = #externalMacro(
  module: "VISORMacros",
  type: "LazyViewModelMacro")
