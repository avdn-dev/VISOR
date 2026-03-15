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
/// **Screen/Content pattern:**
/// ```swift
/// @LazyViewModel(DashboardViewModel.self)
/// struct DashboardScreen: View {
///   var content: some View {
///     DashboardContent(state: viewModel.state, onAction: viewModel.handle)
///   }
/// }
/// ```
///
/// The Screen owns the VM. The Content view is a pure function of state + onAction,
/// trivially previewable with static state and no factory.
///
/// **Bindings:** Use the generated `stateBinding` property for SwiftUI controls:
/// ```swift
/// Toggle("Enabled", isOn: stateBinding.isEnabled)
/// TextField("Name", text: stateBinding.name)
/// ```
///
/// - Parameter observationPolicy: Controls whether observation pauses based on scene phase.
///   Defaults to `.alwaysObserving`. Use `.pauseInBackground` or `.pauseWhenInactive` for
///   view models driving high-frequency work that wastes resources when the UI is not visible.
///
/// > The generated `viewModel` property force-unwraps the backing `@State`. This is safe
/// > because the generated `body` guards with `if _viewModel != nil` before rendering
/// > `content`, and initialization is guaranteed by the `.task` modifier.
@attached(member, names: named(body), named(_viewModel), named(viewModel), named(stateBinding), named(factory), named(containerRouter), named(scenePhase))
public macro LazyViewModel<VM: ViewModel>(
  _: VM.Type,
  observationPolicy: ObservationPolicy = .alwaysObserving
) = #externalMacro(
  module: "VISORMacros",
  type: "LazyViewModelMacro")
