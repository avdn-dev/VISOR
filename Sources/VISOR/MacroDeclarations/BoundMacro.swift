import VISORObservation

/// Projects a cooperative observation source into a `@ViewModel.State` field.
///
/// The `@ViewModel` macro groups fields sharing a source into one declarative
/// observation recipe. The complete-source form assigns each source snapshot;
/// the `selecting:` form projects one value from the snapshot.
///
/// ```swift
/// @MainActor
/// @Observable
/// @ViewModel
/// final class ConnectionsViewModel {
///   final class State {
///     @Bound(
///       source: \\ConnectionsViewModel.connectionSource,
///       selecting: \\ConnectionSnapshot.isAuthenticated)
///     var isAuthenticated = false
///   }
///
///   let state = State()
///   private let connectionSource: ObservationSource<ConnectionSnapshot>
/// }
/// ```
@attached(peer)
public macro Bound<Root, Snapshot: Sendable, Value>(
  source: KeyPath<Root, ObservationSource<Snapshot>>,
  selecting selection: KeyPath<Snapshot, Value>
) = #externalMacro(module: "VISORMacros", type: "BoundMacro")

@attached(peer)
public macro Bound<Root, Value: Sendable>(
  source: KeyPath<Root, ObservationSource<Value>>
) = #externalMacro(module: "VISORMacros", type: "BoundMacro")
