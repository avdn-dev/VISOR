//
//  ObservationPolicy.swift
//  VISOR
//

import SwiftUI

/// Controls whether the `@LazyViewModel` observation loop pauses based on scene phase.
///
/// The default is ``alwaysObserving``, which is correct for most view models.
/// Tearing down and re-establishing observation on every background/foreground cycle
/// adds overhead (task group cancellation, resubscription, initial value re-emission)
/// that outweighs the near-zero cost of an idle observation callback.
///
/// Use ``pauseInBackground`` or ``pauseWhenInactive`` only when the observation loop
/// drives high-frequency work (polling, real-time rendering) that wastes resources
/// when the UI is not visible.
///
/// These policies respond to scene phase, not navigation covering or tab
/// selection. Observation belongs to the retained view's structural identity.
/// A scene pause deliberately withdraws content and cancels descendant view
/// tasks; resuming reconciles fresh snapshots before restoring content.
public enum ObservationPolicy: Equatable, Sendable {
  /// Observation runs continuously regardless of scene phase.
  case alwaysObserving
  /// Cancels observation when the scene enters background; restarts on foreground.
  case pauseInBackground
  /// Cancels observation when the scene is not active (background or inactive).
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
