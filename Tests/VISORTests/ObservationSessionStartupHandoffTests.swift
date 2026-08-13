import Testing
import VISOR
import VISORObservation

// Explicit deinitialisers in this file work around a Swift 6.2.4 release
// optimiser crash for explicitly MainActor-isolated test helpers.

@MainActor
private final class StartupHandoffSignal {
  private var continuation: CheckedContinuation<Void, Never>?
  private var didFire = false

  deinit {}

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
private final class StartupHandoffFailureLog {
  var failures: [_ObservationSourceFailure] = []

  deinit {}
}

@Suite("Observation session startup hand-off")
struct ObservationSessionStartupHandoffTests {
  @Test(.timeLimit(.minutes(1))) @MainActor
  func `Pause during startup hand-off is rejected without trapping`() async throws {
    let channel = ObservationChannel(0)
    let handoffGate = StartupHandoffSignal()
    let handoffStarted = StartupHandoffSignal()
    var operationCount = 0
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: [])._visorErase(),
      ],
      _visorAfterStartupHandoff: {
        handoffStarted.fire()
        await handoffGate.wait()
      })

    let startup = Task { @MainActor in
      try await session._visorStart()
    }
    await handoffStarted.wait()

    do {
      try await session._visorWithPause {
        operationCount += 1
      }
      Issue.record("Expected startup hand-off overlap to be rejected")
    } catch let failure as _ObservationSourceFailure {
      guard case .protocolViolation = failure else {
        Issue.record("Expected a protocol violation, got \(failure)")
        handoffGate.fire()
        return
      }
    }

    #expect(operationCount == 0)
    handoffGate.fire()
    try await startup.value
    #expect(session._visorIsReady)

    try await session._visorWithPause {
      operationCount += 1
    }
    #expect(operationCount == 1)
    await session._visorStop()
  }

  @Test @MainActor
  func `Worker failure at the startup hand-off cannot report ready`() async {
    let channel = ObservationChannel(0)
    let failureObserved = StartupHandoffSignal()
    let log = StartupHandoffFailureLog()
    let session = _ObservationSession(
      lanes: [
        _ObservationLane(
          source: channel.source,
          handlers: []
        )._visorErase(),
      ],
      _visorAfterStartupHandoff: {
        channel._visorTerminate()
        await failureObserved.wait()
      },
      _visorOnFailure: { failure in
        log.failures.append(failure)
        failureObserved.fire()
      })

    await #expect(throws: _ObservationSourceFailure.unexpectedTermination) {
      try await session._visorStart()
    }

    #expect(log.failures == [.unexpectedTermination])
    #expect(!session._visorIsReady)
    #expect(session._visorFailure == .unexpectedTermination)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }
}
