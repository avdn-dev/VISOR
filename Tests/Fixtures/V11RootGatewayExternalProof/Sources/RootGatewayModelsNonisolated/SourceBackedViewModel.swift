import Observation
import RootObservationConsumer
import VISOR

private typealias NonisolatedSourceBackedRoot =
  NonisolatedSourceBackedViewModel

// Deliberately omits explicit deinitialisers so release compilation exercises
// the @ViewModel and cascaded State optimiser workarounds.
@MainActor
@Observable
@ViewModel
public final class NonisolatedSourceBackedViewModel {
  public final class State {
    @Bound(source: \NonisolatedSourceBackedViewModel.consumer.source)
    public private(set) var revision: Int

    @Bound(source: \NonisolatedSourceBackedRoot.consumer.source)
    public private(set) var mirroredRevision: Int

    @Bound(
      source: \NonisolatedSourceBackedViewModel.consumer.projectedSource,
      selecting: \RootProjectedSnapshot.revision)
    public private(set) var projectedRevision: Int

    public private(set) var reactedRevision = -1
    public private(set) var reactedLabel = "unreconciled"

    public init(
      revision: Int,
      mirroredRevision: Int,
      projectedRevision: Int)
    {
      self.revision = revision
      self.mirroredRevision = mirroredRevision
      self.projectedRevision = projectedRevision
    }
  }

  public let consumer: RootObservationConsumer

  @Reaction(source: \NonisolatedSourceBackedRoot.consumer.source)
  private func revisionChanged(_ revision: Int) {
    updateState(\.reactedRevision, to: revision)
  }

  @Reaction(
    source: \NonisolatedSourceBackedViewModel.consumer.projectedSource,
    selecting: \RootProjectedSnapshot.label)
  private func projectedLabelChanged(_ label: String) {
    updateState(\.reactedLabel, to: label)
  }
}
