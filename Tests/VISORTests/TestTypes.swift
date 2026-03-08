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
