//
//  BoundMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

/// Marks a `var` property for automatic observation binding in `@ViewModel` classes.
///
/// The `@ViewModel` macro reads `@Bound` annotations and generates a
/// `startObserving()` method that binds each annotated property to the
/// source property specified by the key path. The key path provides full
/// autocomplete and compiler validation of the source property.
///
/// Bound properties must not have default values — state is initialised from the
/// service at init time.
///
/// Use the `throttledBy:` variant to limit rapid-fire updates to a maximum
/// frequency. The observation loop pauses after each update, dropping
/// intermediate values. Zero CPU cost when the source is quiet.
///
/// ```swift
/// @ViewModel
/// final class ConnectionsViewModel {
///   @Observable
///   final class State {
///     @Bound(\ConnectionsViewModel.connectionService.isAuthenticated) var isAuthenticated: Bool
///     @Bound(\ConnectionsViewModel.headTracker.posture, throttledBy: .seconds(0.125)) var posture: Posture
///   }
///   private let connectionService: ConnectionService
///   private let headTracker: HeadTracker
/// }
/// ```
@attached(peer)
public macro Bound<Root, Value>(_ keyPath: KeyPath<Root, Value>) = #externalMacro(
  module: "VISORMacros", type: "BoundMacro")

@attached(peer)
public macro Bound<Root, Value>(
  _ keyPath: KeyPath<Root, Value>,
  throttledBy interval: Duration
) = #externalMacro(module: "VISORMacros", type: "BoundMacro")
