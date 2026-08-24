import Observation
import Testing
import VISORTesting
@testable import VISORObservation
import os

private struct ObservationStateSnapshot: Equatable, Sendable {
  var count = 0
  var label = "initial"
}

private enum ObservationStateMutationError: Error {
  case expected
}

private enum InferredObservationFlag: Equatable, Sendable {
  case disabled
  case enabled
}

private struct InferredObservationAppearance: Equatable, Sendable {
  var allowsCustomAppearance = false
}

private struct InferredObservationItem: Equatable, Sendable {
  let identifier: Int
}

private final class InferredObservationStateProducer {
  @ObservationState
  private(set) var flag = InferredObservationFlag.disabled

  @ObservationState
  private(set) var appearance = InferredObservationAppearance(
    allowsCustomAppearance: false)

  @ObservationState
  private(set) var items = [InferredObservationItem]()

  @ObservationState(observedAs: .values)
  private(set) var enabled = false

  @ObservationState
  private(set) var retryCount = -1

  @ObservationState
  private(set) var status = "ready"

  func update() {
    flag = .enabled
    appearance = InferredObservationAppearance(allowsCustomAppearance: true)
    items = [InferredObservationItem(identifier: 1)]
    enabled = true
    retryCount = 1
    status = "updated"
  }
}

private final class ObservationStateProducer {
  @ObservationState
  private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot()

  func update(count: Int, label: String) {
    snapshot = ObservationStateSnapshot(count: count, label: label)
  }

  func mutate(count: Int, label: String) -> String {
    withMutableSnapshot { snapshot in
      snapshot.count = count
      snapshot.label = label
      return snapshot.label
    }
  }

  func mutateOrThrow(count: Int, shouldThrow: Bool) throws -> Int {
    try withMutableSnapshot { snapshot in
      snapshot.count = count
      if shouldThrow {
        throw ObservationStateMutationError.expected
      }
      return snapshot.count
    }
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
  init(
    source: ObservationSource<Int>,
    lifecycle: TestEventCounter)
  {
    self.lifecycle = lifecycle
    task = Task { [weak self, source, lifecycle] in
      do {
        for try await _ in source {
          guard !Task.isCancelled else { return }
          lifecycle.record()
          self?.receive()
        }
      } catch {
        Issue.record("Healthy lifetime-test source failed: \(error)")
      }
    }
  }

  deinit {
    lifecycle.record()
    task?.cancel()
  }

  private let lifecycle: TestEventCounter
  private var task: Task<Void, Never>?

  private func receive() { }
}

private actor ActorObservationStateProducer {
  @ObservationState
  private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot(
    count: 1,
    label: "actor")

  func update(count: Int) {
    withMutableSnapshot { snapshot in
      snapshot.count = count
    }
  }
}

@MainActor
@Observable
private final class ObservableObservationStateProducer {
  @ObservationState
  @ObservationIgnored
  private(set) var snapshot: ObservationStateSnapshot = ObservationStateSnapshot()

  func update(count: Int, label: String) {
    withMutableSnapshot { snapshot in
      snapshot.count = count
      snapshot.label = label
    }
  }
}

@Suite("Producer observation state")
struct ObservationStateTests {
  @Test
  func `Inferred concrete State types publish through generated sequences`() {
    let producer = InferredObservationStateProducer()

    #expect(producer.flagSnapshots.currentSnapshot() == .disabled)
    #expect(!producer.appearanceSnapshots.currentSnapshot().allowsCustomAppearance)
    #expect(producer.itemsSnapshots.currentSnapshot().isEmpty)
    #expect(!producer.enabledValues.currentSnapshot())
    #expect(producer.retryCountSnapshots.currentSnapshot() == -1)
    #expect(producer.statusSnapshots.currentSnapshot() == "ready")

    producer.update()

    #expect(producer.flagSnapshots.currentSnapshot() == .enabled)
    #expect(producer.appearanceSnapshots.currentSnapshot().allowsCustomAppearance)
    #expect(producer.itemsSnapshots.currentSnapshot() == [InferredObservationItem(identifier: 1)])
    #expect(producer.enabledValues.currentSnapshot())
    #expect(producer.retryCountSnapshots.currentSnapshot() == 1)
    #expect(producer.statusSnapshots.currentSnapshot() == "updated")
  }

  @Test
  func `Assignment updates State and publishes a snapshot`() async throws {
    let producer = ObservationStateProducer()
    let snapshots = producer.snapshotSnapshots.makeAsyncIterator()

    #expect(try await snapshots.next() == ObservationStateSnapshot())

    producer.update(count: 2, label: "updated")

    #expect(
      try await snapshots.next()
        == ObservationStateSnapshot(count: 2, label: "updated"))
    #expect(producer.snapshot == ObservationStateSnapshot(count: 2, label: "updated"))
  }

  @Test
  func `Generated mutation publishes one completed revision and returns its result`() throws {
    let producer = ObservationStateProducer()
    let source = producer.snapshotSnapshots
    let before = try source._visorOpen()
    before.subscription._visorCancel()

    let label = producer.mutate(count: 2, label: "updated")

    let after = try source._visorOpen()
    after.subscription._visorCancel()
    #expect(label == "updated")
    #expect(after.baseline.revision == before.baseline.revision + 1)
    #expect(after.baseline.snapshot == ObservationStateSnapshot(
      count: 2,
      label: "updated"))
  }

  @Test
  func `A throwing generated value mutation publishes no revision`() throws {
    let producer = ObservationStateProducer()
    let source = producer.snapshotSnapshots
    let before = try source._visorOpen()
    before.subscription._visorCancel()

    #expect(throws: ObservationStateMutationError.expected) {
      try producer.mutateOrThrow(count: 2, shouldThrow: true)
    }

    let after = try source._visorOpen()
    after.subscription._visorCancel()
    #expect(after.baseline.revision == before.baseline.revision)
    #expect(after.baseline.snapshot == ObservationStateSnapshot())
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

    let changeCount = OSAllocatedUnfairLock(initialState: 0)
    trackObservationStateChanges(
      reading: { [weak producer] in _ = producer?.snapshot },
      count: changeCount)

    await confirmation { changed in
      withObservationTracking {
        _ = producer.snapshot
      } onChange: {
        changed()
      }

      producer.update(count: 3, label: "complete")
    }

    #expect(changeCount.withLock { $0 } == 1)
    #expect(producer.snapshot.count == 3)
    #expect(producer.snapshot.label == "complete")
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
    let lifecycle = TestEventCounter()
    var consumer: SnapshotConsumer? = SnapshotConsumer(
      source: channel.source,
      lifecycle: lifecycle)
    weak let weakConsumer = consumer

    await lifecycle.wait()
    consumer = nil
    await lifecycle.wait(for: 2)

    #expect(weakConsumer == nil)
  }
}

@MainActor
private func trackObservationStateChanges(
  reading snapshot: @escaping @MainActor @Sendable () -> Void,
  count: OSAllocatedUnfairLock<Int>
) {
  withObservationTracking {
    snapshot()
  } onChange: {
    count.withLock { $0 += 1 }
    MainActor.assumeIsolated {
      trackObservationStateChanges(reading: snapshot, count: count)
    }
  }
}
