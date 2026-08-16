import Testing
import VISORTesting

private enum JournalActionError: Error {
  case expected
}

@Suite("Journal resource and diagnostic policy")
struct JournalPolicyTests {
  @Test
  @MainActor
  func `Equal and cross-field writes consume raw commits at the exact guard boundary`() async throws {
    let sut = TestingViewModel()
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 4,
      issueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        sut.state.count = 0
        sut.state.status = "idle"
        sut.state.count = 1
        sut.state.status = "ready"
      }

      #expect(test._rawCommitCount(\.count) == 2)
      #expect(test._rawCommitCount(\.status) == 2)
      #expect(test._rawCommitFieldNames == [
        "count",
        "status",
        "count",
        "status",
      ])
      test.expect(\.count, hasExactChanges: [1])
      test.expect(\.status, hasExactChanges: ["ready"])
    }

    #expect(infrastructureIssues.isEmpty)
  }

  @Test
  @MainActor
  func `Overflow fails the complete window once and suppresses later operations`() async throws {
    let sut = TestingViewModel()
    var infrastructureIssues: [String] = []
    var issueLocation: SourceLocation?
    var laterOperationRan = false
    let performLocation = SourceLocation(
      fileID: "JournalPolicyTests/perform",
      filePath: "/JournalPolicyTests/perform.swift",
      line: 1_234,
      column: 56)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 2,
      issueRecorder: { message, sourceLocation in
        infrastructureIssues.append(message)
        issueLocation = sourceLocation
      }
    ) { test in
      await test.perform({
        sut.state.count = 1
        sut.state.status = "second"
        sut.state.count = 3
        // The production State remains usable after the journal fails closed.
        sut.state.status = "completed"
      }, sourceLocation: performLocation)

      #expect(sut.state.count == 3)
      #expect(sut.state.status == "completed")
      #expect(test._rawCommitFieldNames.isEmpty)
      await test.perform {
        laterOperationRan = true
      }
    }

    #expect(infrastructureIssues == [
      "VISOR failed while recording an action window: active State journal exceeded its logical commit guard"
    ])
    #expect(issueLocation == performLocation)
    #expect(!laterOperationRan)
  }

  @Test
  @MainActor
  func `Overflow immediately releases retained prefix values`() async throws {
    let sut = TestingViewModel()
    var first: TestingReference? = TestingReference()
    var second: TestingReference? = TestingReference()
    let current = TestingReference()
    let firstProbe = WeakReference(first)
    let secondProbe = WeakReference(second)
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 2,
      issueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        sut.state.reference = first!
        sut.state.reference = second!
        sut.state.reference = current
        first = nil
        second = nil

        #expect(firstProbe.value == nil)
        #expect(secondProbe.value == nil)
      }

      #expect(test._rawCommitFieldNames.isEmpty)
    }

    #expect(infrastructureIssues.count == 1)
  }

  @Test
  @MainActor
  func `Earlier session failure wins when overflow follows`() async throws {
    let service = TestingService()
    let sut = TestingViewModel(service: service)
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      issueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        service.terminate()
        try? await test._waitForSessionFailureForProof()
        sut.state.count = 1
        sut.state.status = "overflow"
      }
    }

    #expect(infrastructureIssues == [
      "VISOR failed while running the observation session: unexpectedTermination"
    ])
    #expect(service.activeObservationCount == 0)
  }

  @Test
  @MainActor
  func `Overflow preserves the exact throwing action error`() async throws {
    let sut = TestingViewModel()
    var infrastructureIssues: [String] = []
    var laterOperationRan = false

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      issueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await #expect(throws: JournalActionError.expected) {
        try await test.perform {
          sut.state.count = 1
          sut.state.status = "overflow"
          throw JournalActionError.expected
        }
      }

      #expect(sut.state.count == 1)
      #expect(sut.state.status == "overflow")
      await test.perform {
        laterOperationRan = true
      }
    }

    #expect(infrastructureIssues.count == 1)
    #expect(!laterOperationRan)
  }

  @Test
  @MainActor
  func `Overflow preserves a produced result and suppresses later work`() async throws {
    let sut = TestingViewModel()
    var infrastructureIssues: [String] = []
    var result: Int?
    var predicateEvaluations = 0
    var laterOperationRan = false

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      issueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      result = try await test.perform {
        sut.state.count = 1
        sut.state.status = "overflow"
        return 42
      }

      test.expect(
        \.count,
        alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        })
      await test.perform {
        laterOperationRan = true
      }
    }

    #expect(infrastructureIssues.count == 1)
    #expect(result == 42)
    #expect(predicateEvaluations == 0)
    #expect(!laterOperationRan)
  }

  @Test
  @MainActor
  func `Next perform and observe end release retained typed history`() async throws {
    let sut = TestingViewModel()
    var initial: TestingReference? = TestingReference()
    var committed: TestingReference? = TestingReference()
    let current = TestingReference()
    let initialProbe = WeakReference(initial)
    let committedProbe = WeakReference(committed)
    var endProbe: WeakReference<TestingReference>?

    sut.state.reference = initial!

    try await observe(sut) { test in
      await test.perform {
        sut.state.reference = committed!
      }
      sut.state.reference = current
      initial = nil
      committed = nil

      #expect(initialProbe.value != nil)
      #expect(committedProbe.value != nil)

      await test.perform {
        #expect(initialProbe.value == nil)
        #expect(committedProbe.value == nil)
      }

      var retainedUntilEnd: TestingReference? = TestingReference()
      endProbe = WeakReference(retainedUntilEnd)
      await test.perform {
        sut.state.reference = retainedUntilEnd!
      }
      sut.state.reference = current
      retainedUntilEnd = nil
      #expect(endProbe?.value != nil)
    }

    #expect(endProbe?.value == nil)
  }

  @Test
  @MainActor
  func `Outside-window ring preserves global order relation and omission count`() async throws {
    let sut = TestingViewModel()

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8,
      outsideWindowCapacity: 3,
      issueRecorder: { _, _ in }
    ) { test in
      sut.state.count = 1
      sut.state.status = "second"
      sut.state.count = 3
      sut.state.status = "fourth"

      var context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.map(\.order) == [4, 5, 6])
      #expect(context.entries.map(\.fieldName) == [
        "status",
        "count",
        "status",
      ])
      #expect(context.entries.allSatisfy {
        $0.relation == .beforeFirstAction
      })
      #expect(context.omittedEntryCount == 3)

      await test.perform {
        sut.state.count = 5
      }
      test.expect(\.count, hasExactChanges: [5])

      sut.state.status = "sixth"
      context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.map(\.order) == [5, 6, 7])
      #expect(context.entries.map(\.relation) == [
        .beforeAction(1),
        .beforeAction(1),
        .afterAction(1),
      ])
      #expect(context.omittedEntryCount == 4)

      await test.perform {}
      context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.map(\.relation) == [
        .beforeAction(1),
        .beforeAction(1),
        .betweenActions(previous: 1, next: 2),
      ])
      test.expect(\.status, hasExactChanges: [])
    }
  }

  @Test
  @MainActor
  func `Startup reconciliation is context before the first action`() async throws {
    let service = TestingService(7)
    let sut = TestingViewModel(service: service)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 16,
      outsideWindowCapacity: 16,
      issueRecorder: { _, _ in }
    ) { test in
      let startupContext = test._outsideWindowDiagnosticContextForProof
      #expect(sut.state.sourceValue == 7)
      #expect(sut.state.reactedValue == 7)
      #expect(startupContext.entries.map(\.fieldName).contains("sourceValue"))
      #expect(startupContext.entries.map(\.fieldName).contains("reactedValue"))
      #expect(startupContext.entries.allSatisfy {
        $0.relation == .beforeFirstAction
      })

      await test.perform {}

      #expect(test._rawCommitFieldNames.isEmpty)
      test.expect(\.sourceValue, hasExactChanges: [])
      #expect(test._outsideWindowDiagnosticContextForProof.entries
        .allSatisfy { $0.relation == .beforeAction(1) })
    }
  }

  @Test
  @MainActor
  func `Metadata retains no reference payload and teardown clears context`() async throws {
    let sut = TestingViewModel()
    let current = TestingReference()
    var first: TestingReference? = TestingReference()
    var second: TestingReference? = TestingReference()
    let firstProbe = WeakReference(first)
    let secondProbe = WeakReference(second)
    var escapedTest: ObservationTest<TestingViewModel>?

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8,
      outsideWindowCapacity: 3,
      issueRecorder: { _, _ in }
    ) { test in
      escapedTest = test
      sut.state.reference = first!
      sut.state.reference = second!
      sut.state.reference = current
      first = nil
      second = nil

      #expect(firstProbe.value == nil)
      #expect(secondProbe.value == nil)
      #expect(test._outsideWindowDiagnosticContextForProof.entries.count == 3)
      #expect(test._outsideWindowDiagnosticContextForProof.entries
        .allSatisfy { $0.fieldName == "reference" })
    }

    #expect(escapedTest?._outsideWindowDiagnosticContextForProof.entries == [])
    #expect(escapedTest?._outsideWindowDiagnosticContextForProof
      .omittedEntryCount == 0)
  }

  @Test
  @MainActor
  func `Invalidated action tail is not reclassified as outside context`() async throws {
    let sut = TestingViewModel()
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      outsideWindowCapacity: 4,
      issueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        sut.state.count = 1
        sut.state.status = "overflow"
        sut.state.reference = TestingReference()
      }

      #expect(test._rawCommitFieldNames.isEmpty)
      let context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.count == 2)
      #expect(context.entries.allSatisfy {
        $0.fieldName == "sourceValue" || $0.fieldName == "reactedValue"
      })
    }

    #expect(infrastructureIssues.count == 1)
  }
}
