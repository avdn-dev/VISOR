import Testing
import VISORObservation
import VISORTesting

private actor Producer {
  private let channel: ObservationChannel<Int>
  nonisolated let source: ObservationSource<Int>

  init(initial: Int) {
    let channel = ObservationChannel(initial)
    self.channel = channel
    source = channel.source
  }

  func publish(_ value: Int) {
    channel.publish(value)
  }

  func terminate() {
    channel._visorTerminate()
  }
}

@Suite("Public observation snapshots")
struct ObservationSnapshotsTests {
  @Test
  func `Each iterator independently receives the baseline and next publication`() async throws {
    let channel = ObservationChannel(0)
    let first = channel.source.makeAsyncIterator()
    let second = channel.source.makeAsyncIterator()

    #expect(try await first.next() == 0)
    #expect(try await second.next() == 0)

    channel.publish(1)

    #expect(try await first.next() == 1)
    #expect(try await second.next() == 1)
  }

  @Test
  func `Iterator coalesces queued publications to the latest snapshot`() async throws {
    let channel = ObservationChannel(0)
    let iterator = channel.source.makeAsyncIterator()
    #expect(try await iterator.next() == 0)

    channel.publish(1)
    channel.publish(2)
    channel.publish(3)

    #expect(try await iterator.next() == 3)
  }

  @Test
  func `Unexpected termination surfaces the public iterator error`() async throws {
    let channel = ObservationChannel(0)
    let iterator = channel.source.makeAsyncIterator()
    #expect(try await iterator.next() == 0)

    channel._visorTerminate()

    await #expect(throws: ObservationSourceError.terminatedUnexpectedly) {
      _ = try await iterator.next()
    }
  }
}

private actor OrderedProducer {
  private var value = 0
  private let channel: ObservationChannel<Int>
  nonisolated let source: ObservationSource<Int>

  init() {
    let channel = ObservationChannel(0)
    self.channel = channel
    source = channel.source
  }

  func advance() {
    value += 1
    channel.publish(value)
  }
}

private enum Projection<Output: Sendable>: Sendable {
  case deliver(Output)
  case acknowledgeOnly
}

@MainActor
private final class Consumer<Input: Sendable, Output: Sendable> {
  private let subscription: _ObservationSubscription<Input>
  private let project: @Sendable (Input) -> Projection<Output>
  private let receive: @MainActor @Sendable (Output) async -> Void
  private var worker: Task<Void, any Error>!

  private init(
    subscription: _ObservationSubscription<Input>,
    project: @escaping @Sendable (Input) -> Projection<Output>,
    receive: @escaping @MainActor @Sendable (Output) async -> Void
  ) {
    self.subscription = subscription
    self.project = project
    self.receive = receive
  }

  static func start(
    source: ObservationSource<Input>,
    project: @escaping @Sendable (Input) -> Projection<Output>,
    receive: @escaping @MainActor @Sendable (Output) async -> Void
  ) async throws -> Consumer {
    let opened = try source._visorOpen()
    let consumer = Consumer(
      subscription: opened.subscription,
      project: project,
      receive: receive)

    do {
      try Task.checkCancellation()
      try await consumer.consume(opened.baseline)
      try Task.checkCancellation()
      consumer.startWorker()
      return consumer
    } catch {
      opened.subscription._visorCancel()
      throw error
    }
  }

  func checkpointAndPause() async throws -> _ObservationCheckpoint<Input> {
    let checkpoint = try subscription._visorCheckpointAndPause()
    try await subscription._visorWaitUntilAcknowledged(checkpoint)
    return checkpoint
  }

  func resume(after checkpoint: _ObservationCheckpoint<Input>) throws {
    try subscription._visorResume(after: checkpoint)
  }

  func cancelAndJoin() async {
    worker.cancel()
    subscription._visorCancel()
    _ = await worker.result
  }

  func result() async -> Result<Void, any Error> {
    await worker.result
  }

  private func startWorker() {
    worker = Task { @MainActor [subscription, project, receive] in
      while let envelope = try await subscription._visorNext() {
        try Task.checkCancellation()
        switch project(envelope.snapshot) {
        case .deliver(let output):
          await receive(output)
        case .acknowledgeOnly:
          break
        }
        try subscription._visorAcknowledge(envelope)
      }
    }
  }

