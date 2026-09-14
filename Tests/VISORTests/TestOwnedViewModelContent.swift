import SwiftUI
@testable import VISOR

// MARK: - TestOwnedViewModelContent

@MainActor
private struct TestOwnedViewModelContent<VM: ViewModel, Content: View, Pending: View, Failure: View>: View {
  let model: VM
  let policy: ObservationPolicy
  let pending: () -> Pending
  let failure: () -> Failure
  let ready: (VM) -> Content

  var body: some View {
    _visorLazyViewModelContent(
      presentation: presentation,
      observationPolicy: policy,
      pending: pending,
      failure: failure,
      ready: { model, _ in ready(model) },
    )
    .environment(ViewModelFactory { model })
  }

  @State private var presentation = _LazyViewModelPresentation<VM>()
}

@MainActor
func testOwnedViewModelContent<VM: ViewModel>(
  for model: VM,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  @ViewBuilder content: @escaping (VM) -> some View,
) -> some View {
  testOwnedViewModelContent(
    for: model,
    observationPolicy: observationPolicy,
    pending: { Color.clear },
    failure: { Text("Unavailable") },
    content: content,
  )
}

@MainActor
func testOwnedViewModelContent<VM: ViewModel>(
  for model: VM,
  observationPolicy: ObservationPolicy = .alwaysObserving,
  @ViewBuilder pending: @escaping () -> some View,
  @ViewBuilder failure: @escaping () -> some View,
  @ViewBuilder content: @escaping (VM) -> some View,
) -> some View {
  TestOwnedViewModelContent(
    model: model,
    policy: observationPolicy,
    pending: pending,
    failure: failure,
    ready: content,
  )
}
