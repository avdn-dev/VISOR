import RootTestingModelsNonisolated
import RootTestingSupport
import Testing
import VISORTesting

@Suite("Root VISORTesting from a nonisolated target")
struct RootTestingBoundaryTests {
  @Test
  func `Public concurrency waits cooperate with downstream cancellation`() async throws {
    let counter = TestEventCounter()
    let counterWaitStarted = TestEventCounter()
    let counterWait = Task {
      counterWaitStarted.record()
      try await counter.wait()
    }
    try await counterWaitStarted.wait()
    await Task.yield()
    counterWait.cancel()

    await #expect(throws: CancellationError.self) {
      try await counterWait.value
    }

    counter.record()
    try await counter.wait()

    let barrier = TestBarrier(participantCount: 2)
    let firstParticipant = Task {
      try await barrier.arriveAndWait()
    }
    try await barrier.waitUntilArrived(1)
    firstParticipant.cancel()

    await #expect(throws: CancellationError.self) {
      try await firstParticipant.value
    }

    try await barrier.arriveAndWait()
    #expect(await barrier.isOpen)
    #expect(await barrier.arrivalCount == 2)
  }

  @Test
  func `Public observation errors can be handled downstream`() {
    let error = ObservationTestError.resultUnavailable

    #expect(error.errorDescription?.contains("State window was unavailable") == true)
  }

  @Test
  @MainActor
  func `The generated model supports source-fenced public testing APIs`() async throws {
    let service = RootTestingService(initialValue: 1)
    let sut = NonisolatedRootTestingViewModel(service: service)

    try await observe(sut, maximumCommitCountPerAction: 4) { test in
      #expect(sut.state.sourceValue == 1)
      #expect(sut.state.reactedValue == 1)

      await test.perform(.setCount(2))
      test.expect(\.count, hasExactChanges: [2])
      test.expect(\.count, alwaysSatisfies: { (0...2).contains($0) })

      await test.perform {
        service.publish(3)
      }
      test.expect(\.sourceValue, hasExactChanges: [3])
      test.expect(\.reactedValue, alwaysSatisfies: { $0 > 0 })
    }
  }
}
