import VISORObservation

/// The declarative bridge emitted by `@ViewModel`.
///
/// Generated consumer code can describe source projections and reactions, but
/// it never receives the package-owned session or any lifecycle capability.
@MainActor
package struct _ObservationRecipe {
  private let storage: any _ObservationRecipeStorage
  package let sourceID: _ObservationSourceID

  package init<Snapshot: Sendable>(
    source: ObservationSource<Snapshot>,
    projections: [
      @MainActor @Sendable (Snapshot) async -> Void
    ],
    initialReactions: [
      @MainActor @Sendable (Snapshot) async -> Void
    ] = []
  ) {
    let storage = _TypedObservationRecipe(
      source: source,
      projections: projections,
      initialReactions: initialReactions)
    self.storage = storage
    sourceID = source._visorIdentity
  }

  package func append<Snapshot: Sendable>(
    projections: [@MainActor @Sendable (Snapshot) async -> Void],
    initialReactions: [@MainActor @Sendable (Snapshot) async -> Void]
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
}

@MainActor
private protocol _ObservationRecipeStorage: AnyObject {
  func _visorMakeLane() -> _AnyObservationLane
}

@MainActor
private final class _TypedObservationRecipe<Snapshot: Sendable>:
  _ObservationRecipeStorage
{
  let source: ObservationSource<Snapshot>
  var projections: [@MainActor @Sendable (Snapshot) async -> Void]
  var initialReactions: [@MainActor @Sendable (Snapshot) async -> Void]

  init(
    source: ObservationSource<Snapshot>,
    projections: [@MainActor @Sendable (Snapshot) async -> Void],
    initialReactions: [@MainActor @Sendable (Snapshot) async -> Void]
  ) {
    self.source = source
    self.projections = projections
    self.initialReactions = initialReactions
  }

  func _visorMakeLane() -> _AnyObservationLane {
    _ObservationLane(
      source: source,
      handlers: projections,
      initialReactions: initialReactions
    )._visorErase()
  }
}

/// An underscored declarative sink used only by generated ViewModel code.
///
/// Its package-only initializer prevents downstream code from initiating or
/// retaining recipe enumeration. The generated witness can only add source
/// descriptions to a visitor supplied by VISOR.
@MainActor
public final class _ObservationRecipeVisitor {
  package private(set) var recipes: [_ObservationRecipe] = []

  package init() {}

  public func add<Snapshot: Sendable>(
    source: ObservationSource<Snapshot>,
    projections: [
      @MainActor @Sendable (Snapshot) async -> Void
    ],
    initialReactions: [
      @MainActor @Sendable (Snapshot) async -> Void
    ] = []
  ) {
    if let existing = recipes.first(where: {
      $0.sourceID == source._visorIdentity
    }), existing.append(
      projections: projections,
      initialReactions: initialReactions)
    {
      return
    }

    recipes.append(_ObservationRecipe(
      source: source,
      projections: projections,
      initialReactions: initialReactions))
  }
}
