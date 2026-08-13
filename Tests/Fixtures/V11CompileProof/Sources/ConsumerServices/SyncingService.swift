import VISORObservation
import VISORTestDoubles

public struct SyncSnapshot: Equatable, Sendable {
  public var revision: Int

  public init(revision: Int) {
    self.revision = revision
  }
}

public actor SyncingService {
  private let channel: ObservationChannel<SyncSnapshot>

  public nonisolated let observationSource: ObservationSource<SyncSnapshot>

  public nonisolated var activeObservationCountForProof: Int {
    observationSource._visorActiveSubscriptionCount
  }

  public init() {
    let channel = ObservationChannel(SyncSnapshot(revision: 0))
    self.channel = channel
    observationSource = channel.source
  }

  public func synchronise() async {
    let current = observationSource.currentSnapshot()
    channel.publish(SyncSnapshot(revision: current.revision + 1))
  }

  public func publish(_ snapshot: SyncSnapshot) {
    channel.publish(snapshot)
  }

  public nonisolated func publishSynchronously(_ snapshot: SyncSnapshot) {
    channel.publish(snapshot)
  }

  public nonisolated func terminateObservationForProof() {
    channel._visorTerminate()
  }
}

public struct SyncingServiceDoubleSupport: TestDoubleSupport {
  public init() {}
}

public enum SyncStatus: Equatable, Sendable {
  case idle
  case ready
  case loading
  case held
}

public struct StatusSnapshot: Equatable, Sendable {
  public var status: SyncStatus

  public init(status: SyncStatus) {
    self.status = status
  }
}

public actor StatusService {
  private let channel: ObservationChannel<StatusSnapshot>

  public nonisolated let observationSource: ObservationSource<StatusSnapshot>

  public nonisolated var activeObservationCountForProof: Int {
    observationSource._visorActiveSubscriptionCount
  }

  public init() {
    let channel = ObservationChannel(StatusSnapshot(status: .idle))
    self.channel = channel
    observationSource = channel.source
  }

  public func publish(_ status: SyncStatus) {
    channel.publish(StatusSnapshot(status: status))
  }

  public nonisolated func publishSynchronously(_ status: SyncStatus) {
    channel.publish(StatusSnapshot(status: status))
  }
}
