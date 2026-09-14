import Observation
import RootGatewayModelsNonisolated
import VISOR

#if VISOR_PROBE_BINDING_PAYLOAD
@MainActor
@Observable
@ViewModel
final class MismatchedBindingViewModel {
  final class State {
    private(set) var count = 0
  }

  enum Action {
    @StateBinding(\State.count)
    case changed(String)
  }

  @discardableResult
  func handle(_: Action) -> ActionCompletion {
    .completed
  }
}
#endif

#if VISOR_PROBE_PROJECTION_UPDATE
@MainActor
func probeProjectionUpdate(_ model: NonisolatedBindingViewModel) {
  model.updateState(\.isDisabled, to: false)
}
#endif

#if VISOR_PROBE_PROJECTION_SETTER
@MainActor
func probeProjectionSetter(_ model: NonisolatedBindingViewModel) {
  model.state.isDisabled = false
}
#endif

#if VISOR_PROBE_PROJECTION_PAYLOAD
@MainActor
@Observable
@ViewModel
final class MismatchedProjectionViewModel {
  final class State {
    var projected: Bool {
      true
    }
  }

  enum Action {
    @StateBinding(\State.projected)
    case changed(String)
  }

  @discardableResult
  func handle(_: Action) -> ActionCompletion {
    .completed
  }
}
#endif

#if VISOR_PROBE_CONDITIONAL_BINDING_ACTION
@MainActor
@Observable
@ViewModel
final class ConditionalBindingViewModel {
  final class State {
    private(set) var count = 0
  }

  #if os(macOS)
  enum Action {
    @StateBinding(\State.count)
    case changed(Int)
  }
  #endif

  @discardableResult
  func handle(_: Action) -> ActionCompletion {
    .completed
  }
}
#endif

#if VISOR_PROBE_V12_BINDING_NAMESPACE
@MainActor
func probeBindingNamespace(_ model: NonisolatedBindingViewModel) {
  _ = model.bindableState
  _ = model.bindings.displayOnly
  _ = model.bindings.hidden
  _ = model.bindings.preparedValue
  _ = model.state[\.isDisabled]
}

@MainActor
func probeUnannotatedSourceBindings(_ model: NonisolatedSourceBackedViewModel) {
  _ = model.bindings.projectedRevision
  _ = model.bindings.reactedRevision
}
#endif
