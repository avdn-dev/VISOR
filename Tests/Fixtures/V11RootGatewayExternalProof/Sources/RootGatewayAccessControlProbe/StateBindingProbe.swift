import Observation
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

  func handle(_: Action) { }
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

  func handle(_: Action) { }
}
#endif
