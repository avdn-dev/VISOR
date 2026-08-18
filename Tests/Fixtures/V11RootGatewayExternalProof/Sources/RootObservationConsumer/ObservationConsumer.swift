import VISOR
import VISORObservation

@ObservationStateRequirements
public protocol RootObservationStateProviding {
  @ObservationState(initial: 0, observedAs: .values)
  var count: Int { get }
}

public final class RootObservationStateProducer: RootObservationStateProviding {
  @ObservationState(observedAs: .values)
  public private(set) var count = 0

  public init() {}

  public func updateCount(_ count: Int) {
    self.count = count
  }
}

public struct RootProjectedSnapshot: Equatable, Sendable {
  public let revision: Int
  public let label: String

  public init(revision: Int, label: String) {
    self.revision = revision
    self.label = label
  }
}

public struct RootObservationConsumer: Sendable {
  private let channel: ObservationChannel<Int>
  private let projectedChannel: ObservationChannel<RootProjectedSnapshot>
  public let source: ObservationSource<Int>
  public let projectedSource: ObservationSource<RootProjectedSnapshot>

  public init(initialValue: Int) {
    let channel = ObservationChannel(initialValue)
    let projectedChannel = ObservationChannel(RootProjectedSnapshot(
      revision: initialValue,
      label: "revision-\(initialValue)"))
    self.channel = channel
    self.projectedChannel = projectedChannel
    source = channel.source
    projectedSource = projectedChannel.source
  }

  public func publish(_ value: Int) {
    channel.publish(value)
  }

  public func publish(_ snapshot: RootProjectedSnapshot) {
    projectedChannel.publish(snapshot)
  }

  public func snapshot() -> Int {
    source.currentSnapshot()
  }

  public func projectedSnapshot() -> RootProjectedSnapshot {
    projectedSource.currentSnapshot()
  }
}

@MainActor
public func describeRootObservation(
  source: ObservationSource<Int>,
  into visitor: VISOR._ObservationRecipeVisitor
) {
  visitor.add(
    source: source,
    projections: [{ _ in }])
}
