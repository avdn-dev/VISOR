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
///   private let contentService: ContentService
///
///   init(contentService: ContentService) {
///     self.contentService = contentService
///   }
///
///   @Reaction(
///     source: \ContentViewModel.contentService.source,
///     selecting: \ContentSnapshot.title)
///   private func recordTitle(_ title: String) { ... }
/// }
/// ```
///
/// - Parameters:
///   - source: A key path from the ViewModel to a stable snapshot source.
///   - selection: A key path selecting the method argument from each snapshot.
@attached(peer)
public macro Reaction<Root, Snapshot: Sendable, Value>(
  source: KeyPath<Root, ObservationSource<Snapshot>>,
  selecting selection: KeyPath<Snapshot, Value>
) = #externalMacro(module: "VISORMacros", type: "ReactionMacro")

/// Invokes the annotated method for every complete source value.
///
/// - Parameter source: A key path from the ViewModel to the stable value source.
@attached(peer)
public macro Reaction<Root, Value: Sendable>(
  source: KeyPath<Root, ObservationSource<Value>>
) = #externalMacro(module: "VISORMacros", type: "ReactionMacro")
