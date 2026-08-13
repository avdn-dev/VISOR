import VISORObservation

public actor ExternalSyncService {
  private let channel = ObservationChannel(0)

  public init() {}

  public nonisolated var observationSource: ObservationSource<Int> {
    channel.source
  }

  public func synchronise() async {
    channel.publish(observationSource.currentSnapshot() + 1)
  }

  public func publish(_ revision: Int) {
    channel.publish(revision)
  }
}
