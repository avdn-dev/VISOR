import SwiftUI
import VISOR

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

nonisolated enum SingleStackTestScene: NavigationScene {
  typealias Push = TestPush
  typealias Sheet = TestSheet
  typealias FullScreen = TestFullScreen
}

// MARK: - Routed ViewModel Fixture

/// Shared routed VM fixture used across ViewModelFactory and Integration tests.
@Observable
@MainActor
@ViewModel
final class RoutedTestVM {
  final class State {
    init() {}
  }

  let state = State()
  let routerID: ObjectIdentifier

  init(routerID: ObjectIdentifier) {
    self.routerID = routerID
  }
}
