import ExternalServices
import Observation
import VISOR

@MainActor
@Observable
@ViewModel
public final class ExternalSourceBackedViewModel {
  public final class State {
    @Bound(
      source: \ExternalSourceBackedViewModel.service.observationSource)
    public private(set) var revision = -1

    public private(set) var reactedRevision = -1

    public init() {}
  }

  public let state = State()
  public let service: ExternalSyncService

  public init(service: ExternalSyncService) {
    self.service = service
  }

  @Reaction(
    source: \ExternalSourceBackedViewModel.service.observationSource)
  private func revisionChanged(_ revision: Int) {
    updateState(\.reactedRevision, to: revision)
  }
}
