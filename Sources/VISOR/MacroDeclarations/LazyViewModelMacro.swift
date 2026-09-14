import SwiftUI

/// Retains a lazily constructed model and one structured observation lifetime.
///
/// Implement `readyContent(state:)`, optionally accepting `bindings` and a
/// `viewModel` parameter for integration that requires the prepared model.
/// These parameters are supplied only after initial source projections and
/// immediate reactions have reconciled.
///
/// ```swift
/// @LazyViewModel(LibraryViewModel.self)
/// struct LibraryView: View {
///   var body: some View {
///     content
///       .navigationTitle("Library")
///       .toolbar {
///         Button("Refresh") { send(.refresh) }
///           .disabled(state?.canRefresh != true)
///       }
///   }
///
///   func readyContent(state: LibraryViewModel.State) -> some View {
///     LibraryContent(state: state, onAction: { send($0) })
///   }
/// }
/// ```
/// `content` is the generated lifecycle slot. An authored `body` places stable
/// navigation and presentation around it; otherwise `body { content }` is
/// generated. Optional `pendingContent` and `failureContent` properties replace
/// the transparent preparation and generic unavailable defaults. Preparation
/// presentation includes the first render, before model construction.
///
/// The view's generated `state` is optional and returns a value only while the
/// model is ready. The explicit `state` parameter in `readyContent` is
/// nonoptional. There are no implicit nonoptional model or binding properties.
///
/// `send` dispatches synchronously and returns the action's `ActionCompletion`,
/// or `nil` when readiness does not permit dispatch. Rejected actions are never
/// queued. Supplied bindings reject writes after their observation generation
/// ends. Domain-specific admission and dismissal guards remain model-owned.
///
/// Navigation covering and tab switches preserve observation. Actual removal
/// cancels and joins the observation lifetime; scene pause policies withdraw
/// ready content until fresh source snapshots have reconciled on resumption.
@attached(
  member,
  names: named(body),
  named(content),
  named(state),
  named(send),
  named(_visorPresentation),
  named(_visorScenePhase)
)
public macro LazyViewModel<VM: ViewModel>(
  _ viewModelType: VM.Type,
  observationPolicy: ObservationPolicy = .alwaysObserving,
) = #externalMacro(module: "VISORMacros", type: "LazyViewModelMacro")
