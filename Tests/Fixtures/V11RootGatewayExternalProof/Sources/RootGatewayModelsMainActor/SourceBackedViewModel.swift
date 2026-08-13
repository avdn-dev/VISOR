import Observation
import RootObservationConsumer
import VISOR

// Deliberately omits explicit deinitialisers so release compilation exercises
// the @ViewModel and cascaded State optimiser workarounds.
@MainActor
@Observable
@ViewModel
public final class MainActorSourceBackedViewModel {
  public final class State {
    @Bound(source: \MainActorSourceBackedViewModel.consumer.source)
    public private(set) var revision = -1

    @Bound(source: \MainActorSourceBackedViewModel.consumer.source)
    public private(set) var mirroredRevision = -1

    @Bound(
      source: \MainActorSourceBackedViewModel.consumer.projectedSource,
      selecting: \RootProjectedSnapshot.revision)
    public private(set) var projectedRevision = -1

    public private(set) var reactedRevision = -1
    public private(set) var reactedLabel = "unreconciled"

    public init() {}
  }

  public let state = State()
  public let consumer: RootObservationConsumer

  public init(consumer: RootObservationConsumer) {
    self.consumer = consumer
  }

  @Reaction(source: \MainActorSourceBackedViewModel.consumer.source)
  private func revisionChanged(_ revision: Int) {
    updateState(\.reactedRevision, to: revision)
  }

  @Reaction(
    source: \MainActorSourceBackedViewModel.consumer.projectedSource,
    selecting: \RootProjectedSnapshot.label)
  private func projectedLabelChanged(_ label: String) {
    updateState(\.reactedLabel, to: label)
  }
}
