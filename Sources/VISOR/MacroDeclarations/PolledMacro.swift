//
//  PolledMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/3/2026.
//

/// Marks a `var` property for periodic polling in `@ViewModel` classes.
///
/// The `@ViewModel` macro reads `@Polled` annotations and generates a
/// `startObserving()` method that periodically reads the source property
/// on a timer. This is the pull-based counterpart to `@Bound`.
///
/// Use `@Polled` for non-observable sources (hardware sensors, system APIs,
/// computed properties) where the source doesn't participate in `@Observable`.
///
/// Polled properties without default values are initialised from the service
/// at init time — same semantics as `@Bound`.
///
/// ```swift
/// @Observable
/// @ViewModel
/// final class DashboardViewModel {
///   @Observable
///   final class State {
///     @Polled(\DashboardViewModel.batteryMonitor.level, every: .seconds(30)) var batteryLevel: Float
///
///     nonisolated init(batteryLevel: Float) {
///       self._batteryLevel = batteryLevel
///     }
///   }
///   private let batteryMonitor: BatteryMonitor
/// }
/// ```
///
/// In `nonisolated` State initializers, assign backing storage (`self._batteryLevel = batteryLevel`)
/// rather than the observable property setter (`self.batteryLevel = batteryLevel`).
@attached(peer)
public macro Polled<Root, Value>(
  _ keyPath: KeyPath<Root, Value>,
  every interval: Duration
) = #externalMacro(module: "VISORMacros", type: "PolledMacro")
