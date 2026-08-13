import SwiftUI

/// Controls which scene phases retain a generated observation generation.
public enum ObservationPolicy: Equatable, Sendable {
  case alwaysObserving
  case pauseInBackground
  case pauseWhenInactive

  package func _visorIsEnabled(in scenePhase: ScenePhase) -> Bool {
    switch self {
    case .alwaysObserving:
      true
    case .pauseInBackground:
      scenePhase != .background
    case .pauseWhenInactive:
      scenePhase == .active
    }
  }
}
