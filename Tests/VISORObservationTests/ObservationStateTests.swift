import Observation
import Testing
@testable import VISORObservation

private struct ObservationStateSnapshot: Equatable, Sendable {
  var count = 0
  var label = "initial"
}

private final class ObservationStateProducer {
  @ObservationState
  private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot()

  func update(count: Int, label: String) {
    snapshot = ObservationStateSnapshot(count: count, label: label)
  }

  func increment() {
    snapshot.count += 1
  }
}

private final class SourceFirstObservationStateProducer {
  @ObservationState(initial: ObservationStateSnapshot())
  var snapshot: ObservationSource<ObservationStateSnapshot>

  func update(count: Int, label: String) {
    publishSnapshot(ObservationStateSnapshot(count: count, label: label))
  }
}

@MainActor
private final class SnapshotConsumer {
  init(source: ObservationSource<Int>) {
    task = Task { [weak self, source] in
      for await _ in source {
        guard !Task.isCancelled else { return }
        self?.receive()
      }
    }
  }

  deinit {
    task?.cancel()
  }

  private var task: Task<Void, Never>?

  private func receive() { }
}

private actor ActorObservationStateProducer {
  @ObservationState
  nonisolated private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot()

  init(snapshot: ObservationStateSnapshot) {
    self.snapshot = snapshot
  }

  func update(count: Int) {
    snapshot.count = count
  }
}

@MainActor
@Observable
private final class ObservableObservationStateProducer {
  @ObservationState
  @ObservationIgnored
  private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot()

  func update(count: Int) {
    snapshot.count = count
  }
}

@MainActor
@Observable
private final class SourceFirstObservableObservationStateProducer {
  @ObservationState(initial: ObservationStateSnapshot())
  @ObservationIgnored
  var snapshot: ObservationSource<ObservationStateSnapshot>

  func update(count: Int) {
    publishSnapshot(ObservationStateSnapshot(count: count))
  }
}

@Suite("Producer observation state")
struct ObservationStateTests {
  @Test
  func `A source-first producer exposes only its read-only State`() async {
    let producer = SourceFirstObservationStateProducer()
    let source = producer.snapshot
    let snapshots = source.makeAsyncIterator()

    #expect(await snapshots.next() == ObservationStateSnapshot())

    producer.update(count: 2, label: "updated")

    #expect(await snapshots.next() == ObservationStateSnapshot(count: 2, label: "updated"))
    #expect(source.currentSnapshot() == ObservationStateSnapshot(count: 2, label: "updated"))
    #expect(source._visorIdentity == producer.snapshot._visorIdentity)
  }

  @Test
  func `The generated source has stable identity and the latest snapshot`() {
    let producer = ObservationStateProducer()
    let source = producer.snapshotSource

    producer.update(count: 2, label: "updated")

    #expect(producer.snapshot == ObservationStateSnapshot(count: 2, label: "updated"))
    #expect(source.currentSnapshot() == producer.snapshot)
    #expect(source._visorIdentity == producer.snapshotSource._visorIdentity)
  }

  @Test
  func `In-place value mutation publishes the completed snapshot`() {
    let producer = ObservationStateProducer()

    producer.increment()

    #expect(producer.snapshotSource.currentSnapshot().count == 1)
  }

  @Test
  func `An actor can expose its generated source without isolation hops`() async {
    let producer = ActorObservationStateProducer(
      snapshot: ObservationStateSnapshot(count: 1, label: "actor"))
    let source = producer.snapshotSource

    #expect(source.currentSnapshot().count == 1)
    await producer.update(count: 5)

    #expect(source.currentSnapshot().count == 5)
  }

  @Test @MainActor
  func `Observation State composes with Observable`() {
    let producer = ObservableObservationStateProducer()

    producer.update(count: 3)

    #expect(producer.snapshot.count == 3)
    #expect(producer.snapshotSource.currentSnapshot().count == 3)
  }

  @Test @MainActor
  func `Source-first Observation State composes with explicit Observation exclusion`() {
    let producer = SourceFirstObservableObservationStateProducer()

    producer.update(count: 4)

    #expect(producer.snapshot.currentSnapshot().count == 4)
  }

  @Test
  func `A constant source retains one immutable snapshot`() {
    let source = ObservationSource.constant(ObservationStateSnapshot(count: 4, label: "constant"))

    #expect(source.currentSnapshot() == ObservationStateSnapshot(count: 4, label: "constant"))
  }

  @Test
  func `A generated snapshot stream emits its baseline and later publications`() async {
    let producer = ObservationStateProducer()
    let snapshots = producer.snapshotSource.makeAsyncIterator()

    #expect(await snapshots.next() == ObservationStateSnapshot())

    producer.update(count: 1, label: "published")

    #expect(await snapshots.next() == ObservationStateSnapshot(count: 1, label: "published"))
  }

  @Test
  @MainActor
  func `A service-owned snapshot task releases its owner while waiting`() async {
    let channel = ObservationChannel(0)
    var consumer: SnapshotConsumer? = SnapshotConsumer(source: channel.source)
    weak let weakConsumer = consumer

    while channel.source._visorActiveSubscriptionCount == 0 {
      await Task.yield()
    }
    consumer = nil
    for _ in 0..<100 where weakConsumer != nil {
      await Task.yield()
    }

    #expect(weakConsumer == nil)
  }
}
