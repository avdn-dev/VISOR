import Observation
import os
import RootGatewayModelsMainActor
import RootObservationConsumer
import SwiftUI
import Testing
import VISOR

@Suite("Root State gateway from a MainActor-by-default target")
struct RootGatewayMainActorTests {
  @Test
  func `Every supported write spelling uses the generated State`() {
    typealias State = MainActorGatewayState

    let countSelector:
      KeyPath<State._VISORSelectors, _StateField<State, Int>> = \.count
    let settingsSelector:
      KeyPath<State._VISORSelectors, _StateField<State, GatewaySettings>> = \.settings

    let state = State(identifier: "main-actor")

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
    #expect(state.identifier == "main-actor")
  }

  @Test
  func `Generated accessors remain observable`() {
    let state = MainActorGatewayState()
    let changes = OSAllocatedUnfairLock(initialState: 0)

    withObservationTracking {
      _ = state.count
    } onChange: {
      changes.withLock { $0 += 1 }
    }

    state.setCountDirectly(1)

    #expect(changes.withLock { $0 } == 1)
  }

  @Test
  func `Root source-backed ViewModel expansion crosses the package boundary`() {
    let consumer = RootObservationConsumer(initialValue: 42)
    let viewModel = MainActorSourceBackedViewModel(consumer: consumer)

    requireViewModelConformance(viewModel)
    _ = viewModel._visorBuildObservationRecipe

    #expect(viewModel.state.revision == -1)
    #expect(viewModel.state.mirroredRevision == -1)
    #expect(viewModel.state.projectedRevision == -1)
    #expect(viewModel.state.reactedRevision == -1)
    #expect(viewModel.state.reactedLabel == "unreconciled")
    #expect(consumer.snapshot() == 42)
    #expect(consumer.projectedSnapshot().revision == 42)
  }

  @Test
  func `Ordinary LazyViewModel selects source-backed ownership across the package boundary`() {
    let view = MainActorSourceBackedView()

    requireViewConformance(view)
    requireViewConformance(view.body)
  }

  private func requireViewModelConformance<Subject: ViewModel>(_: Subject) {}

  private func requireViewConformance<Subject: View>(_: Subject) {}
}
