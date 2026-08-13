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
      infrastructureIssueRecorder: { message, location in
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
    var enteredBody = false

    try await withKnownIssue(
      "startup failure is attributed to observe",
      {
        try await observe(sut) { _ in
          enteredBody = true
        }
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue.hasPrefix(
            "VISOR failed while starting observation:")
        }
      })

    #expect(!enteredBody)
    #expect(service.activeObservationCount == 0)
  }

  @Test
  @MainActor
  func `Runtime source failure poisons the window and suppresses later work`() async throws {
    let service = TestingService()
    let sut = TestingViewModel(service: service)
    var laterOperationRan = false

    try await withKnownIssue(
      "runtime source failure is reported once",
      {
        try await observe(sut) { test in
          await test.perform {
            service.terminate()
          }
          test.expect(\.sourceValue, hasExactChanges: [])
          await test.perform {
            laterOperationRan = true
          }
        }
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue.hasPrefix("VISOR failed while ")
        }
      })

    #expect(!laterOperationRan)
    #expect(service.activeObservationCount == 0)
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

    try await observe(sut!) { test in
      escaped = test
    }

    sut = nil
    #expect(weakSUT.value == nil)
    #expect(service.activeObservationCount == 0)

    await withKnownIssue(
      "stale handle is diagnosed",
      {
        await escaped?.perform {}
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue == "This observation scope has ended"
        }
      })
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
