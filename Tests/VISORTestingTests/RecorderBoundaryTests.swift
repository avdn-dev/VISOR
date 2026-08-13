import Observation
import os
import Testing
import VISORTesting

private final class RecorderBoundaryDescriptionCounter: Sendable {
  private let storage = OSAllocatedUnfairLock(initialState: 0)

  var value: Int {
    storage.withLock { $0 }
  }

  func increment() {
    storage.withLock { $0 += 1 }
  }
}

private final class RecorderBoundaryPayload: CustomStringConvertible {
  private let counter: RecorderBoundaryDescriptionCounter
  private let value: Int

  init(
    value: Int,
    counter: RecorderBoundaryDescriptionCounter
  ) {
    self.value = value
    self.counter = counter
  }

  var description: String {
    counter.increment()
    return "RecorderBoundaryPayload(\(value))"
  }
}

@MainActor
@Observable
@ViewModel
private final class NilRecorderProbeViewModel {
  final class State {
    var payload: RecorderBoundaryPayload

    init(payload: RecorderBoundaryPayload) {
      self.payload = payload
    }
  }

  let state: State

  init(payload: RecorderBoundaryPayload) {
    state = State(payload: payload)
  }
}

@MainActor
private final class RecorderBoundaryRendezvous {
  private var arrivalCount = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private let onBothArrived: @MainActor () -> Void

  init(onBothArrived: @escaping @MainActor () -> Void) {
    self.onBothArrived = onBothArrived
  }

  deinit {}

  func arriveAndWait() async {
    arrivalCount += 1
    precondition(arrivalCount <= 2)

    if arrivalCount == 2 {
      onBothArrived()
      let waiters = waiters
      self.waiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

@MainActor
private final class RecorderBoundaryResults {
  var activeObservationCount = 0
  var firstRawCommitCount = 0
  var secondRawCommitCount = 0
  var firstInfrastructureIssues: [String] = []
  var secondInfrastructureIssues: [String] = []

  deinit {}
}

@Suite("Per-State recorder boundary")
struct RecorderBoundaryTests {
  @Test
  @MainActor
  func `Distinct State identities sharing a service keep independent concurrent histories`() async throws {
    let service = TestingService()
    let first = TestingViewModel(service: service)
    let second = TestingViewModel(service: service)
    let results = RecorderBoundaryResults()
    let rendezvous = RecorderBoundaryRendezvous {
      results.activeObservationCount = service.activeObservationCount
    }

    let firstScope = Task { @MainActor in
      try await _observeWithJournalPolicyForProof(
        first,
        logicalCommitLimit: 8,
        issueRecorder: { message, _ in
          results.firstInfrastructureIssues.append(message)
        }
      ) { test in
        await rendezvous.arriveAndWait()
        await test.perform(.setCount(11))
        results.firstRawCommitCount = test._rawCommitCount(\.count)
        test.expect(\.count, hasExactChanges: [11])
      }
    }
    let secondScope = Task { @MainActor in
      try await _observeWithJournalPolicyForProof(
        second,
        logicalCommitLimit: 8,
        issueRecorder: { message, _ in
          results.secondInfrastructureIssues.append(message)
        }
      ) { test in
        await rendezvous.arriveAndWait()
        await test.perform(.setCount(22))
        results.secondRawCommitCount = test._rawCommitCount(\.count)
        test.expect(\.count, hasExactChanges: [22])
      }
    }

    try await firstScope.value
    try await secondScope.value

    #expect(results.activeObservationCount == 2)
    #expect(results.firstRawCommitCount == 1)
    #expect(results.secondRawCommitCount == 1)
    #expect(results.firstInfrastructureIssues.isEmpty)
    #expect(results.secondInfrastructureIssues.isEmpty)
    #expect(first.state.count == 11)
    #expect(second.state.count == 22)
    #expect(service.activeObservationCount == 0)
  }

  @Test
  @MainActor
  func `Nested same-State observe is rejected without disturbing the first scope`() async throws {
    let service = TestingService()
    let sut = TestingViewModel(service: service)
    var firstInfrastructureIssues: [String] = []
    var secondInfrastructureIssues: [String] = []
    var secondBodyEntered = false

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8,
      issueRecorder: { message, _ in
        firstInfrastructureIssues.append(message)
      }
    ) { firstTest in
      try await _observeWithJournalPolicyForProof(
        sut,
        logicalCommitLimit: 8,
        issueRecorder: { message, _ in
          secondInfrastructureIssues.append(message)
        }
      ) { _ in
        secondBodyEntered = true
      }

      #expect(!secondBodyEntered)
      #expect(secondInfrastructureIssues == [
        "This State already has an active observation scope"
      ])
      #expect(service.activeObservationCount == 1)

      await firstTest.perform(.setCount(7))
      #expect(firstTest._rawCommitCount(\.count) == 1)
      firstTest.expect(\.count, hasExactChanges: [7])
    }

    #expect(firstInfrastructureIssues.isEmpty)
    #expect(sut.state.count == 7)
    #expect(service.activeObservationCount == 0)
  }

  @Test
  @MainActor
  func `Nil recorder retires the old reference without describing a test snapshot`() {
    let descriptionCounter = RecorderBoundaryDescriptionCounter()
    var initialPayload: RecorderBoundaryPayload? = RecorderBoundaryPayload(
      value: 1,
      counter: descriptionCounter)
    let retiredPayload = WeakReference(initialPayload)
    let sut = NilRecorderProbeViewModel(payload: initialPayload!)
    let replacement = RecorderBoundaryPayload(
      value: 2,
      counter: descriptionCounter)

    initialPayload = nil
    #expect(retiredPayload.value != nil)
    #expect(sut.state._visorMutationRecorder == nil)

    sut.state.payload = replacement

    #expect(descriptionCounter.value == 0)
    #expect(retiredPayload.value == nil)
    #expect(sut.state.payload === replacement)
  }
}
