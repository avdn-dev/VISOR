import Testing
import VISOR
import VISORObservation

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

@MainActor
private final class HandlerGate {
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var didStart = false

  func wait() async {
    didStart = true
    startedContinuation?.resume()
    startedContinuation = nil
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    guard !didStart else { return }
    await withCheckedContinuation { continuation in
      startedContinuation = continuation
    }
  }

  func open() {
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class OneShotSignal {
  private var continuation: CheckedContinuation<Void, Never>?
  private var didFire = false

  func wait() async {
    guard !didFire else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func fire() {
    guard !didFire else { return }
    didFire = true
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class ReadinessLog {
  var events: [String] = []
  var first = -1
  var firstDerived = -1
  var second = -1
}

@MainActor
private final class SessionLog {
  var events: [String] = []
  var integer = -1
  var text = ""
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
    let gate = HandlerGate()
    let consumer = try await Consumer.start(
      source: producer.source,
      project: { .deliver($0) },
      receive: { [model, gate] value in
        if value == 1 {
          await gate.wait()
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
    gate.open()

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
    let gate = HandlerGate()
    let slow = try await Consumer.start(
      source: channel.source,
      project: { .deliver($0) },
      receive: { [slowModel, gate] value in
        if value == 1 {
          await gate.wait()
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

    gate.open()
    let slowSettled = try await slow.checkpointAndPause()
    #expect(slowModel.current == 2)

    try fast.resume(after: fastSecond)
    try slow.resume(after: slowSettled)
    await fast.cancelAndJoin()
    await slow.cancelAndJoin()
  }

  @Test @MainActor
  func `All sources arm before deterministic initial handlers run`() async throws {
    let firstChannel = ObservationChannel(1)
    let secondChannel = ObservationChannel(2)
    let log = ReadinessLog()

    let firstLane = _ObservationLane(
      source: firstChannel.source,
      handlers: [
        { [log] value in
          log.events.append("first-bound")
          log.first = value
        },
        { [log] value in
          log.events.append("first-reaction")
          log.firstDerived = value * 10
        },
      ])
    let secondLane = _ObservationLane(
      source: secondChannel.source,
      handlers: [
        { [log] value in
          log.events.append("second-bound")
          log.second = value
        },
      ])

    let firstPrepared = try firstLane._visorPrepare()
    firstChannel.publish(3)
    let secondPrepared = try secondLane._visorPrepare()
    secondChannel.publish(4)

    try await firstPrepared._visorActivate()
    try await secondPrepared._visorActivate()

    let firstReady = try await firstLane._visorCheckpointAndPause()
    let secondReady = try await secondLane._visorCheckpointAndPause()

    #expect(log.events.prefix(3) == [
      "first-bound",
      "first-reaction",
      "second-bound",
    ])
    #expect(log.first == 3)
    #expect(log.firstDerived == 30)
    #expect(log.second == 4)

    try firstLane._visorResume(after: firstReady)
    try secondLane._visorResume(after: secondReady)
    await firstLane._visorCancelAndJoin()
    await secondLane._visorCancelAndJoin()
  }

  @Test @MainActor
  func `Partial multi-source preparation failure rolls back earlier subscriptions`() async {
    let firstChannel = ObservationChannel(1)
    let failedChannel = ObservationChannel(2)
    failedChannel._visorTerminate()
    let firstLane = _ObservationLane(
      source: firstChannel.source,
      handlers: [])
    let failedLane = _ObservationLane(
      source: failedChannel.source,
      handlers: [])

    #expect(throws: _ObservationSourceFailure.unexpectedTermination) {
      let firstPrepared = try firstLane._visorPrepare()
      #expect(firstChannel.source._visorActiveSubscriptionCount == 1)
      _ = firstPrepared
      _ = try failedLane._visorPrepare()
    }

    #expect(firstChannel.source._visorActiveSubscriptionCount == 0)
    #expect(failedChannel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Cancellation between source preparations releases the prepared source`() async {
    let firstChannel = ObservationChannel(1)
    let secondChannel = ObservationChannel(2)
    let firstLane = _ObservationLane(
      source: firstChannel.source,
      handlers: [])
    let secondLane = _ObservationLane(
      source: secondChannel.source,
      handlers: [])
    let gate = HandlerGate()

    let preparation = Task { @MainActor in
      let firstPrepared = try firstLane._visorPrepare()
      await gate.wait()
      try Task.checkCancellation()
      _ = firstPrepared
      _ = try secondLane._visorPrepare()
    }

    await gate.waitUntilStarted()
    preparation.cancel()
    gate.open()

    await #expect(throws: CancellationError.self) {
      try await preparation.value
    }
    #expect(firstChannel.source._visorActiveSubscriptionCount == 0)
    #expect(secondChannel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Duplicate lane preparation and activation report protocol violations`() async throws {
    let channel = ObservationChannel(0)
    let lane = _ObservationLane(
      source: channel.source,
      handlers: [])
    let prepared = try lane._visorPrepare()

    #expect(throws: _ObservationSourceFailure.self) {
      _ = try lane._visorPrepare()
    }
    #expect(channel.source._visorActiveSubscriptionCount == 1)

    try await prepared._visorActivate()
    await #expect(throws: _ObservationSourceFailure.self) {
      try await prepared._visorActivate()
    }

    await lane._visorCancelAndJoin()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Cancelling baseline activation removes its prepared subscription`() async throws {
    let channel = ObservationChannel(0)
    let model = Model()
    let gate = HandlerGate()
    let lane = _ObservationLane(
      source: channel.source,
      handlers: [
        { [model, gate] value in
          await gate.wait()
          model.receive(value)
        },
      ])
    let prepared = try lane._visorPrepare()
    let activation = Task { @MainActor in
      try await prepared._visorActivate()
    }

    await gate.waitUntilStarted()
    activation.cancel()
    gate.open()

    await #expect(throws: CancellationError.self) {
      try await activation.value
    }
    #expect(channel.source._visorActiveSubscriptionCount == 0)

    channel.publish(1)
    #expect(model.received == [0])
  }

  @Test @MainActor
  func `Cancelling a checkpoint drain tears down the paused lane`() async throws {
    let channel = ObservationChannel(0)
    let model = Model()
    let gate = HandlerGate()
    let lane = _ObservationLane(
      source: channel.source,
      handlers: [
        { [model, gate] value in
          if value == 1 {
            await gate.wait()
          }
          model.receive(value)
        },
      ])
    let prepared = try lane._visorPrepare()
    try await prepared._visorActivate()
    let startup = try await lane._visorCheckpointAndPause()
    try lane._visorResume(after: startup)

    channel.publish(1)
    let fence = Task { @MainActor in
      try await lane._visorCheckpointAndPause()
    }
    await gate.waitUntilStarted()
    fence.cancel()
    gate.open()

    await #expect(throws: CancellationError.self) {
      try await fence.value
    }
    #expect(channel.source._visorActiveSubscriptionCount == 0)

    channel.publish(2)
    #expect(model.received == [0, 1])
  }

  @Test @MainActor
  func `Opening and closing fences place revisions on the correct side`() async throws {
    let channel = ObservationChannel(0)
    let model = Model()
    let lane = _ObservationLane(
      source: channel.source,
      handlers: [
        { [model] value in model.receive(value) },
      ])
    let prepared = try lane._visorPrepare()
    try await prepared._visorActivate()

    let startup = try await lane._visorCheckpointAndPause()
    channel.publish(1)
    #expect(model.received == [0])

    var window: [Int] = []
    try lane._visorResume(after: startup)
    let actionFence = try await lane._visorCheckpointAndPause()
    window.append(contentsOf: model.received.dropFirst())
    #expect(window == [1])

    channel.publish(2)
    #expect(window == [1])
    #expect(model.current == 1)

    try lane._visorResume(after: actionFence)
    let nextOpeningFence = try await lane._visorCheckpointAndPause()
    #expect(model.current == 2)
    #expect(window == [1])

    try lane._visorResume(after: nextOpeningFence)
    await lane._visorCancelAndJoin()
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
  func `Heterogeneous session arms everything before ordered startup work`() async throws {
    let first = ObservationChannel(1)
    let second = ObservationChannel("ready")
    let log = SessionLog()

    let firstLane = _ObservationLane(
      source: first.source,
      handlers: [
        { [log] value in
          #expect(first.source._visorActiveSubscriptionCount == 1)
          #expect(second.source._visorActiveSubscriptionCount == 1)
          log.events.append("integer")
          log.integer = value
        },
      ])
    let secondLane = _ObservationLane(
      source: second.source,
      handlers: [
        { [log] value in
          log.events.append("text")
          log.text = value
        },
      ])
    let session = _ObservationSession(lanes: [
      firstLane._visorErase(),
      secondLane._visorErase(),
    ])

    try await session._visorStart()

    #expect(session._visorIsReady)
    #expect(log.events == ["integer", "text"])
    #expect(log.integer == 1)
    #expect(log.text == "ready")

    await session._visorStop()
    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(second.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Every baseline projection precedes every initial reaction`() async throws {
    let first = ObservationChannel(1)
    let second = ObservationChannel("ready")
    let log = SessionLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: first.source,
        handlers: [
          { [log] value in
            log.integer = value
            log.events.append("integer-projection")
          },
        ],
        initialReactions: [
          { [log] _ in
            log.events.append("reaction-saw-\(log.text)")
          },
        ])._visorErase(),
      _ObservationLane(
        source: second.source,
        handlers: [
          { [log] value in
            log.text = value
            log.events.append("text-projection")
          },
        ])._visorErase(),
    ])

    try await session._visorStart()

    #expect(log.events == [
      "integer-projection",
      "text-projection",
      "reaction-saw-ready",
    ])

    await session._visorStop()
  }

