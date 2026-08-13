import ConsumerModelsNonisolated
import ConsumerServices
import Testing
import VISORTesting

private final class OutsideWindowWeakReference<Value: AnyObject> {
  weak var value: Value?

  init(_ value: Value?) {
    self.value = value
  }
}

@Suite("Outside-window diagnostic ring")
struct OutsideWindowDiagnosticRingTests {
  @Test
  @MainActor
  func `Startup reconciliation is context before the first action`() async throws {
    let service = SyncingService()
    await service.publish(SyncSnapshot(revision: 7))
    let sut = SourceBackedViewModel(service: service)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 16,
      outsideWindowCapacity: 16,
      infrastructureIssueRecorder: { _, _ in }
    ) { test in
      let startupContext =
        test._outsideWindowDiagnosticContextForProof
      #expect(sut.state.revision == 7)
      #expect(sut.state.mirroredRevision == 7)
      #expect(startupContext.entries.map(\.fieldName).contains("revision"))
      #expect(
        startupContext.entries.map(\.fieldName)
          .contains("mirroredRevision"))
      #expect(
        startupContext.entries.allSatisfy {
          $0.relation == .beforeFirstAction
        })

      await test.perform {}

      #expect(test._rawCommitFieldNames.isEmpty)
      test.expect(\.revision, hasExactChanges: [])
      #expect(
        test._outsideWindowDiagnosticContextForProof.entries
          .allSatisfy { $0.relation == .beforeAction(1) })
    }
  }

  @Test
  @MainActor
  func `Metadata preserves order and action relation without entering journals`() async throws {
    let sut = CompileProofViewModel()
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 16,
      outsideWindowCapacity: 8,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      sut.state[\.count] = 1

      #expect(
        test._outsideWindowDiagnosticContextForProof.entries.map(\.relation)
          == [.beforeFirstAction])

      await test.perform {
        sut.state[\.error] = "inside first"
        sut.state[\.count] = 2
      }

      #expect(test._rawCommitFieldNames == ["error", "count"])
      #expect(
        test._outsideWindowDiagnosticContextForProof.entries.map(\.relation)
          == [.beforeAction(1)])

      sut.state[\.items].append(1)
      sut.state[\.count] = 3

      // Metadata writes do not enter or alter the still-matchable first
      // window, and active writes never enter the diagnostic ring.
      #expect(test._rawCommitFieldNames == ["error", "count"])
      test.expect(\.error, hasExactChanges: ["inside first"])
      test.expect(\.count, hasExactChanges: [2])

      var context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.map(\.order) == [1, 2, 3])
      #expect(context.entries.map(\.fieldName) == ["count", "items", "count"])
      #expect(context.entries[0].fieldID == context.entries[2].fieldID)
      #expect(context.entries[0].fieldID != context.entries[1].fieldID)
      #expect(context.entries.map(\.relation) == [
        .beforeAction(1),
        .afterAction(1),
        .afterAction(1),
      ])

      await test.perform {
        sut.state[\.phase] = .loading
      }

      #expect(test._rawCommitFieldNames == ["phase"])
      context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.map(\.relation) == [
        .beforeAction(1),
        .betweenActions(previous: 1, next: 2),
        .betweenActions(previous: 1, next: 2),
      ])

      sut.state[\.error] = "after second"

      #expect(test._rawCommitFieldNames == ["phase"])
      test.expect(\.phase, hasExactChanges: [.loading])
      context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.map(\.order) == [1, 2, 3, 4])
      #expect(context.entries.last?.relation == .afterAction(2))
      #expect(context.omittedEntryCount == 0)
    }

    #expect(infrastructureIssues.isEmpty)
  }

  @Test
  @MainActor
  func `Overwrite retains newest global order and cumulative omission count`() async throws {
    let sut = CompileProofViewModel()

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8,
      outsideWindowCapacity: 3,
      infrastructureIssueRecorder: { _, _ in }
    ) { test in
      sut.state[\.count] = 1
      sut.state[\.error] = "second"
      sut.state[\.items] = [3]
      sut.state[\.phase] = .loading
      sut.state[\.settings] = .init(revision: 5)

      var context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.count == 3)
      #expect(context.entries.map(\.order) == [3, 4, 5])
      #expect(context.entries.map(\.fieldName) == ["items", "phase", "settings"])
      #expect(context.omittedEntryCount == 2)

      await test.perform {}

      sut.state[\.count] = 6
      sut.state[\.error] = "seventh"

      context = test._outsideWindowDiagnosticContextForProof
      #expect(context.entries.count == 3)
      #expect(context.entries.map(\.order) == [5, 6, 7])
      #expect(context.entries.map(\.fieldName) == ["settings", "count", "error"])
      #expect(context.entries.map(\.relation) == [
        .beforeAction(1),
        .afterAction(1),
        .afterAction(1),
      ])
      #expect(context.omittedEntryCount == 4)
    }
  }

  @Test
  @MainActor
  func `Previous typed-window deinitialisation is between actions`() async throws {
    let sut = CompileProofViewModel()
    let replacement = CompileProofViewModel.ReferenceValue(rawValue: 2)
    var retired: CompileProofViewModel.ReferenceValue? = .init(
      rawValue: 1,
      onDeinitialise: {
        sut.state[\.count] = 41
      })

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8,
      outsideWindowCapacity: 8,
      infrastructureIssueRecorder: { _, _ in }
    ) { test in
      sut.state[\.reference] = retired!

      await test.perform {
        sut.state[\.reference] = replacement
      }

      retired = nil
      #expect(sut.state.count == 0)

      await test.perform {
        // Opening action two releases action one's typed reference history.
        // Its synchronous deinitialiser mutates count before this baseline.
        #expect(sut.state.count == 41)
      }

      test.expect(\.count, hasExactChanges: [])
      #expect(test._rawCommitFieldNames.isEmpty)
      let countContext = test._outsideWindowDiagnosticContextForProof.entries
        .filter { $0.fieldName == "count" }
      #expect(countContext.count == 1)
      #expect(
        countContext.first?.relation
          == .betweenActions(previous: 1, next: 2))
    }
  }

  @Test
  @MainActor
  func `Metadata retains no reference payload and teardown clears context`() async throws {
    let sut = CompileProofViewModel()
    let current = CompileProofViewModel.ReferenceValue(rawValue: 3)
    var first: CompileProofViewModel.ReferenceValue? = .init(rawValue: 1)
    var second: CompileProofViewModel.ReferenceValue? = .init(rawValue: 2)
    let firstProbe = OutsideWindowWeakReference(first)
    let secondProbe = OutsideWindowWeakReference(second)
    var escapedTest: ObservationTest<CompileProofViewModel>?

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8,
      outsideWindowCapacity: 4,
      infrastructureIssueRecorder: { _, _ in }
    ) { test in
      escapedTest = test
      sut.state[\.reference] = first!
      sut.state[\.reference] = second!
      sut.state[\.reference] = current
      first = nil
      second = nil

      #expect(firstProbe.value == nil)
      #expect(secondProbe.value == nil)
      #expect(test._outsideWindowDiagnosticContextForProof.entries.count == 3)
      #expect(
        test._outsideWindowDiagnosticContextForProof.entries
          .allSatisfy { $0.fieldName == "reference" })
    }

    #expect(escapedTest?._outsideWindowDiagnosticContextForProof.entries == [])
    #expect(
      escapedTest?._outsideWindowDiagnosticContextForProof.omittedEntryCount
        == 0)
  }

  @Test
  @MainActor
  func `Outside writes neither satisfy nor violate exact matching`() async throws {
    let sut = CompileProofViewModel()

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8,
      outsideWindowCapacity: 4,
      infrastructureIssueRecorder: { _, _ in }
    ) { test in
      sut.state[\.count] = 1
      await test.perform {}
      sut.state[\.count] = 2

      test.expect(\.count, hasExactChanges: [])
      withKnownIssue(
        "an outside-window write cannot satisfy an action expectation",
        {
          test.expect(\.count, hasExactChanges: [2])
        },
        matching: { issue in
          issue.comments.contains { comment in
            comment.rawValue == """
              Expected exact changes [2] for 'count', got []
              Outside-window context (0 omitted): #1 count before action 1; #2 count after action 1
              """
          }
        })
    }
  }

  @Test
  @MainActor
  func `Distinct recorders keep independent rings and action ordinals`() async throws {
    let first = CompileProofViewModel()
    let second = CompileProofViewModel()

    try await _observeWithJournalPolicyForProof(
      first,
      logicalCommitLimit: 8,
      outsideWindowCapacity: 2,
      infrastructureIssueRecorder: { _, _ in }
    ) { firstTest in
      first.state[\.count] = 1
      first.state[\.error] = "second"
      first.state[\.items] = [3]

      try await _observeWithJournalPolicyForProof(
        second,
        logicalCommitLimit: 8,
        outsideWindowCapacity: 4,
        infrastructureIssueRecorder: { _, _ in }
      ) { secondTest in
        second.state[\.phase] = .loading

        let firstContext =
          firstTest._outsideWindowDiagnosticContextForProof
        let secondContext =
          secondTest._outsideWindowDiagnosticContextForProof
        #expect(firstContext.entries.map(\.order) == [2, 3])
        #expect(firstContext.entries.map(\.fieldName) == ["error", "items"])
        #expect(firstContext.omittedEntryCount == 1)
        #expect(secondContext.entries.map(\.order) == [1])
        #expect(secondContext.entries.map(\.fieldName) == ["phase"])
        #expect(secondContext.omittedEntryCount == 0)

        await firstTest.perform {}
        await secondTest.perform {}

        #expect(
          firstTest._outsideWindowDiagnosticContextForProof.entries
            .allSatisfy { $0.relation == .beforeAction(1) })
        #expect(
          secondTest._outsideWindowDiagnosticContextForProof.entries
            .allSatisfy { $0.relation == .beforeAction(1) })
      }
    }
  }

  @Test
  @MainActor
  func `Invalidated action tail is not reclassified as outside context`() async throws {
    let sut = CompileProofViewModel()
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      outsideWindowCapacity: 4,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        sut.state[\.count] = 1
        sut.state[\.error] = "overflows"
        sut.state[\.items] = [3]
      }

      #expect(test._rawCommitFieldNames.isEmpty)
      #expect(test._outsideWindowDiagnosticContextForProof.entries.isEmpty)
    }

    #expect(infrastructureIssues.count == 1)
  }
}
