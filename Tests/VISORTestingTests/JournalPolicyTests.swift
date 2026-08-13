import Testing
import VISORTesting

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
}
