import SwiftUI
import VISOR

// MARK: - TestRoot

nonisolated enum TestRoot: Int, RootDestination {
  case home = 0
  case settings = 1
}

// MARK: - ManuallyEnumeratedTestRoot

nonisolated struct ManuallyEnumeratedTestRoot: RootDestination {
  static let allCases = [Self(rawValue: 0), Self(rawValue: 1)]

  let rawValue: Int
}

// MARK: - TestPush

nonisolated enum TestPush: PushDestination {
  case detail(id: String)
  case nested
}

// MARK: - TestSheet

nonisolated enum TestSheet: String, SheetDestination {
  case preferences
  case profile

  var id: String {
    rawValue
  }
}

// MARK: - TestFullScreen

nonisolated enum TestFullScreen: String, FullScreenDestination {
  case onboarding
  case tutorial

  var id: String {
    rawValue
  }
}

// MARK: - TestScene

nonisolated enum TestScene: NavigationScene {
  typealias Push = TestPush
  typealias Sheet = TestSheet
  typealias FullScreen = TestFullScreen
  typealias Root = TestRoot
}

// MARK: - SingleStackTestScene

nonisolated enum SingleStackTestScene: NavigationScene {
  typealias Push = TestPush
  typealias Sheet = TestSheet
  typealias FullScreen = TestFullScreen
}

// MARK: - PushOnlyTestScene

nonisolated enum PushOnlyTestScene: NavigationScene {
  typealias Push = TestPush
}

// MARK: - IdentifiedTestSheet

nonisolated enum IdentifiedTestSheet: SheetDestination {
  case editor(documentID: String, revision: Int)

  var id: String {
    switch self {
    case .editor(let documentID, _): documentID
    }
  }
}

// MARK: - IdentifiedTestFullScreen

nonisolated enum IdentifiedTestFullScreen: FullScreenDestination {
  case reader(documentID: String, revision: Int)

  var id: String {
    switch self {
    case .reader(let documentID, _): documentID
    }
  }
}

// MARK: - IdentifiedPresentationTestScene

nonisolated enum IdentifiedPresentationTestScene: NavigationScene {
  typealias Push = TestPush
  typealias Sheet = IdentifiedTestSheet
  typealias FullScreen = IdentifiedTestFullScreen
}

// MARK: - RoutedTestVM

/// Shared routed VM fixture used across ViewModelFactory and Integration tests.
@Observable
@MainActor
@ViewModel
final class RoutedTestVM {

  // MARK: Lifecycle

  init(routerID: ObjectIdentifier) {
    self.routerID = routerID
  }

  // MARK: Internal

  final class State {
    init() { }
  }

  let state = State()
  let routerID: ObjectIdentifier

}