  @Test @MainActor
  func `Stopping during a startup projection joins it and skips later work`() async {
    let channel = ObservationChannel(0)
    let handlerGate = HandlerGate()
    let stopStarted = OneShotSignal()
    let log = SessionLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { [handlerGate, log] _ in
            log.events.append("first-started")
            await handlerGate.wait()
            log.events.append("first-returned")
          },
          { [log] _ in log.events.append("second-ran") },
        ])._visorErase(),
    ])
    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await handlerGate.waitUntilStarted()

    let stop = Task { @MainActor in
      stopStarted.fire()
      await session._visorStop()
      log.events.append("stop-returned")
    }
    await stopStarted.wait()
    #expect(!log.events.contains("stop-returned"))

    handlerGate.open()
    await stop.value
    await #expect(throws: CancellationError.self) {
      try await startup.value
    }
    #expect(log.events == ["first-started", "first-returned", "stop-returned"])
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Stopping during an initial reaction joins it and skips later work`() async {
    let channel = ObservationChannel(0)
    let reactionGate = HandlerGate()
    let stopStarted = OneShotSignal()
    let log = SessionLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { [log] _ in log.events.append("projection") },
        ],
        initialReactions: [
          { [reactionGate, log] _ in
            log.events.append("reaction-started")
            await reactionGate.wait()
            log.events.append("reaction-returned")
          },
          { [log] _ in log.events.append("later-reaction-ran") },
        ])._visorErase(),
    ])
    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await reactionGate.waitUntilStarted()

    let stop = Task { @MainActor in
      stopStarted.fire()
      await session._visorStop()
      log.events.append("stop-returned")
    }
    await stopStarted.wait()
    #expect(!log.events.contains("stop-returned"))

    reactionGate.open()
    await stop.value
    await #expect(throws: CancellationError.self) {
      try await startup.value
    }
    #expect(log.events == [
      "projection",
      "reaction-started",
      "reaction-returned",
      "stop-returned",
    ])
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Cancellation at the readiness boundary tears down started workers`() async {
    let channel = ObservationChannel(0)
    let readinessGate = HandlerGate()
    let log = SessionLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [
            { [log] value in
              log.integer = value
              log.events.append("value-\(value)")
            },
          ])._visorErase(),
      ],
      _visorBeforeReady: {
        await readinessGate.wait()
      })
    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await readinessGate.waitUntilStarted()

    startup.cancel()
    readinessGate.open()

    await #expect(throws: CancellationError.self) {
      try await startup.value
    }
    #expect(!session._visorIsReady)
    #expect(channel.source._visorActiveSubscriptionCount == 0)

    channel.publish(1)
    #expect(log.events == ["value-0"])
  }

  @Test @MainActor
  func `Cancellation at the pause boundary skips the scoped operation`() async throws {
    let channel = ObservationChannel(0)
    let pauseGate = HandlerGate()
    let log = SessionLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [])._visorErase(),
      ],
      _visorBeforePauseOperation: {
        await pauseGate.wait()
      })
    try await session._visorStart()

    let pause = Task { @MainActor in
      try await session._visorWithPause {
        log.events.append("operation-ran")
      }
    }
    await pauseGate.waitUntilStarted()

    pause.cancel()
    pauseGate.open()

    await #expect(throws: CancellationError.self) {
      try await pause.value
    }
    #expect(log.events.isEmpty)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Stopping at the pause boundary skips the scoped operation`() async throws {
    let channel = ObservationChannel(0)
    let pauseGate = HandlerGate()
    let log = SessionLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [])._visorErase(),
      ],
      _visorBeforePauseOperation: {
        await pauseGate.wait()
      })
    try await session._visorStart()

    let pause = Task { @MainActor in
      try await session._visorWithPause {
        log.events.append("operation-ran")
      }
    }
    await pauseGate.waitUntilStarted()

    await session._visorStop()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
    pauseGate.open()

    await #expect(throws: CancellationError.self) {
      try await pause.value
    }
    await #expect(throws: CancellationError.self) {
      try await session._visorWaitForFailure()
    }
    #expect(log.events.isEmpty)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Stopping a draining pause is cancellation rather than source failure`() async throws {
    let channel = ObservationChannel(0)
    let handlerGate = HandlerGate()
    let stopStarted = OneShotSignal()
    let log = SessionLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { value in
            if value == 1 {
              await handlerGate.wait()
            }
          },
        ])._visorErase(),
    ])
    try await session._visorStart()

    channel.publish(1)
    let pause = Task { @MainActor in
      try await session._visorWithPause {
        log.events.append("operation-ran")
      }
    }
    await handlerGate.waitUntilStarted()

    let stop = Task { @MainActor in
      stopStarted.fire()
      await session._visorStop()
    }
    await stopStarted.wait()
    handlerGate.open()

    await #expect(throws: CancellationError.self) {
      try await pause.value
    }
    await stop.value
    await #expect(throws: CancellationError.self) {
      try await session._visorWaitForFailure()
    }
    #expect(log.events.isEmpty)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Startup fixes every target before an initial handler publishes`() async throws {
    let trigger = ObservationChannel(1)
    let dependent = ObservationChannel("old")
    let log = SessionLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: trigger.source,
        handlers: [],
        initialReactions: [
          { [log] value in
            log.events.append("trigger-\(value)")
            dependent.publish("new")
          },
        ])._visorErase(),
      _ObservationLane(
        source: dependent.source,
        handlers: [
          { [log] value in
            log.events.append("dependent-\(value)")
            log.text = value
          },
        ])._visorErase(),
    ])

    try await session._visorStart()

    #expect(log.events == ["dependent-old", "trigger-1"])
    #expect(log.text == "old")

    try await session._visorWithPause {
      #expect(log.text == "new")
    }
    await session._visorStop()
  }

  @Test @MainActor
  func `Whole-session fence pauses every source before draining`() async throws {
    let first = ObservationChannel(0)
    let second = ObservationChannel(
      "zero",
      groupedWith: first)
    let gate = HandlerGate()
    let log = SessionLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: first.source,
        handlers: [
          { [gate, log] value in
            if value == 1 {
              await gate.wait()
            }
            log.integer = value
          },
        ])._visorErase(),
      _ObservationLane(
        source: second.source,
        handlers: [
          { [log] value in log.text = value },
        ])._visorErase(),
    ])
    try await session._visorStart()

    first.publish(1)
    second.publish("one")
    let fence = Task { @MainActor in
      try await session._visorWithPause {
        #expect(log.integer == 1)
        #expect(log.text == "one")
      }
    }
    await gate.waitUntilStarted()

    second.publish("two")
    #expect(log.text == "one")

    gate.open()
    try await fence.value
    #expect(log.integer == 1)
    try await session._visorWithPause {
      #expect(log.text == "two")
    }
    await session._visorStop()
  }

  @Test @MainActor
  func `Heterogeneous startup failure rolls back every subscription`() async {
    let first = ObservationChannel(0)
    let failed = ObservationChannel("failed")
    failed._visorTerminate()
    let session = _ObservationSession(lanes: [
      _ObservationLane(source: first.source, handlers: [])._visorErase(),
      _ObservationLane(source: failed.source, handlers: [])._visorErase(),
    ])

    await #expect(throws: _ObservationSourceFailure.unexpectedTermination) {
      try await session._visorStart()
    }
    #expect(!session._visorIsReady)
    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(failed.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Active source failure revokes readiness and joins every lane`() async throws {
    let first = ObservationChannel(0)
    let second = ObservationChannel("ready")
    let log = SessionLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: first.source,
        handlers: [
          { [log] value in log.integer = value },
        ])._visorErase(),
      _ObservationLane(
        source: second.source,
        handlers: [
          { [log] value in log.text = value },
        ])._visorErase(),
    ])
    try await session._visorStart()

    first._visorTerminate()
    let failure = try await session._visorWaitForFailure()

    #expect(failure == .unexpectedTermination)
    #expect(!session._visorIsReady)
    await session._visorStop()
    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(second.source._visorActiveSubscriptionCount == 0)

    second.publish("later")
    #expect(log.text == "ready")
  }

  @Test @MainActor
  func `Cancelling a failure waiter does not outlive the session`() async throws {
    let channel = ObservationChannel(0)
    let session = _ObservationSession(lanes: [
      _ObservationLane(source: channel.source, handlers: [])._visorErase(),
    ])
    try await session._visorStart()

    let waiter = Task { @MainActor in
      try await session._visorWaitForFailure()
    }
    waiter.cancel()

    await #expect(throws: CancellationError.self) {
      try await waiter.value
    }
    await session._visorStop()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test @MainActor
  func `Throwing from a scoped pause tears down its session`() async throws {
    let channel = ObservationChannel(0)
    let session = _ObservationSession(lanes: [
      _ObservationLane(source: channel.source, handlers: [])._visorErase(),
    ])
    try await session._visorStart()

    struct PauseFailure: Error {}
    await #expect(throws: PauseFailure.self) {
      try await session._visorWithPause {
        throw PauseFailure()
      }
    }
    await session._visorStop()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
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
