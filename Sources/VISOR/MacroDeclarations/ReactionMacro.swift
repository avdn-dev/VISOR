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
/// Both sync and async methods use `for await value in VISOR.valuesOf({ ... })` for
/// sequential delivery — each handler completes before the next value is processed.
///
/// Use `throttledBy:` to limit rapid-fire changes. The observation loop pauses after
/// each handler completes, dropping intermediate values.
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
