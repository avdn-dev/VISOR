import RootObservationConsumer
import Testing

@Suite("Root observation products from a downstream package")
struct RootObservationConsumerTests {
  @Test("Public source and channel operations cross the package boundary")
  func publicSourceAndChannelOperationsCrossTheBoundary() {
    let consumer = RootObservationConsumer(initialValue: 1)

    #expect(consumer.snapshot() == 1)
    consumer.publish(2)
    #expect(consumer.snapshot() == 2)

    #expect(consumer.projectedSnapshot() == RootProjectedSnapshot(
      revision: 1,
      label: "revision-1"))
    consumer.publish(RootProjectedSnapshot(
      revision: 3,
      label: "three"))
    #expect(consumer.projectedSnapshot() == RootProjectedSnapshot(
      revision: 3,
      label: "three"))
  }
}
