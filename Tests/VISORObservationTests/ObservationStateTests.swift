import Observation
import Testing
@testable import VISORObservation
import os

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

private enum ObservationStateInitialiserProbe {
  static let count = OSAllocatedUnfairLock(initialState: 0)

  static func makeSnapshot() -> ObservationStateSnapshot {
    count.withLock { $0 += 1 }
    return ObservationStateSnapshot()
  }
}

private final class ExactlyOnceObservationStateProducer {
  @ObservationState
  var snapshot: ObservationStateSnapshot = ObservationStateInitialiserProbe.makeSnapshot()
}

private final class ReinitialisedObservationStateProducer {
  @ObservationState
  private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot()

  init(snapshot: ObservationStateSnapshot) {
    self.snapshot = snapshot
  }
}

private final class AttributeInitialValueProducer {
  @ObservationState(observedAs: .values)
  private(set) var optional: Int? = nil

  @ObservationState
  private(set) var items: [Int] = []
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
  private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot(
    count: 1,
    label: "actor")

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

@Suite("Producer observation state")
struct ObservationStateTests {
  @Test
  func `Assignment updates State and publishes a snapshot`() async {
    let producer = ObservationStateProducer()
    let snapshots = producer.snapshotSnapshots.makeAsyncIterator()

    #expect(await snapshots.next() == ObservationStateSnapshot())

    producer.update(count: 2, label: "updated")

    #expect(await snapshots.next() == ObservationStateSnapshot(count: 2, label: "updated"))
    #expect(producer.snapshot == ObservationStateSnapshot(count: 2, label: "updated"))
  }

  @Test
  func `An authored initial value is evaluated exactly once`() {
    ObservationStateInitialiserProbe.count.withLock { $0 = 0 }

    let producer = ExactlyOnceObservationStateProducer()

    #expect(ObservationStateInitialiserProbe.count.withLock { $0 } == 1)
    #expect(producer.snapshotSnapshots.currentSnapshot() == producer.snapshot)
  }

  @Test
  func `An enclosing initialiser can replace a declaration default`() {
    let initial = ObservationStateSnapshot(count: 7, label: "initialised")

    let producer = ReinitialisedObservationStateProducer(snapshot: initial)

    #expect(producer.snapshot == initial)
    #expect(producer.snapshotSnapshots.currentSnapshot() == initial)
  }

  @Test
  func `The generated sequence has stable identity and the latest snapshot`() {
    let producer = ObservationStateProducer()
    let source = producer.snapshotSnapshots

    producer.update(count: 2, label: "updated")

    #expect(source.currentSnapshot() == producer.snapshot)
    #expect(source._visorIdentity == producer.snapshotSnapshots._visorIdentity)
  }

  @Test
  func `In-place value mutation publishes the completed snapshot`() {
    let producer = ObservationStateProducer()

    producer.increment()

    #expect(producer.snapshotSnapshots.currentSnapshot().count == 1)
  }

  @Test
  func `Attribute initial values establish typed baselines`() {
    let producer = AttributeInitialValueProducer()

    #expect(producer.optional == nil)
    #expect(producer.optionalValues.currentSnapshot() == nil)
    #expect(producer.items.isEmpty)
    #expect(producer.itemsSnapshots.currentSnapshot().isEmpty)
  }

  @Test
  func `An actor can expose snapshots without an isolation hop`() async {
    let producer = ActorObservationStateProducer()
    let snapshots = producer.snapshotSnapshots

    #expect(snapshots.currentSnapshot().count == 1)
    await producer.update(count: 5)

    #expect(snapshots.currentSnapshot().count == 5)
  }

  @Test @MainActor
  func `Observation State participates in Apple Observation`() async {
    let producer = ObservableObservationStateProducer()

    await confirmation { changed in
      withObservationTracking {
        _ = producer.snapshot
      } onChange: {
        changed()
      }

      producer.update(count: 3)
    }

    #expect(producer.snapshot.count == 3)
    #expect(producer.snapshotSnapshots.currentSnapshot().count == 3)
  }

  @Test
  func `A constant source retains one immutable snapshot`() {
    let source = ObservationSource.constant(ObservationStateSnapshot(count: 4, label: "constant"))

    #expect(source.currentSnapshot() == ObservationStateSnapshot(count: 4, label: "constant"))
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
