import Testing
import VISORTesting

private enum LifecycleError: Error {
  case body
}

@Suite("Observation lifecycle")
struct ObservationLifecycleTests {
  @Test
  @MainActor
  func `State identity swap fails the next opening and requests teardown once`() async throws {
    let service = TestingService(1)
    let sut = SwappableTestingViewModel(service: service)
    var infrastructureIssues: [(String, SourceLocation)] = []
    var actionRan = false
    var laterActionRan = false
    let performLocation = SourceLocation(
      fileID: "ObservationLifecycleTests/state-identity",
      filePath: "/ObservationLifecycleTests/state-identity.swift",
      line: 456,
      column: 7)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8_192,
      issueRecorder: { message, location in
        infrastructureIssues.append((message, location))
      }
    ) { test in
      #expect(service.activeObservationCount == 1)
      #expect(sut.state.sourceValue == 1)

      sut.replaceState()
      await test.perform(
        { actionRan = true },
        sourceLocation: performLocation)

      #expect(!actionRan)
      #expect(infrastructureIssues.count == 1)
      #expect(infrastructureIssues.first?.0 ==
        "VISOR failed while opening an action window: stateIdentityChanged")
      #expect(infrastructureIssues.first?.1 == performLocation)
      // Identity loss poisons the harness and must synchronously revoke the
      // old generation before control returns from the rejected perform.
      #expect(service.activeObservationCount == 0)

      await test.perform {
        laterActionRan = true
      }
      #expect(!laterActionRan)
      #expect(infrastructureIssues.count == 1)
    }

    #expect(service.activeObservationCount == 0)
    #expect(infrastructureIssues.count == 1)
  }

  @Test
  @MainActor
  func `Startup failure records once and does not enter the body`() async throws {
    let service = TestingService()
    service.terminate()
    let sut = TestingViewModel(service: service)
    var issues: [(message: String, location: SourceLocation)] = []
    var enteredBody = false
    let observeLocation = SourceLocation(
      fileID: "ObservationLifecycleTests/startup",
      filePath: "/ObservationLifecycleTests/startup.swift",
      line: 404,
      column: 4)

    try await _observeWithJournalPolicyForProof(
      sut,
      sourceLocation: observeLocation,
      logicalCommitLimit: 8_192,
      issueRecorder: { message, location in
        issues.append((message, location))
      }
    ) { _ in
      enteredBody = true
    }

    #expect(issues.count == 1)
    #expect(issues.first?.message ==
      "VISOR failed while starting observation: unexpectedTermination")
    #expect(issues.first?.location == observeLocation)
    #expect(!enteredBody)
    #expect(service.activeObservationCount == 0)
    #expect(sut.state._visorMutationRecorder == nil)
  }

  @Test
  @MainActor
  func `Runtime source failure poisons the window and suppresses later work`() async throws {
    let service = TestingService()
    let sut = TestingViewModel(service: service)
    var issues: [(message: String, location: SourceLocation)] = []
    var laterOperationRan = false
    let failureLocation = SourceLocation(
      fileID: "ObservationLifecycleTests/runtime",
      filePath: "/ObservationLifecycleTests/runtime.swift",
      line: 505,
      column: 5)
    let suppressedExpectationLocation = SourceLocation(
      fileID: "ObservationLifecycleTests/suppressed-expectation",
      filePath: "/ObservationLifecycleTests/suppressed-expectation.swift",
      line: 506,
      column: 6)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8_192,
      issueRecorder: { message, location in
        issues.append((message, location))
      }
    ) { test in
      await test.perform(
        { service.terminate() },
        sourceLocation: failureLocation)
      test.expect(
        \.sourceValue,
        hasExactChanges: [],
        sourceLocation: suppressedExpectationLocation)
      await test.perform {
        laterOperationRan = true
      }
    }

    #expect(issues.count == 1)
    #expect(issues.first?.message ==
      "VISOR failed while closing an action window: unexpectedTermination")
    #expect(issues.first?.location == failureLocation)
    #expect(!laterOperationRan)
    #expect(service.activeObservationCount == 0)
    #expect(sut.state._visorMutationRecorder == nil)
  }

  @Test
  @MainActor
  func `Cancellation abandons the window and joins the source session`() async {
    let service = TestingService()
    let sut = TestingViewModel(service: service)
    let gate = TestingGate()

    let task = Task { @MainActor in
      try await observe(sut) { test in
        await test.perform {
          await gate.suspend()
        }
      }
    }

    await gate.waitUntilStarted()
    task.cancel()
    gate.open()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(service.activeObservationCount == 0)
  }

  @Test
  @MainActor
  func `Escaped handle releases its graph and diagnoses stale use`() async throws {
    let service = TestingService()
    var sut: TestingViewModel? = TestingViewModel(service: service)
    let weakSUT = WeakReference(sut)
    var escaped: ObservationTest<TestingViewModel>?
    var issues: [(message: String, location: SourceLocation)] = []
    var staleOperationRan = false
    let staleLocation = SourceLocation(
      fileID: "ObservationLifecycleTests/stale-handle",
      filePath: "/ObservationLifecycleTests/stale-handle.swift",
      line: 606,
      column: 6)

    try await _observeWithJournalPolicyForProof(
      sut!,
      logicalCommitLimit: 8_192,
      issueRecorder: { message, location in
        issues.append((message, location))
      }
    ) { test in
      escaped = test
    }

    sut = nil
    #expect(weakSUT.value == nil)
    #expect(service.activeObservationCount == 0)
    #expect(issues.isEmpty)

    await escaped?.perform(
      { staleOperationRan = true },
      sourceLocation: staleLocation)

    #expect(issues.count == 1)
    #expect(issues.first?.message == "This observation scope has ended")
    #expect(issues.first?.location == staleLocation)
    #expect(!staleOperationRan)
    #expect(service.activeObservationCount == 0)
  }

  @Test
  @MainActor
  func `Body error remains primary while teardown still joins`() async {
    let service = TestingService()
    let sut = TestingViewModel(service: service)

    await #expect(throws: LifecycleError.body) {
      try await observe(sut) { _ in
        throw LifecycleError.body
      }
    }
    #expect(service.activeObservationCount == 0)
  }
}
