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
///       source: \ConnectionsViewModel.connectionService.source,
///       selecting: \ConnectionSnapshot.isAuthenticated)
///     var isAuthenticated = false
///   }
///
///   let state = State()
///   private let connectionService: ConnectionService
///
///   init(connectionService: ConnectionService) {
///     self.connectionService = connectionService
///   }
/// }
/// ```
///
/// - Parameters:
///   - source: A key path from the ViewModel to a stable snapshot source.
///   - selection: A key path selecting the State field's value from each snapshot.
@attached(peer)
public macro Bound<Root, Snapshot: Sendable, Value>(
  source: KeyPath<Root, ObservationSource<Snapshot>>,
  selecting selection: KeyPath<Snapshot, Value>
) = #externalMacro(module: "VISORMacros", type: "BoundMacro")

/// Projects every complete source value into the annotated State field.
///
/// - Parameter source: A key path from the ViewModel to the stable value source.
@attached(peer)
public macro Bound<Root, Value: Sendable>(
  source: KeyPath<Root, ObservationSource<Value>>
) = #externalMacro(module: "VISORMacros", type: "BoundMacro")
