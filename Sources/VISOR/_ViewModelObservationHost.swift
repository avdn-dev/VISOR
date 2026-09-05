import SwiftUI

// MARK: - _ViewModelObservationHost

/// SwiftUI bridge used by generated `@LazyViewModel` bodies.
///
/// The content closure receives only the ViewModel. It cannot acquire a
/// session, readiness handle, cancellation hook or any other lifecycle
/// capability.
@MainActor
package struct _ViewModelObservationHost<
  VM: ViewModel,
  Content: View,
  Pending: View,
  Failure: View,
>: View {

  // MARK: Lifecycle

  package init(
    viewModel: VM,
    observationPolicy: ObservationPolicy,
    @ViewBuilder content: @escaping (VM) -> Content,
    @ViewBuilder pending: @escaping () -> Pending,
    @ViewBuilder failure: @escaping () -> Failure,
  ) {
    self.viewModel = viewModel
    self.observationPolicy = observationPolicy
    self.content = content
    self.pending = pending
    self.failure = failure
  }

  // MARK: Package

  package var body: some View {
    Group {
      if !isEnabled {
        Color.clear
      } else if
        let owner,
        owner._visorCanExposeContent(
          for: viewModel,
          isEnabled: isEnabled,
        )
      {
        content(viewModel)
      } else if owner?._visorFailure != nil {
        failure()
      } else {
        pending()
      }
    }
    .task {
      // Appearance starts ownership, but covering a destination does not end
      // its SwiftUI identity. State releases this lifetime on actual removal.
      guard lifetime == nil, !Task.isCancelled else { return }
      lifetime = _ViewModelObservationLifetime(
        viewModel: viewModel,
        initiallyEnabled: isEnabled,
      )
    }
    .onChange(of: isEnabled) { _, enabled in
      owner?._visorSetEnabled(enabled)
    }
  }

  // MARK: Private

  @State private var lifetime: _ViewModelObservationLifetime<VM>?
  @Environment(\.scenePhase) private var scenePhase

  private let viewModel: VM
  private let observationPolicy: ObservationPolicy
  private let content: (VM) -> Content
  private let pending: () -> Pending
  private let failure: () -> Failure

  private var owner: _ViewModelObservationOwner<VM>? {
    lifetime?.owner
  }

  private var isEnabled: Bool {
    observationPolicy._visorIsEnabled(in: scenePhase)
  }
}

/// The only production-owner bridge named by generated downstream code.
/// Its opaque result hides the concrete host and all lifecycle capabilities.
@MainActor
public func _visorOwnedViewModelContent<VM: ViewModel>(
  for viewModel: VM,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  @ViewBuilder content: @escaping (VM) -> some View,
) -> some View {
  _visorOwnedViewModelContent(
    for: viewModel,
    observationPolicy: observationPolicy,
    pending: { Color.clear },
    failure: {
      ContentUnavailableView(
        "Unable to Load",
        systemImage: "exclamationmark.triangle",
        description: Text("This screen could not be prepared."),
      )
    },
    content: content,
  )
}

/// Custom-presentation bridge used by generated `@LazyViewModel` bodies.
///
/// This overload is public only because attached macro expansions are
/// type-checked in the consuming module.
@MainActor
public func _visorOwnedViewModelContent<VM: ViewModel>(
  for viewModel: VM,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  @ViewBuilder pending: @escaping () -> some View,
  @ViewBuilder failure: @escaping () -> some View,
  @ViewBuilder content: @escaping (VM) -> some View,
) -> some View {
  _ViewModelObservationHost(
    viewModel: viewModel,
    observationPolicy: observationPolicy,
    content: content,
    pending: pending,
    failure: failure,
  )
  .id(ObjectIdentifier(viewModel._visorObservationOwnership))
}
