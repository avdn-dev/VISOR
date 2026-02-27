import SwiftUI
import VISOR

// MARK: - Navigation Scene Types

enum TestTab: Int, TabDestination {
  case home = 0
  case settings = 1
}

enum TestPush: PushDestination {
  case detail(id: String)
  case nested

  var destinationView: some View {
    Text("push")
  }
}

enum TestSheet: String, SheetDestination {
  case preferences

  var id: String { rawValue }

  var destinationView: some View {
    Text("sheet")
  }
}

enum TestFullScreen: String, FullScreenDestination {
  case onboarding

  var id: String { rawValue }

  var destinationView: some View {
    Text("fullScreen")
  }
}

enum TestScene: NavigationScene {
  typealias Push = TestPush
  typealias Sheet = TestSheet
  typealias FullScreen = TestFullScreen
  typealias Tab = TestTab
}
