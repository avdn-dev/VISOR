import Observation
import VISOR

#if VISOR_PROBE_ACTION_HANDLER
@MainActor
@Observable
@ViewModel
final class LegacyAsyncHandler {
  final class State { }
  enum Action { case refresh }

  func handle(_: Action) async { }
}

@MainActor
@Observable
@ViewModel
final class LegacyVoidHandler {
  final class State {
    var input = 0
  }

  enum Action {
    @StateBinding(\State.input)
    case changed(Int)
  }

  func handle(_: Action) { }
}

@MainActor
@Observable
@ViewModel
final class AsyncCompletionHandler {
  final class State { }
  enum Action { case refresh }

  func handle(_: Action) async -> ActionCompletion {
    .completed
  }
}
#endif
