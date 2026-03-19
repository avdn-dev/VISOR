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
/// Use `throttledBy:` to limit rapid-fire changes. On async methods, this switches
/// from cancel-previous (`latestValuesOf`) to throttle semantics (`for await` + sleep),
/// meaning each call runs to completion before the pause.
///
/// ```swift
/// @ViewModel
/// final class ContentViewModel {
///   @Reaction(\Self.deepLinkRouter.pendingDestination)
///   func handleDeepLink(destination: Destination?) { ... }
///
///   @Reaction(\Self.recorder.audioLevel, throttledBy: .seconds(0.1))
///   func handleAudioLevel(level: Float) { ... }
/// }
/// ```
@attached(peer)
public macro Reaction<Root, Value>(_ keyPath: KeyPath<Root, Value>) = #externalMacro(
  module: "VISORMacros", type: "ReactionMacro")

@attached(peer)
public macro Reaction<Root, Value>(
  _ keyPath: KeyPath<Root, Value>,
  throttledBy interval: Duration
) = #externalMacro(module: "VISORMacros", type: "ReactionMacro")
