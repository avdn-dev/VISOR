import Testing
import VISOR
import VISORObservation
import VISORTesting

// MARK: - ObservationSessionContractLog

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

@MainActor
private final class ObservationSessionContractLog {

  // MARK: Lifecycle

  deinit { }

  // MARK: Internal

  var events = [String]()
  var integer = -1
  var text = ""

}

// MARK: - ObservationSessionContractTests

@Suite("Observation session contract")
struct ObservationSessionContractTests {
  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Heterogeneous readiness arms every lane before projection`() async throws {
    let integer = ObservationChannel(1)
    let text = ObservationChannel("ready")
    let log = ObservationSessionContractLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: integer.source,
        handlers: [{ value in
          #expect(integer.source._visorActiveSubscriptionCount == 1)
          #expect(text.source._visorActiveSubscriptionCount == 1)
          log.events.append("integer")
          log.integer = value
        }],
      )._visorErase(),
      _ObservationLane(
        source: text.source,
        handlers: [{ value in
          log.events.append("text")
          log.text = value
        }],
      )._visorErase(),
    ])

    try await session._visorStart()

    #expect(session._visorIsReady)
    #expect(log.events == ["integer", "text"])
    #expect(log.integer == 1)
    #expect(log.text == "ready")

    await session._visorStop()
    #expect(integer.source._visorActiveSubscriptionCount == 0)
    #expect(text.source._visorActiveSubscriptionCount == 0)
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Every projection precedes every initial reaction`() async throws {
    let integer = ObservationChannel(1)
    let text = ObservationChannel("ready")
    let log = ObservationSessionContractLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: integer.source,
        handlers: [{ value in
          log.integer = value
          log.events.append("integer-projection")
        }],
        initialReactions: [{ _ in
          log.events.append("reaction-saw-\(log.text)")
        }],
      )._visorErase(),
      _ObservationLane(
        source: text.source,
        handlers: [{ value in
          log.text = value
          log.events.append("text-projection")
        }],
      )._visorErase(),
    ])

    try await session._visorStart()

    #expect(log.events == [
      "integer-projection",
      "text-projection",
      "reaction-saw-ready",
    ])
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Startup fixes every target before a reaction publishes`() async throws {
    let trigger = ObservationChannel(1)
    let dependent = ObservationChannel("old")
    let log = ObservationSessionContractLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: trigger.source,
        handlers: [],
        initialReactions: [{ value in
          log.events.append("trigger-\(value)")
          dependent.publish("new")
        }],
      )._visorErase(),
      _ObservationLane(
        source: dependent.source,
        handlers: [{ value in
          log.events.append("dependent-\(value)")
          log.text = value
        }],
      )._visorErase(),
    ])

    try await session._visorStart()

    #expect(log.events == ["dependent-old", "trigger-1"])
    #expect(log.text == "old")
    try await session._visorWithPause {
      #expect(log.text == "new")
    }
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Whole-session fence pauses every lane before draining`() async throws {
    let integer = ObservationChannel(0)
    let text = ObservationChannel("zero", groupedWith: integer)
    let gate = ControllableOperation<Void, Never>()
    let log = ObservationSessionContractLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: integer.source,
        handlers: [{ value in
          if value == 1 { await gate.run(gate.prepare()) }
          log.integer = value
        }],
      )._visorErase(),
      _ObservationLane(
        source: text.source,
        handlers: [{ value in log.text = value }],
      )._visorErase(),
    ])
    try await session._visorStart()

    integer.publish(1)
    text.publish("one")
    let fence = Task { @MainActor in
      try await session._visorWithPause {
        #expect(log.integer == 1)
        #expect(log.text == "one")
      }
    }
    await gate.waitUntilStarted()

    text.publish("two")
    #expect(log.text == "one")
    gate.setTerminalResult(.success(()))
    try await fence.value

    try await session._visorWithPause {
      #expect(log.text == "two")
    }
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Heterogeneous startup failure rolls back every lane`() async {
    let healthy = ObservationChannel(0)
    let failed = ObservationChannel("failed")
    failed._visorTerminate()
    let session = _ObservationSession(lanes: [
      _ObservationLane(source: healthy.source, handlers: [])._visorErase(),
      _ObservationLane(source: failed.source, handlers: [])._visorErase(),
    ])

    await #expect(throws: _ObservationSourceFailure.unexpectedTermination) {
      try await session._visorStart()
    }
    #expect(!session._visorIsReady)
    #expect(healthy.source._visorActiveSubscriptionCount == 0)
    #expect(failed.source._visorActiveSubscriptionCount == 0)
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Active source failure revokes readiness and joins every lane`() async throws {
    let integer = ObservationChannel(0)
    let text = ObservationChannel("ready")
    let log = ObservationSessionContractLog()
    let session = _ObservationSession(lanes: [
      _ObservationLane(
        source: integer.source,
        handlers: [{ value in log.integer = value }],
      )._visorErase(),
      _ObservationLane(
        source: text.source,
        handlers: [{ value in log.text = value }],
      )._visorErase(),
    ])
    try await session._visorStart()

    integer._visorTerminate()
    let failure = try await session._visorWaitForFailure()

    #expect(failure == .unexpectedTermination)
    #expect(!session._visorIsReady)
    await session._visorStop()
    #expect(integer.source._visorActiveSubscriptionCount == 0)
    #expect(text.source._visorActiveSubscriptionCount == 0)

    text.publish("later")
    #expect(log.text == "ready")
  }

  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Empty recipe set becomes ready and stops cleanly`() async throws {
    let session = _ObservationSession(recipes: [])

    try await session._visorStart()
    #expect(session._visorIsReady)

    try await session._visorWithPause { }
    #expect(session._visorIsReady)

    await session._visorStop()
    #expect(session._visorIsStopped)
  }
}
