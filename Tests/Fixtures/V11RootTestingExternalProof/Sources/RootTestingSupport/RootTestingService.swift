import VISORObservation

public struct RootTestingService: Sendable {
  private let channel: ObservationChannel<Int>
  public let source: ObservationSource<Int>

  public init(initialValue: Int) {
    let channel = ObservationChannel(initialValue)
    self.channel = channel
    source = channel.source
  }

  public func publish(_ value: Int) {
    channel.publish(value)
  }
}
