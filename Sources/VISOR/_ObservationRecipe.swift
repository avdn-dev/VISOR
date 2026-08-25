import VISORObservation

// MARK: - _ObservationRecipe

/// The declarative bridge emitted by `@ViewModel`.
///
/// Generated consumer code can describe source projections and reactions, but
/// it never receives the package-owned session or any lifecycle capability.
@MainActor
package struct _ObservationRecipe {

  // MARK: Lifecycle

  package init<Snapshot: Sendable>(
    source: ObservationSource<Snapshot>,
    projections: [
      @MainActor @Sendable (Snapshot) async -> Void
    ],
    initialReactions: [
      @MainActor @Sendable (Snapshot) async -> Void
    ] = [],
  ) {
    let storage = _TypedObservationRecipe(
      source: source,
      projections: projections,
      initialReactions: initialReactions,
    )
    self.storage = storage
    sourceID = source._visorIdentity
  }

  // MARK: Package

  package let sourceID: _ObservationSourceID

  package func append<Snapshot: Sendable>(
    projections: [@MainActor @Sendable (Snapshot) async -> Void],
    initialReactions: [@MainActor @Sendable (Snapshot) async -> Void],
  ) -> Bool {
    guard let storage = storage as? _TypedObservationRecipe<Snapshot> else {
      return false
    }
    storage.projections.append(contentsOf: projections)
    storage.initialReactions.append(contentsOf: initialReactions)
    return true
  }

  package func _visorMakeLane() -> _AnyObservationLane {
    storage._visorMakeLane()
  }

  // MARK: Private

  private let storage: any _ObservationRecipeStorage

}

// MARK: - _ObservationRecipeStorage

@MainActor
private protocol _ObservationRecipeStorage: AnyObject {
  func _visorMakeLane() -> _AnyObservationLane
}

// MARK: - _TypedObservationRecipe

@MainActor
private final class _TypedObservationRecipe<Snapshot: Sendable>:
  _ObservationRecipeStorage
{

  // MARK: Lifecycle

  init(
    source: ObservationSource<Snapshot>,
    projections: [@MainActor @Sendable (Snapshot) async -> Void],
    initialReactions: [@MainActor @Sendable (Snapshot) async -> Void],
  ) {
    self.source = source
    self.projections = projections
    self.initialReactions = initialReactions
  }

  /// Empty deinitialisers in this file work around a Swift 6.2.4 release
  /// optimiser crash for explicitly MainActor-isolated classes.
  deinit { }

  // MARK: Internal

  let source: ObservationSource<Snapshot>
  var projections: [@MainActor @Sendable (Snapshot) async -> Void]
  var initialReactions: [@MainActor @Sendable (Snapshot) async -> Void]

  func _visorMakeLane() -> _AnyObservationLane {
    _ObservationLane(
      source: source,
      handlers: projections,
      initialReactions: initialReactions,
    )._visorErase()
  }
}

// MARK: - _ObservationRecipeVisitor

/// An underscored declarative sink used only by generated ViewModel code.
///
/// Its package-only initialiser prevents downstream code from initiating or
/// retaining recipe enumeration. The generated witness can only add source
/// descriptions to a visitor supplied by VISOR.
@MainActor
public final class _ObservationRecipeVisitor {

  // MARK: Lifecycle

  package init() { }

  deinit { }

  // MARK: Public

  /// Adds one generated source description to the visitor.
  ///
  /// This method is public only because attached macro expansions are
  /// type-checked in the consuming module.
  ///
  /// - Parameters:
  ///   - source: The source shared by the generated handlers.
  ///   - projections: State projections run for every delivered snapshot.
  ///   - initialReactions: Reactions also run while establishing readiness.
  public func add<Snapshot: Sendable>(
    source: ObservationSource<Snapshot>,
    projections: [
      @MainActor @Sendable (Snapshot) async -> Void
    ],
    initialReactions: [
      @MainActor @Sendable (Snapshot) async -> Void
    ] = [],
  ) {
    if
      let existing = recipes.first(where: {
        $0.sourceID == source._visorIdentity
      }), existing.append(
        projections: projections,
        initialReactions: initialReactions,
      )
    {
      return
    }

    recipes.append(_ObservationRecipe(
      source: source,
      projections: projections,
      initialReactions: initialReactions,
    ))
  }

  // MARK: Package

  package private(set) var recipes = [_ObservationRecipe]()

}
