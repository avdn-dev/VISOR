import VISOR
import VISORObservation

// MARK: - RootObservationStateProviding

@ObservationStateRequirements
public protocol RootObservationStateProviding {
  @ObservationState(initial: 0, observedAs: .values)
  var count: Int { get }
}

// MARK: - RootObservationStateProducer

public final class RootObservationStateProducer: RootObservationStateProviding {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  @ObservationState(observedAs: .values)
  public private(set) var count = 0

  public func updateCount(_ count: Int) {
    withMutableCount { value in
      value = count
    }
  }
}

// MARK: - RootProjectedSnapshot

public struct RootProjectedSnapshot: Equatable, Sendable {
  public init(revision: Int, label: String) {
    self.revision = revision
    self.label = label
  }

  public let revision: Int
  public let label: String

}

// MARK: - RootObservationConsumer

public struct RootObservationConsumer: Sendable {

  // MARK: Lifecycle

  public init(initialValue: Int) {
    let channel = ObservationChannel(initialValue)
    let projectedChannel = ObservationChannel(RootProjectedSnapshot(
      revision: initialValue,
      label: "revision-\(initialValue)",
    ))
    self.channel = channel
    self.projectedChannel = projectedChannel
    source = channel.source
    projectedSource = projectedChannel.source
  }

  // MARK: Public

  public let source: ObservationSource<Int>
  public let projectedSource: ObservationSource<RootProjectedSnapshot>

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

  // MARK: Private

  private let channel: ObservationChannel<Int>
  private let projectedChannel: ObservationChannel<RootProjectedSnapshot>

}

@MainActor
public func describeRootObservation(
  source: ObservationSource<Int>,
  into visitor: VISOR._ObservationRecipeVisitor,
) {
  visitor.add(
    source: source,
    projections: [{ _ in }],
  )
}
