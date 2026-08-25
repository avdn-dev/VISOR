import Testing
import VISORTesting

// MARK: - TestActionError

private enum TestActionError: Error {
  case expected
}

// MARK: - SourceFencedObservationTests

@Suite("Source-fenced observation")
struct SourceFencedObservationTests {
  @Test
  @MainActor
  func `Readiness precedes the body and perform closes on a finite frontier`() async throws {
    let service = TestingService(1)
    let gate = ControllableOperation<Void, Never>()
    let sut = TestingViewModel(service: service, reactionGate: gate)

    #expect(sut.state.sourceValue == -1)

    try await _observeForProof(
      sut,
      beforePauseDrain: {
        if service.source.currentSnapshot().value == 10 {
          service.publishSynchronously(11)
        }
      },
    ) { test in
      #expect(service.activeObservationCount == 1)
      #expect(sut.state.sourceValue == 1)
      #expect(sut.state.reactedValue == 1)

      let fencedAction = Task { @MainActor in
        await test.perform {
          await service.publish(10)
        }
      }

      try await gate.waitUntilStarted()
      #expect(sut.state.sourceValue == 10)
      #expect(sut.state.reactedValue == 1)
      gate.setTerminalResult(.success(()))
      await fencedAction.value

      test.expect(\.sourceValue, hasExactChanges: [10])
      test.expect(\.reactedValue, hasExactChanges: [10])

      // Revision 11 was published after the previous closing checkpoint. The
      // next opening fence reconciles it before taking this action's baseline.
      await test.perform { }
      #expect(sut.state.sourceValue == 11)
      #expect(sut.state.reactedValue == 11)
      test.expect(\.sourceValue, hasExactChanges: [])
      test.expect(\.reactedValue, hasExactChanges: [])
    }

    #expect(service.activeObservationCount == 0)
  }

  @Test
  @MainActor
  func `Perform overloads return values and isolate successive windows`() async throws {
    let sut = TestingViewModel()

    try await observe(sut) { test in
      await test.perform(.setCount(1))
      test.expect(\.count, hasExactChanges: [1])

      await test.perform {
        sut.state.count = 2
        sut.state.count = 2
        sut.state.count = 3
      }
      test.expect(\.count, hasExactChanges: [2, 3])
      test.expect(\.count, alwaysSatisfies: { (1...3).contains($0) })

      await #expect(throws: TestActionError.expected) {
        try await test.perform {
          sut.state.status = "throwing"
          throw TestActionError.expected
        }
      }
      test.expect(\.status, hasExactChanges: ["throwing"])

      let result = try await test.perform {
        sut.state.status = "returned"
        return 42
      }
      #expect(result == 42)
      test.expect(\.status, hasExactChanges: ["returned"])

      await test.perform { }
      test.expect(\.count, hasExactChanges: [])
      test.expect(\.status, hasExactChanges: [])
    }
  }
}
