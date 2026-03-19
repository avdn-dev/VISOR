//
//  ObservationPolicy.swift
//  VISOR
//

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
public enum ObservationPolicy: Sendable {
  /// Observation runs continuously regardless of scene phase.
  case alwaysObserving
  /// Cancels observation when the scene enters background; restarts on foreground.
  case pauseInBackground
  /// Cancels observation when the scene is not active (background or inactive).
  case pauseWhenInactive
}
