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
/// Bound properties without default values are initialized from the service
/// at init time — no stale defaults.
///
/// ```swift
/// @ViewModel
/// final class ConnectionsViewModel {
///   struct State: Equatable {
///     @Bound(\ConnectionsViewModel.connectionService.isAuthenticated) var isAuthenticated: Bool
///     @Bound(\ConnectionsViewModel.connectionService.connections) var connections: [Connection]
///   }
///   private let connectionService: ConnectionService
/// }
/// ```
@attached(peer)
public macro Bound<Root, Value>(_ keyPath: KeyPath<Root, Value>) = #externalMacro(
  module: "VISORMacros", type: "BoundMacro")
