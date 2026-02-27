//
//  ReactionMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

/// Marks a method for automatic observation reaction in `@ViewModel` classes.
///
/// The `@ViewModel` macro reads `@Reaction` annotations and generates an
/// observation wrapper that calls the annotated method whenever the observed
/// expression changes.
///
/// - Sync methods: `for await value in VISOR.valuesOf({ ... }) { self.method(value) }`
/// - Async methods: `await VISOR.latestValuesOf({ ... }) { value in await self.method(value) }`
///
/// ```swift
/// @ViewModel
/// final class ContentViewModel {
///   @Reaction(\Self.deepLinkRouter.pendingDestination)
///   func handleDeepLink(destination: Destination?) { ... }
/// }
/// ```
@attached(peer)
public macro Reaction<Root, Value>(_ keyPath: KeyPath<Root, Value>) = #externalMacro(
  module: "VISORMacros", type: "ReactionMacro")
