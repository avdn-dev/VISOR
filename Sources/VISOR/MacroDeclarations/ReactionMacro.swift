import VISORObservation

/// Reacts to values from a cooperative observation source in a `@ViewModel`.
///
/// The annotated method must accept exactly one parameter, return `Void`, and
/// be nonthrowing. Both synchronous and asynchronous methods are supported.
///
/// ```swift
/// @MainActor
/// @Observable
/// @ViewModel
/// final class ContentViewModel {
///   final class State { var title = "" }
///   let state = State()
///
///   @Reaction(
///     source: \\ContentViewModel.contentSource,
///     selecting: \\ContentSnapshot.title)
///   func recordTitle(_ title: String) { ... }
/// }
/// ```
@attached(peer)
public macro Reaction<Root, Snapshot: Sendable, Value>(
  source: KeyPath<Root, ObservationSource<Snapshot>>,
  selecting selection: KeyPath<Snapshot, Value>
) = #externalMacro(module: "VISORMacros", type: "ReactionMacro")

@attached(peer)
public macro Reaction<Root, Value: Sendable>(
  source: KeyPath<Root, ObservationSource<Value>>
) = #externalMacro(module: "VISORMacros", type: "ReactionMacro")
