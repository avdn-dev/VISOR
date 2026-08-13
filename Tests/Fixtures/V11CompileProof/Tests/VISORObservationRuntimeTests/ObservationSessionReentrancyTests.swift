import Testing
import VISOR
import VISORObservation

@MainActor
private final class ReentrantSessionReference {
  weak var session: _ObservationSession?
}

@MainActor
private final class ReentrantLaneReference<Value: Sendable> {
  weak var lane: _ObservationLane<Value>?
}

@MainActor
private final class ReentrancySignal {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var didFire = false

  func wait() async {
    guard !didFire else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func fire() {
    guard !didFire else { return }
    didFire = true
    let waiters = waiters
    self.waiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }
}

@MainActor
private final class ReentrancyGate {
  private let started = ReentrancySignal()
  private var hasOpened = false
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    started.fire()
    guard !hasOpened else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    await started.wait()
  }

  func open() {
    hasOpened = true
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class ReentrancyLog {
  var values: [Int] = []
  var pauseOperationCount = 0
  var pauseWasRejected = false
  var waitWasRejected = false
  var checkpointWasRejected = false
  var unexpectedPauseFailure: String?
}

@Suite("V11 observation session re-entrancy")
struct ObservationSessionReentrancyTests {
  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Overlapping pauses reject the contender without poisoning the session`() async throws {
    let channel = ObservationChannel(0)
    let pauseGate = ReentrancyGate()
    var firstOperationCount = 0
    var secondOperationCount = 0
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [])._visorErase(),
      ],
      _visorBeforePauseDrain: { await pauseGate.wait() })
    try await session._visorStart()

    let firstPause = Task { @MainActor in
      try await session._visorWithPause {
        firstOperationCount += 1
      }
    }
    await pauseGate.waitUntilStarted()

    do {
      try await session._visorWithPause {
        secondOperationCount += 1
      }
      Issue.record("Expected the overlapping pause to be rejected")
    } catch let failure as _ObservationSourceFailure {
      guard case .protocolViolation = failure else {
        Issue.record("Expected a protocol violation, got \(failure)")
        pauseGate.open()
        return
      }
    }

    #expect(firstOperationCount == 0)
    #expect(secondOperationCount == 0)
    #expect(!session._visorIsReady)

    pauseGate.open()
    try await firstPause.value

    #expect(firstOperationCount == 1)
    #expect(secondOperationCount == 0)
    #expect(session._visorIsReady)

    try await session._visorWithPause {}
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Inherited handler task requests its own stop without self-joining`() async throws {
    let channel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let requestReturned = ReentrancySignal()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { [reference, requestReturned] value in
            guard value == 1, let session = reference.session else { return }
            let request = Task { @MainActor in
              await session._visorStop()
            }
            await request.value
            requestReturned.fire()
          },
        ])._visorErase(),
    ])
    reference.session = session
    try await session._visorStart()

    channel.publish(1)
    await requestReturned.wait()

    #expect(!session._visorIsReady)
    await session._visorStop()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Handler pause fails before changing its own session`() async throws {
    let channel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let pauseReturned = ReentrancySignal()
    let log = ReentrancyLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { [reference, pauseReturned, log] value in
            log.values.append(value)
            guard value == 1, let session = reference.session else { return }
            do {
              try await session._visorWithPause {
                log.pauseOperationCount += 1
              }
            } catch let failure as _ObservationSourceFailure {
              if case .protocolViolation = failure {
                log.pauseWasRejected = true
              } else {
                log.unexpectedPauseFailure = String(describing: failure)
              }
            } catch {
              log.unexpectedPauseFailure = String(describing: error)
            }
            pauseReturned.fire()
          },
        ])._visorErase(),
    ])
    reference.session = session
    try await session._visorStart()

    channel.publish(1)
    await pauseReturned.wait()

    #expect(log.pauseWasRejected)
    #expect(log.unexpectedPauseFailure == nil)
    #expect(log.pauseOperationCount == 0)
    #expect(session._visorIsReady)

    channel.publish(2)
    try await session._visorWithPause {}
    #expect(log.values == [0, 1, 2])

    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Handler cannot wait for its own session failure`() async throws {
    let channel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let waitReturned = ReentrancySignal()
    let log = ReentrancyLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { [reference, waitReturned, log] value in
            log.values.append(value)
            guard value == 1, let session = reference.session else { return }
            do {
              _ = try await session._visorWaitForFailure()
            } catch let failure as _ObservationSourceFailure {
              if case .protocolViolation = failure {
                log.waitWasRejected = true
              } else {
                log.unexpectedPauseFailure = String(describing: failure)
              }
            } catch {
              log.unexpectedPauseFailure = String(describing: error)
            }
            waitReturned.fire()
          },
        ])._visorErase(),
    ])
    reference.session = session
    try await session._visorStart()

    channel.publish(1)
    await waitReturned.wait()

    #expect(log.waitWasRejected)
    #expect(log.unexpectedPauseFailure == nil)
    #expect(session._visorIsReady)

    channel.publish(2)
    try await session._visorWithPause {}
    #expect(log.values == [0, 1, 2])

    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Before-ready hook requests stop without joining startup`() async {
    let channel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let requestReturned = ReentrancySignal()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [])._visorErase(),
      ],
      _visorBeforeReady: { [reference, requestReturned] in
        guard let session = reference.session else { return }
        await session._visorStop()
        requestReturned.fire()
      })
    reference.session = session

    await #expect(throws: CancellationError.self) {
      try await session._visorStart()
    }

    #expect(requestReturned.didFire)
    #expect(!session._visorIsReady)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Initial reaction requests stop without awaiting its startup task`() async {
    let channel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let requestReturned = ReentrancySignal()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [],
        initialReactions: [
          { [reference, requestReturned] _ in
            guard let session = reference.session else { return }
            await session._visorStop()
            requestReturned.fire()
          },
        ])._visorErase(),
    ])
    reference.session = session

    await #expect(throws: CancellationError.self) {
      try await session._visorStart()
    }

    #expect(requestReturned.didFire)
    #expect(!session._visorIsReady)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Handler still joins a different session stop`() async throws {
    let otherChannel = ObservationChannel(0)
    let otherGate = ReentrancyGate()
    let otherSession = _ObservationSession(lanes: [
      _ObservationLane(
        source: otherChannel.source,
        handlers: [
          { [otherGate] value in
            if value == 1 {
              await otherGate.wait()
            }
          },
        ])._visorErase(),
    ])
    try await otherSession._visorStart()
    otherChannel.publish(1)
    await otherGate.waitUntilStarted()

    let channel = ObservationChannel(0)
    let stopStarted = ReentrancySignal()
    let stopReturned = ReentrancySignal()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { [otherSession, stopStarted, stopReturned] value in
            guard value == 1 else { return }
            stopStarted.fire()
            await otherSession._visorStop()
            stopReturned.fire()
          },
        ])._visorErase(),
    ])
    try await session._visorStart()

    channel.publish(1)
    await stopStarted.wait()
    #expect(!stopReturned.didFire)

    otherGate.open()
    await stopReturned.wait()
    #expect(!otherSession._visorIsReady)
    #expect(otherChannel.source._visorActiveSubscriptionCount == 0)

    try await session._visorWithPause {}
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Standalone handler cannot checkpoint its own lane`() async throws {
    let channel = ObservationChannel(0)
    let reference = ReentrantLaneReference<Int>()
    let checkpointReturned = ReentrancySignal()
    let log = ReentrancyLog()
    let lane = _ObservationLane(
      source: channel.source,
      handlers: [
        { [reference, checkpointReturned, log] value in
          log.values.append(value)
          guard value == 1, let lane = reference.lane else { return }
          do {
            _ = try await lane._visorCheckpointAndPause()
          } catch let failure as _ObservationSourceFailure {
            if case .protocolViolation = failure {
              log.checkpointWasRejected = true
            } else {
              log.unexpectedPauseFailure = String(describing: failure)
            }
          } catch {
            log.unexpectedPauseFailure = String(describing: error)
          }
          checkpointReturned.fire()
        },
      ])
    reference.lane = lane
    let prepared = try lane._visorPrepare()
    try await prepared._visorActivate()

    channel.publish(1)
    await checkpointReturned.wait()

    #expect(log.checkpointWasRejected)
    #expect(log.unexpectedPauseFailure == nil)
    let checkpoint = try await lane._visorCheckpointAndPause()
    #expect(log.values == [0, 1])
    try lane._visorResume(after: checkpoint)

    channel.publish(2)
    let finalCheckpoint = try await lane._visorCheckpointAndPause()
    #expect(log.values == [0, 1, 2])
    try lane._visorResume(after: finalCheckpoint)
    await lane._visorCancelAndJoin()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Standalone handler requests cancellation without joining itself`() async throws {
    let channel = ObservationChannel(0)
    let reference = ReentrantLaneReference<Int>()
    let requestReturned = ReentrancySignal()
    let lane = _ObservationLane(
      source: channel.source,
      handlers: [
        { [reference, requestReturned] value in
          guard value == 1, let lane = reference.lane else { return }
          await lane._visorCancelAndJoin()
          requestReturned.fire()
        },
      ])
    reference.lane = lane
    let prepared = try lane._visorPrepare()
    try await prepared._visorActivate()

    channel.publish(1)
    await requestReturned.wait()
    await lane._visorCancelAndJoin()

    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Unstructured descendant joins after its handler returns`() async throws {
    let firstChannel = ObservationChannel(0)
    let secondChannel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let descendantRelease = ReentrancySignal()
    let descendantCreated = ReentrancySignal()
    let laterRevisionHandled = ReentrancySignal()
    let stopStarted = ReentrancySignal()
    let stopReturned = ReentrancySignal()
    let otherGate = ReentrancyGate()

    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: firstChannel.source,
        handlers: [
          { [
            reference,
            descendantRelease,
            descendantCreated,
            laterRevisionHandled,
            stopStarted,
            stopReturned,
          ] value in
            if value == 1 {
              Task { @MainActor in
                await descendantRelease.wait()
                guard let session = reference.session else { return }
                stopStarted.fire()
                await session._visorStop()
                stopReturned.fire()
              }
              descendantCreated.fire()
            } else if value == 2 {
              laterRevisionHandled.fire()
            }
          },
        ])._visorErase(),
      _ObservationLane(
        source: secondChannel.source,
        handlers: [
          { [otherGate] value in
            if value == 1 {
              await otherGate.wait()
            }
          },
        ])._visorErase(),
    ])
    reference.session = session
    try await session._visorStart()

    secondChannel.publish(1)
    await otherGate.waitUntilStarted()
    firstChannel.publish(1)
    await descendantCreated.wait()
    firstChannel.publish(2)
    await laterRevisionHandled.wait()

    descendantRelease.fire()
    await stopStarted.wait()
    #expect(!stopReturned.didFire)

    otherGate.open()
    await stopReturned.wait()
    #expect(!session._visorIsReady)
    #expect(firstChannel.source._visorActiveSubscriptionCount == 0)
    #expect(secondChannel.source._visorActiveSubscriptionCount == 0)
  }
}
