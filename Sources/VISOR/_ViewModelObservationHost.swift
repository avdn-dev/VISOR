import SwiftUI

/// SwiftUI bridge used by generated `@LazyViewModel` bodies.
///
/// The content closure receives only the ViewModel. It cannot acquire a
/// session, readiness handle, cancellation hook or any other lifecycle
/// capability.
@MainActor
package struct _ViewModelObservationHost<
  VM: ViewModel,
  Content: View,
  Suspended: View,
  Pending: View,
  Failure: View
>: View {
  @State private var owner: _ViewModelObservationOwner<VM>?
  @Environment(\.scenePhase) private var scenePhase

  private let viewModel: VM
  private let observationPolicy: ObservationPolicy
  private let content: (VM) -> Content
  private let suspended: () -> Suspended
  private let pending: () -> Pending
  private let failure: () -> Failure

  package init(
    viewModel: VM,
    observationPolicy: ObservationPolicy,
    @ViewBuilder content: @escaping (VM) -> Content,
    @ViewBuilder suspended: @escaping () -> Suspended,
    @ViewBuilder pending: @escaping () -> Pending,
    @ViewBuilder failure: @escaping () -> Failure
  ) {
    self.viewModel = viewModel
    self.observationPolicy = observationPolicy
    self.content = content
    self.suspended = suspended
    self.pending = pending
    self.failure = failure
  }

  package var body: some View {
    Group {
      if !isEnabled {
        suspended()
      } else if let owner,
         owner._visorCanExposeContent(
           for: viewModel,
           isEnabled: isEnabled)
      {
        content(viewModel)
      } else if owner?._visorFailure != nil {
        failure()
      } else {
        pending()
      }
    }
    .task {
      // Every SwiftUI task lifetime receives a fresh contender. If a prior
      // lifetime is still joining, the ViewModel token serialises hand-off.
      let activeOwner = _ViewModelObservationOwner<VM>()
      owner = activeOwner
      await activeOwner._visorRun(
        viewModel: viewModel,
        initiallyEnabled: isEnabled)
    }
    .onChange(of: isEnabled) { _, enabled in
      owner?._visorSetEnabled(enabled)
    }
  }

  private var isEnabled: Bool {
    observationPolicy._visorIsEnabled(in: scenePhase)
  }
}

/// The only production-owner bridge named by generated downstream code.
/// Its opaque result hides the concrete host and all lifecycle capabilities.
@MainActor
public func _visorOwnedViewModelContent<VM, Content>(
  for viewModel: VM,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  @ViewBuilder content: @escaping (VM) -> Content
) -> some View where VM: ViewModel, Content: View {
  _visorOwnedViewModelContent(
    for: viewModel,
    observationPolicy: observationPolicy,
    pending: { ProgressView("Preparing Screen") },
    failure: {
      ContentUnavailableView(
        "Unable to Load",
        systemImage: "exclamationmark.triangle",
        description: Text("This screen could not be prepared."))
    },
    content: content)
}

/// Custom-presentation bridge used by generated `@LazyViewModel` bodies.
///
/// This overload is public only because attached macro expansions are
/// type-checked in the consuming module.
@MainActor
public func _visorOwnedViewModelContent<VM, Content, Pending, Failure>(
  for viewModel: VM,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  @ViewBuilder pending: @escaping () -> Pending,
  @ViewBuilder failure: @escaping () -> Failure,
  @ViewBuilder content: @escaping (VM) -> Content
) -> some View
where VM: ViewModel, Content: View, Pending: View, Failure: View {
  _ViewModelObservationHost(
    viewModel: viewModel,
    observationPolicy: observationPolicy,
    content: content,
    suspended: { Color.clear },
    pending: pending,
    failure: failure)
    .id(ObjectIdentifier(viewModel._visorObservationOwnership))
}
