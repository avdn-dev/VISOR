import Observation
import os
import RootGatewayModelsNonisolated
import RootObservationConsumer
import SwiftUI
import Testing
import VISOR

@Suite("Root State gateway from a nonisolated target")
struct RootGatewayNonisolatedTests {
  @MainActor
  @Test
  func `Every supported write spelling uses the generated State`() {
    typealias State = NonisolatedGatewayState

    let countSelector:
      KeyPath<State._VISORSelectors, _StateField<State, Int>> = \.count
    let settingsSelector:
      KeyPath<State._VISORSelectors, _StateField<State, GatewaySettings>> = \.settings

    let state = State(identifier: "nonisolated")

    state.setCountDirectly(1)
    state.incrementSettingsDirectly()
    state[countSelector] = 2
    state[settingsSelector].revision += 1

    @Bindable var boundState = state
    $boundState[\.count].wrappedValue = 3

    let bindableState = Bindable(state)
    bindableState[\.count].wrappedValue = 4

    #expect(state.count == 4)
    #expect(state.settings.revision == 2)
    #expect(state.identifier == "nonisolated")
  }

  @MainActor
  @Test
  func `Generated accessors remain observable`() {
    let state = NonisolatedGatewayState()
    let changes = OSAllocatedUnfairLock(initialState: 0)

    withObservationTracking {
      _ = state.count
    } onChange: {
      changes.withLock { $0 += 1 }
    }

    state.setCountDirectly(1)

    #expect(changes.withLock { $0 } == 1)
  }

  @MainActor
  @Test
  func `Root source-backed ViewModel expansion crosses the package boundary`() {
    let consumer = RootObservationConsumer(initialValue: 41)
    let viewModel = NonisolatedSourceBackedViewModel(consumer: consumer)

    requireViewModelConformance(viewModel)
    _ = viewModel._visorBuildObservationRecipe

    #expect(viewModel.state.revision == 41)
    #expect(viewModel.state.mirroredRevision == 41)
    #expect(viewModel.state.projectedRevision == 41)
    #expect(viewModel.state.reactedRevision == -1)
    #expect(viewModel.state.reactedLabel == "unreconciled")
    #expect(consumer.snapshot() == 41)
    #expect(consumer.projectedSnapshot().revision == 41)
  }

  @MainActor
  @Test
  func `Ordinary LazyViewModel selects source-backed ownership across the package boundary`() {
    let view = NonisolatedSourceBackedView()

    requireViewConformance(view)
    requireViewConformance(view.body)
  }

  @MainActor
  private func requireViewModelConformance<Subject: ViewModel>(_: Subject) {}

  @MainActor
  private func requireViewConformance<Subject: View>(_: Subject) {}
}
