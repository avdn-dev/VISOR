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
/// corresponding property on the named dependency.
///
///
/// ```swift
/// @ViewModel
/// final class ConnectionsViewModel {
///   @Bound(\Self.connectionService) var isAuthenticated = false
///   @Bound(\Self.connectionService) var connections: [Connection] = []
///   private let connectionService: ConnectionService
/// }
/// ```
@attached(peer)
public macro Bound<Root, Value>(_ keyPath: KeyPath<Root, Value>) = #externalMacro(
  module: "VISORMacros", type: "BoundMacro")
