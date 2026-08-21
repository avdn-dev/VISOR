import Testing
import VISOR
import VISORObservation
import VISORTesting

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

@MainActor
private final class ReentrantSessionReference {
  weak var session: _ObservationSession?

  deinit {}
}

@MainActor
private final class ReentrantLaneReference<Value: Sendable> {
  weak var lane: _ObservationLane<Value>?

  deinit {}
}

@MainActor
private final class ReentrancyLog {
  var values: [Int] = []
  var pauseOperationCount = 0
  var pauseWasRejected = false
  var waitWasRejected = false
  var checkpointWasRejected = false
  var unexpectedPauseFailure: String?

  deinit {}
}

@Suite("V11 observation session re-entrancy")
struct ObservationSessionReentrancyTests {
  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Overlapping pauses reject the contender without poisoning the session`() async throws {
    let channel = ObservationChannel(0)
    let pauseGate = ControllableOperation<Void, Never>()
    var firstOperationCount = 0
    var secondOperationCount = 0
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [])._visorErase(),
      ],
      _visorBeforePauseDrain: { await pauseGate.run() })
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
        pauseGate.finish()
        return
      }
    }

    #expect(firstOperationCount == 0)
    #expect(secondOperationCount == 0)
    #expect(session._visorIsReady == false)

    pauseGate.finish()
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
    let requestReturned = TestEventCounter()
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
            requestReturned.record()
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
    let pauseReturned = TestEventCounter()
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
            pauseReturned.record()
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
    let waitReturned = TestEventCounter()
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
            waitReturned.record()
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
    let requestReturned = TestEventCounter()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [])._visorErase(),
      ],
      _visorBeforeReady: { [reference, requestReturned] in
        guard let session = reference.session else { return }
        await session._visorStop()
            requestReturned.record()
      })
    reference.session = session

    await #expect(throws: CancellationError.self) {
      try await session._visorStart()
    }

    #expect(requestReturned.count == 1)
    #expect(!session._visorIsReady)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Initial reaction requests stop without awaiting its startup task`() async {
    let channel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let requestReturned = TestEventCounter()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [],
        initialReactions: [
          { [reference, requestReturned] _ in
            guard let session = reference.session else { return }
            await session._visorStop()
            requestReturned.record()
          },
        ])._visorErase(),
    ])
    reference.session = session

    await #expect(throws: CancellationError.self) {
      try await session._visorStart()
    }

    #expect(requestReturned.count == 1)
    #expect(!session._visorIsReady)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Handler still joins a different session stop`() async throws {
    let otherChannel = ObservationChannel(0)
    let otherGate = ControllableOperation<Void, Never>()
    let otherSession = _ObservationSession(lanes: [
      _ObservationLane(
        source: otherChannel.source,
        handlers: [
          { [otherGate] value in
            if value == 1 {
              await otherGate.run()
            }
          },
        ])._visorErase(),
    ])
    try await otherSession._visorStart()
    otherChannel.publish(1)
    await otherGate.waitUntilStarted()

    let channel = ObservationChannel(0)
    let stopStarted = TestEventCounter()
    let stopReturned = TestEventCounter()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: channel.source,
        handlers: [
          { [otherSession, stopStarted, stopReturned] value in
            guard value == 1 else { return }
            stopStarted.record()
            await otherSession._visorStop()
            stopReturned.record()
          },
        ])._visorErase(),
    ])
    try await session._visorStart()

    channel.publish(1)
    await stopStarted.wait()
    #expect(stopReturned.count == 0)

    otherGate.finish()
    await stopReturned.wait()
    #expect(!otherSession._visorIsReady)
    #expect(otherChannel.source._visorActiveSubscriptionCount == 0)

    try await session._visorWithPause {}
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Handler cannot checkpoint its own lane`() async throws {
    let channel = ObservationChannel(0)
    let reference = ReentrantLaneReference<Int>()
    let checkpointReturned = TestEventCounter()
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
            checkpointReturned.record()
        },
      ])
    reference.lane = lane
    let session = _ObservationSession(lanes: [lane._visorErase()])
    try await session._visorStart()

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
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Handler requests lane cancellation without joining itself`() async throws {
    let channel = ObservationChannel(0)
    let reference = ReentrantLaneReference<Int>()
    let requestReturned = TestEventCounter()
    let lane = _ObservationLane(
      source: channel.source,
      handlers: [
        { [reference, requestReturned] value in
          guard value == 1, let lane = reference.lane else { return }
          await lane._visorCancelAndJoin()
        requestReturned.record()
        },
      ])
    reference.lane = lane
    let session = _ObservationSession(lanes: [lane._visorErase()])
    try await session._visorStart()

    channel.publish(1)
    await requestReturned.wait()
    await session._visorStop()

    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Unstructured descendant joins after its handler returns`() async throws {
    let firstChannel = ObservationChannel(0)
    let secondChannel = ObservationChannel(0)
    let reference = ReentrantSessionReference()
    let descendantRelease = TestEventCounter()
    let descendantCreated = TestEventCounter()
    let laterRevisionHandled = TestEventCounter()
    let stopStarted = TestEventCounter()
    let stopReturned = TestEventCounter()
    let otherGate = ControllableOperation<Void, Never>()

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
                stopStarted.record()
                await session._visorStop()
                stopReturned.record()
              }
              descendantCreated.record()
            } else if value == 2 {
              laterRevisionHandled.record()
            }
          },
        ])._visorErase(),
      _ObservationLane(
        source: secondChannel.source,
        handlers: [
          { [otherGate] value in
            if value == 1 {
              await otherGate.run()
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

    descendantRelease.record()
    await stopStarted.wait()
    #expect(stopReturned.count == 0)

    otherGate.finish()
    await stopReturned.wait()
    #expect(!session._visorIsReady)
    #expect(firstChannel.source._visorActiveSubscriptionCount == 0)
    #expect(secondChannel.source._visorActiveSubscriptionCount == 0)
  }
}
