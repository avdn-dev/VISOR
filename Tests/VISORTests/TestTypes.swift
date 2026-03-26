import SwiftUI
import VISOR

// MARK: - Shared Observable Source

/// Shared observable test dependency used across observation test suites.
/// Replaces per-file duplicates (CounterSource, FlagSource, ObserveSource, etc.)
@Observable
@MainActor
final class TestSource {
  var count = 0
  var isEnabled = false
  var name = "initial"
}

// MARK: - Navigation Scene Types

nonisolated enum TestTab: Int, TabDestination {
  case home = 0
  case settings = 1
}

nonisolated enum TestPush: PushDestination {
  case detail(id: String)
  case nested
}

nonisolated enum TestSheet: String, SheetDestination {
  case preferences
  case profile

  var id: String { rawValue }
}

nonisolated enum TestFullScreen: String, FullScreenDestination {
  case onboarding
  case tutorial

  var id: String { rawValue }
}

nonisolated enum TestScene: NavigationScene {
  typealias Push = TestPush
  typealias Sheet = TestSheet
  typealias FullScreen = TestFullScreen
  typealias Tab = TestTab
}

// MARK: - Routed ViewModel Fixture

/// Shared routed VM fixture used across ViewModelFactory and Integration tests.
@Observable
@MainActor
final class RoutedTestVM: ViewModel {
  @Observable
  final class State: @preconcurrency Equatable {
    static func == (lhs: State, rhs: State) -> Bool { true }
  }

  @ObservationIgnored private var _state = State()
  var state: State {
    get { access(keyPath: \.state); return _state }
    set { withMutation(keyPath: \.state) { _state = newValue } }
  }

  func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
    guard _state[keyPath: keyPath] != value else { return }
    _state[keyPath: keyPath] = value
  }

  let routerID: ObjectIdentifier

  init(routerID: ObjectIdentifier) {
    self.routerID = routerID
  }
}
