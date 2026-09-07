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
