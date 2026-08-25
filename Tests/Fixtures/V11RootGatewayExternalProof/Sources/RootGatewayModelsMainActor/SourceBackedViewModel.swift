import Observation
import RootObservationConsumer
import VISOR

/// Deliberately omits explicit deinitialisers so release compilation exercises
/// the @ViewModel and cascaded State optimiser workarounds.
@MainActor
@Observable
@ViewModel
public final class MainActorSourceBackedViewModel {

  // MARK: Public

  public final class State {

    // MARK: Lifecycle

    public init(
      revision: Int,
      mirroredRevision: Int,
      projectedRevision: Int,
    ) {
      self.revision = revision
      self.mirroredRevision = mirroredRevision
      self.projectedRevision = projectedRevision
    }

    // MARK: Public

    @Bound(source: \MainActorSourceBackedViewModel.consumer.source)
    public private(set) var revision: Int

    @Bound(source: \MainActorSourceBackedViewModel.consumer.source)
    public private(set) var mirroredRevision: Int

    @Bound(
      source: \MainActorSourceBackedViewModel.consumer.projectedSource,
      selecting: \RootProjectedSnapshot.revision,
    )
    public private(set) var projectedRevision: Int

    public private(set) var reactedRevision = -1
    public private(set) var reactedLabel = "unreconciled"

  }

  public let consumer: RootObservationConsumer

  // MARK: Private

  @Reaction(source: \MainActorSourceBackedViewModel.consumer.source)
  private func revisionChanged(_ revision: Int) {
    updateState(\.reactedRevision, to: revision)
  }

  @Reaction(
    source: \MainActorSourceBackedViewModel.consumer.projectedSource,
    selecting: \RootProjectedSnapshot.label,
  )
  private func projectedLabelChanged(_ label: String) {
    updateState(\.reactedLabel, to: label)
  }
}
