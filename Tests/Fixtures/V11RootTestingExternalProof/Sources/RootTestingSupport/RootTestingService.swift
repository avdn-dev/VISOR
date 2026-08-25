import VISORObservation

public struct RootTestingService: Sendable {
  public init(initialValue: Int) {
    let channel = ObservationChannel(initialValue)
    self.channel = channel
    source = channel.source
  }

  public let source: ObservationSource<Int>

  public func publish(_ value: Int) {
    channel.publish(value)
  }

  private let channel: ObservationChannel<Int>

}