  private func consume(_ envelope: _ObservationEnvelope<Input>) async throws {
    switch project(envelope.snapshot) {
    case .deliver(let output):
      await receive(output)
    case .acknowledgeOnly:
      break
    }
    try subscription._visorAcknowledge(envelope)
  }
}

@MainActor
private final class Model {
  var current = -1
  var received: [Int] = []

  func receive(_ value: Int) {
    current = value
    received.append(value)
  }
}

@Suite("V11 cooperative observation source")
struct ObservationSourceTests {
  @Test @MainActor
  func `Actor producer settles into MainActor State through a checkpoint`() async throws {
    let producer = Producer(initial: 0)
    let model = Model()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { .deliver($0) },
      receive: { [model] in model.receive($0) })

    let startup = try await consumer.checkpointAndPause()
    try consumer.resume(after: startup)
    #expect(model.current == 0)

    await producer.publish(1)
    let closing = try await consumer.checkpointAndPause()
    #expect(model.current == 1)
    #expect(model.received == [0, 1])
    try consumer.resume(after: closing)

    await consumer.cancelAndJoin()
  }

  @Test @MainActor
  func `Opening concurrently with publication loses no latest State`() async throws {
    for _ in 0..<500 {
      let producer = Producer(initial: 0)
      let model = Model()

      async let publication: Void = producer.publish(1)
      let consumer = try await Consumer.start(
        source: producer.source,
        project: { .deliver($0) },
        receive: { [model] in model.receive($0) })
      await publication

      let startup = try await consumer.checkpointAndPause()
      #expect(model.current == 1)
      try consumer.resume(after: startup)
      await consumer.cancelAndJoin()
    }
  }

  @Test @MainActor
  func `Copied source handles retain one stable producer identity`() throws {
    let channel = ObservationChannel(0)
    let firstSource = channel.source
    let copiedSource = firstSource
    let first = try firstSource._visorOpen()

    channel.publish(1)
    let second = try copiedSource._visorOpen()

    #expect(first.baseline.sourceID == second.baseline.sourceID)
    #expect(first.baseline.epoch == second.baseline.epoch)
    #expect(first.baseline.revision == 0)
    #expect(second.baseline.revision == 1)

    first.subscription._visorCancel()
    second.subscription._visorCancel()
  }

  @Test @MainActor
  func `Service actor mutation and publication remain in one actor turn`() async throws {
    let producer = OrderedProducer()
    let model = Model()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { .deliver($0) },
      receive: { [model] in model.receive($0) })
    let startup = try await consumer.checkpointAndPause()
    try consumer.resume(after: startup)

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<500 {
        group.addTask {
          await producer.advance()
        }
      }
    }

    let closing = try await consumer.checkpointAndPause()
    #expect(model.current == 500)
    try consumer.resume(after: closing)
    await consumer.cancelAndJoin()
  }

  @Test @MainActor
  func `A paused subscription retains only the newest snapshot`() async throws {
    let producer = Producer(initial: 0)
    let model = Model()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { .deliver($0) },
      receive: { [model] in model.receive($0) })

    let startup = try await consumer.checkpointAndPause()
    await producer.publish(1)
    await producer.publish(2)
    await producer.publish(3)
    #expect(model.received == [0])

    try consumer.resume(after: startup)
    let closing = try await consumer.checkpointAndPause()
    #expect(model.received == [0, 3])
    try consumer.resume(after: closing)
    await consumer.cancelAndJoin()
  }

  @Test @MainActor
  func `Concurrent publication falls wholly before or after the checkpoint cut`() async throws {
    for _ in 0..<500 {
      let producer = Producer(initial: 0)
      let model = Model()
      let consumer = try await Consumer.start(
        source: producer.source,
        project: { .deliver($0) },
        receive: { [model] in model.receive($0) })
      let startup = try await consumer.checkpointAndPause()
      try consumer.resume(after: startup)

      async let publication: Void = producer.publish(1)
      let cut = try await consumer.checkpointAndPause()
      await publication

      // If publication won, both values are 1. If the checkpoint won, both
      // are 0 and the publication is held. A torn cut would disagree here.
      #expect(model.current == cut.envelope.snapshot)
      try consumer.resume(after: cut)

      let settled = try await consumer.checkpointAndPause()
      #expect(model.current == 1)
      #expect(settled.envelope.snapshot == 1)
      try consumer.resume(after: settled)
      await consumer.cancelAndJoin()
    }
  }

  @Test @MainActor
  func `A filtered revision is acknowledged and cannot strand a fence`() async throws {
    let producer = Producer(initial: 0)
    let model = Model()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { value in
        value.isMultiple(of: 2) ? .deliver(value * 10) : .acknowledgeOnly
      },
      receive: { [model] in model.receive($0) })

    let startup = try await consumer.checkpointAndPause()
    try consumer.resume(after: startup)
    await producer.publish(1)

    let filtered = try await consumer.checkpointAndPause()
    #expect(model.received == [0])
    try consumer.resume(after: filtered)

    await producer.publish(2)
    let mapped = try await consumer.checkpointAndPause()
    #expect(model.received == [0, 20])
    try consumer.resume(after: mapped)
    await consumer.cancelAndJoin()
  }

  @Test @MainActor
  func `A checkpoint waits for its immediate handler to acknowledge`() async throws {
    let producer = Producer(initial: 0)
    let model = Model()
    let gate = ControllableOperation<Void, Never>()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { .deliver($0) },
      receive: { [model, gate] value in
        if value == 1 {
          await gate.run()
        }
        model.receive(value)
      })
    let startup = try await consumer.checkpointAndPause()
    try consumer.resume(after: startup)

    await producer.publish(1)
    let fence = Task { @MainActor in
      try await consumer.checkpointAndPause()
    }

    await gate.waitUntilStarted()
    #expect(model.current == 0)
    gate.finish()

    let checkpoint = try await fence.value
    #expect(model.current == 1)
    try consumer.resume(after: checkpoint)
    await consumer.cancelAndJoin()
  }

  @Test @MainActor
  func `A slow subscriber does not block publication or another subscriber`() async throws {
    let channel = ObservationChannel(0)
    let slowModel = Model()
    let fastModel = Model()
    let gate = ControllableOperation<Void, Never>()
    let slow = try await Consumer.start(
      source: channel.source,
      project: { .deliver($0) },
      receive: { [slowModel, gate] value in
        if value == 1 {
          await gate.run()
        }
        slowModel.receive(value)
      })
    let fast = try await Consumer.start(
      source: channel.source,
      project: { .deliver($0) },
      receive: { [fastModel] in fastModel.receive($0) })

    let slowStartup = try await slow.checkpointAndPause()
    let fastStartup = try await fast.checkpointAndPause()
    try slow.resume(after: slowStartup)
    try fast.resume(after: fastStartup)

    channel.publish(1)
    await gate.waitUntilStarted()

    let fastFirst = try await fast.checkpointAndPause()
    #expect(fastModel.current == 1)
    #expect(slowModel.current == 0)

    channel.publish(2)
    try fast.resume(after: fastFirst)
    let fastSecond = try await fast.checkpointAndPause()
    #expect(fastModel.current == 2)
    #expect(slowModel.current == 0)

    gate.finish()
    let slowSettled = try await slow.checkpointAndPause()
    #expect(slowModel.current == 2)

    try fast.resume(after: fastSecond)
    try slow.resume(after: slowSettled)
    await fast.cancelAndJoin()
    await slow.cancelAndJoin()
  }
  @Test
  func `Grouped channels retain distinct sources in one producer domain`() {
    let lifecycle = ObservationChannel(0)
    let waveform = ObservationChannel(
      "quiet",
      groupedWith: lifecycle)
    let independent = ObservationChannel(false)

    #expect(lifecycle.source._visorIdentity != waveform.source._visorIdentity)
    #expect(
      lifecycle.source._visorGroupIdentity
        == waveform.source._visorGroupIdentity)
    #expect(
      lifecycle.source._visorGroupIdentity
        != independent.source._visorGroupIdentity)
  }

  @Test
  func `Grouped opening captures every baseline under one source group`() throws {
    let first = ObservationChannel(1)
    let second = ObservationChannel(
      "ready",
      groupedWith: first)

    let prepared = try _ObservationRuntime._visorPrepareAll([
      first.source._visorErase(),
      second.source._visorErase(),
    ])
    let firstObservation = try prepared[0]._visorUnwrap(as: Int.self)
    let secondObservation = try prepared[1]._visorUnwrap(as: String.self)

    #expect(firstObservation.baseline.snapshot == 1)
    #expect(secondObservation.baseline.snapshot == "ready")
    #expect(first.source._visorActiveSubscriptionCount == 1)
    #expect(second.source._visorActiveSubscriptionCount == 1)

    for observation in prepared {
      observation._visorCancel()
    }
    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(second.source._visorActiveSubscriptionCount == 0)
  }

  @Test
  func `A group cut may fall between separate publications`() throws {
    let first = ObservationChannel(0)
    let second = ObservationChannel(
      "old",
      groupedWith: first)

    first.publish(1)
    let prepared = try _ObservationRuntime._visorPrepareAll([
      first.source._visorErase(),
      second.source._visorErase(),
    ])
    let firstObservation = try prepared[0]._visorUnwrap(as: Int.self)
    let secondObservation = try prepared[1]._visorUnwrap(as: String.self)

    #expect(firstObservation.baseline.snapshot == 1)
    #expect(secondObservation.baseline.snapshot == "old")

    for observation in prepared {
      observation._visorCancel()
    }
  }

  @Test
  func `Rejected group checkpoint fails closed without a stranded pause`() throws {
    let first = ObservationChannel(1)
    let second = ObservationChannel(
      "ready",
      groupedWith: first)
    let prepared = try _ObservationRuntime._visorPrepareAll([
      first.source._visorErase(),
      second.source._visorErase(),
    ])
    let firstOpened = try prepared[0]
      ._visorUnwrap(as: Int.self)
      ._visorActivate()
    let secondOpened = try prepared[1]
      ._visorUnwrap(as: String.self)
      ._visorActivate()
    try firstOpened.subscription._visorAcknowledge(firstOpened.baseline)
    try secondOpened.subscription._visorAcknowledge(secondOpened.baseline)

    let existing = try secondOpened.subscription
      ._visorCheckpointAndPause()
    #expect(throws: _ObservationSourceFailure.self) {
      _ = try _ObservationRuntime._visorCheckpointAndPauseAll([
        firstOpened.subscription._visorErase(),
        secondOpened.subscription._visorErase(),
      ])
    }

    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(second.source._visorActiveSubscriptionCount == 0)
    #expect(throws: CancellationError.self) {
      try secondOpened.subscription._visorResume(after: existing)
    }
  }

  @Test
  func `Later group failure cancels an earlier captured group`() throws {
    let first = ObservationChannel(1)
    let second = ObservationChannel("ready")
    let firstOpened = try first.source._visorOpen()
    let secondOpened = try second.source._visorOpen()
    try firstOpened.subscription._visorAcknowledge(firstOpened.baseline)
    try secondOpened.subscription._visorAcknowledge(secondOpened.baseline)

    _ = try secondOpened.subscription._visorCheckpointAndPause()
    #expect(throws: _ObservationSourceFailure.self) {
      _ = try _ObservationRuntime._visorCheckpointAndPauseAll([
        firstOpened.subscription._visorErase(),
        secondOpened.subscription._visorErase(),
      ])
    }

    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(second.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Cancellation joins the iterator and prevents later delivery`() async throws {
    let producer = Producer(initial: 0)
    let model = Model()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { .deliver($0) },
      receive: { [model] in model.receive($0) })
    let startup = try await consumer.checkpointAndPause()
    try consumer.resume(after: startup)

    await consumer.cancelAndJoin()
    await producer.publish(1)
    #expect(model.received == [0])
  }

  @Test @MainActor
  func `Unexpected source termination wakes the iterator and later fences`() async throws {
    let producer = Producer(initial: 0)
    let model = Model()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { .deliver($0) },
      receive: { [model] in model.receive($0) })
    let startup = try await consumer.checkpointAndPause()
    try consumer.resume(after: startup)

    await producer.terminate()
    let result = await consumer.result()
    switch result {
    case .success:
      Issue.record("Termination unexpectedly completed the consumer normally")
    case .failure(let error):
      #expect(error as? _ObservationSourceFailure == .unexpectedTermination)
    }

    await #expect(throws: _ObservationSourceFailure.unexpectedTermination) {
      _ = try await consumer.checkpointAndPause()
    }
  }

  @Test
  func `Termination wakes a pending acknowledgement fence`() async throws {
    let channel = ObservationChannel(0)
    let opened = try channel.source._visorOpen()
    try opened.subscription._visorAcknowledge(opened.baseline)
    channel.publish(1)
    let checkpoint = try opened.subscription._visorCheckpointAndPause()

    let waiter = Task {
      try await opened.subscription._visorWaitUntilAcknowledged(checkpoint)
    }
    channel._visorTerminate()

    await #expect(throws: _ObservationSourceFailure.unexpectedTermination) {
      try await waiter.value
    }
  }
}
