import SwiftUI
import Observation
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

  var destinationView: some View {
    Text("push")
  }
}

nonisolated enum TestSheet: String, SheetDestination {
  case preferences
  case profile

  var id: String { rawValue }

  var destinationView: some View {
    Text("sheet")
  }
}

nonisolated enum TestFullScreen: String, FullScreenDestination {
  case onboarding
  case tutorial

  var id: String { rawValue }

  var destinationView: some View {
    Text("fullScreen")
  }
}

nonisolated enum TestScene: NavigationScene {
  typealias Push = TestPush
  typealias Sheet = TestSheet
  typealias FullScreen = TestFullScreen
  typealias Tab = TestTab
}
