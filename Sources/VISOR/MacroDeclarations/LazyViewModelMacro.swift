//
//  LazyViewModelMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

import SwiftUI

// MARK: - Single ViewModel Macro

/// Attach to a View struct to enable lazy view model initialisation.
/// Auto-generates factory environment, viewModel property, and body.
///
/// The generated body performs lazy initialisation once, then delegates
/// observation to VISOR's structured, readiness-gated owner through an opaque
/// runtime bridge.
///
/// **View/Content pattern:**
/// ```swift
/// @LazyViewModel(DashboardViewModel.self)
/// struct DashboardView: View {
///   var content: some View {
///     DashboardContent(state: state) { action in
///       Task { await viewModel.handle(action) }
///     }
///   }
/// }
/// ```
///
/// The `@LazyViewModel` view owns the VM. The Content view is a pure function of
/// state + onAction, trivially previewable with static state and no factory.
///
/// **Read-only state:** Use the generated `state` alias for reading:
/// ```swift
/// Text(state.title)
/// ```
///
/// **Bindings:** Use the generated `bindableState` property for SwiftUI controls:
/// ```swift
/// Toggle("Enabled", isOn: bindableState[\.isEnabled])
/// TextField("Name", text: bindableState[\.name])
/// ```
///
/// The default owner UI shows labelled progress while observation becomes
/// ready and a generic unavailable state after an infrastructure failure. Use
/// the custom-presentation overload when the feature needs its own copy or
/// layout; ordinary domain failures still belong in ViewModel State.
///
/// - Parameters:
///   - viewModelType: The concrete ViewModel type owned by the generated view.
///   - observationPolicy: Controls whether observation pauses based on scene phase.
///     Defaults to `.alwaysObserving`. Use `.pauseInBackground` or `.pauseWhenInactive` for
///     view models driving high-frequency work that wastes resources when the UI is not visible.
///
/// > The generated `viewModel` property fails with a diagnostic precondition if accessed
/// > before initialisation. The generated `body` renders `content` only while the backing
/// > `@State` contains a ViewModel; its task creates that instance when the owner mounts.
@attached(
  member,
  names: named(body),
  named(_viewModel),
  named(viewModel),
  named(state),
  named(bindableState),
  named(factory),
  named(hostRouter),
  named(scenePhase)
)
public macro LazyViewModel<VM: ViewModel>(
  _ viewModelType: VM.Type,
  observationPolicy: ObservationPolicy = .alwaysObserving,
) = #externalMacro(
  module: "VISORMacros",
  type: "LazyViewModelMacro",
)

/// Custom-presentation form of ``LazyViewModel(_:observationPolicy:)``.
///
/// The pending and failure views replace VISOR's defaults after the ViewModel
/// has been created. The brief transparent pre-construction state is retained.
/// Supply a meaningful accessibility label in custom pending UI, and make a
/// custom failure view explain the unavailable state without creating a dead
/// end.
///
/// - Parameters:
///   - viewModelType: The concrete ViewModel type owned by the generated view.
///   - observationPolicy: Controls whether observation pauses based on scene phase.
///   - pending: UI shown while VISOR reconciles initial observation state.
///   - failure: UI shown when VISOR can no longer guarantee coherent State.
@attached(
  member,
  names: named(body),
  named(_viewModel),
  named(viewModel),
  named(state),
  named(bindableState),
  named(factory),
  named(hostRouter),
  named(scenePhase)
)
public macro LazyViewModel<VM: ViewModel, Pending: View, Failure: View>(
  _ viewModelType: VM.Type,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  pending: Pending,
  failure: Failure,
) = #externalMacro(
  module: "VISORMacros",
  type: "LazyViewModelMacro",
)
