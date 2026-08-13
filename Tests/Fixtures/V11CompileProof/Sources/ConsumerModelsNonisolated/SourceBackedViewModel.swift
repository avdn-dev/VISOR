import ConsumerServices
import Observation
import VISOR

@MainActor
public final class ObservationReactionGate {
  private var isOpen = false
  private var hasStarted = false
  private var openWaiters: [CheckedContinuation<Void, Never>] = []
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func suspend() async {
    hasStarted = true
    let started = startedWaiters
    startedWaiters.removeAll()
    for waiter in started { waiter.resume() }
    guard !isOpen else { return }
    await withCheckedContinuation { openWaiters.append($0) }
  }

  public func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  public func open() {
    isOpen = true
    let waiters = openWaiters
    openWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

@MainActor
@Observable
@ViewModel
public final class SourceBackedViewModel {
  public final class State {
    @Bound(
      source: \SourceBackedViewModel.aliasService.observationSource,
      selecting: \SyncSnapshot.revision)
    public private(set) var revision = -1

    @Bound(
      source: \SourceBackedViewModel.service.observationSource,
      selecting: \SyncSnapshot.revision)
    public private(set) var mirroredRevision = -1

    public private(set) var reactedRevision = -1
    public private(set) var projectedRevisionSumSeenByReaction = -1

    @Bound(
      source: \SourceBackedViewModel.statusService.observationSource,
      selecting: \StatusSnapshot.status)
    public private(set) var status = SyncStatus.idle

    public private(set) var reactedStatus = SyncStatus.idle
    public private(set) var revisionSeenByStatusReaction = -1

    public init() {}
  }

  public let state = State()
  public let service: SyncingService
  public let aliasService: SyncingService
  public let statusService: StatusService
  private let reactionGate: ObservationReactionGate?

  public init(
    service: SyncingService,
    statusService: StatusService = StatusService(),
    reactionGate: ObservationReactionGate? = nil
  ) {
    self.service = service
    aliasService = service
    self.statusService = statusService
    self.reactionGate = reactionGate
  }

  @Reaction(
    source: \SourceBackedViewModel.service.observationSource,
    selecting: \SyncSnapshot.revision)
  private func revisionChanged(_ revision: Int) {
    updateState(
      \.projectedRevisionSumSeenByReaction,
      to: state.revision + state.mirroredRevision)
    updateState(\.reactedRevision, to: revision)
  }

  @Reaction(
    source: \SourceBackedViewModel.statusService.observationSource,
    selecting: \StatusSnapshot.status)
  private func statusChanged(_ status: SyncStatus) async {
    updateState(\.revisionSeenByStatusReaction, to: state.revision)
    if status == .loading {
      await reactionGate?.suspend()
    }
    updateState(\.reactedStatus, to: status)
  }
}
