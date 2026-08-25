import RootObservationConsumer
import Testing

@Suite("Root observation products from a downstream package")
struct RootObservationConsumerTests {
  @Test
  func `Observation State requirements cross the package boundary`() {
    let producer = RootObservationStateProducer()
    let provider: any RootObservationStateProviding = producer

    #expect(provider.count == 0)
    #expect(provider.countValues.currentSnapshot() == 0)

    producer.updateCount(1)

    #expect(provider.count == 1)
    #expect(provider.countValues.currentSnapshot() == 1)
  }

  @Test
  func `Public source and channel operations cross the package boundary`() {
    let consumer = RootObservationConsumer(initialValue: 1)

    #expect(consumer.snapshot() == 1)
    consumer.publish(2)
    #expect(consumer.snapshot() == 2)

    #expect(consumer.projectedSnapshot() == RootProjectedSnapshot(
      revision: 1,
      label: "revision-1",
    ))
    consumer.publish(RootProjectedSnapshot(
      revision: 3,
      label: "three",
    ))
    #expect(consumer.projectedSnapshot() == RootProjectedSnapshot(
      revision: 3,
      label: "three",
    ))
  }
}
