import ConsumerModelsNonisolated
import ConsumerServices
import Testing
import VISORTesting

private final class JournalWeakReference<Value: AnyObject> {
  weak var value: Value?

  init(_ value: Value?) {
    self.value = value
  }
}

private enum JournalActionError: Error {
  case expected
}

@Suite("Complete-or-fail State journal resources")
struct JournalResourceGuardTests {
  @Test
  @MainActor
  func `Equal and cross-field writes each consume one raw commit`() async throws {
    let sut = CompileProofViewModel()
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 4,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        sut.state[\.count] = 0
        sut.state[\.error] = nil
        sut.state[\.count] = 1
        sut.state[\.items] = []
      }

      #expect(test._rawCommitCount(\.count) == 2)
      #expect(test._rawCommitCount(\.error) == 1)
      #expect(test._rawCommitCount(\.items) == 1)
      #expect(test._rawCommitFieldNames == [
        "count",
        "error",
        "count",
        "items",
      ])
    }

    #expect(infrastructureIssues.isEmpty)
  }

  @Test
  @MainActor
  func `The exact logical boundary remains a complete matchable window`() async throws {
    let sut = CompileProofViewModel()
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 3,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        sut.state[\.count] = 1
        sut.state[\.count] = 2
        sut.state[\.count] = 3
      }

      #expect(test._rawCommitCount(\.count) == 3)
      test.expect(\.count, hasExactChanges: [1, 2, 3])
    }

    #expect(infrastructureIssues.isEmpty)
  }

  @Test
  @MainActor
  func `Overflow completes State writes then fails the whole window once`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    var infrastructureIssues: [String] = []
    var infrastructureIssueLocation: SourceLocation?
    var predicateEvaluations = 0
    var laterOperationRan = false
    let performLocation = SourceLocation(
      fileID: "JournalResourceGuardTests/perform",
      filePath: "/JournalResourceGuardTests/perform.swift",
      line: 1_234,
      column: 56)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 3,
      infrastructureIssueRecorder: { message, sourceLocation in
        infrastructureIssues.append(message)
        infrastructureIssueLocation = sourceLocation
      }
    ) { test in
      #expect(service.activeObservationCountForProof == 1)

      await test.perform({
        sut.state[\.revision] = sut.state.revision
        sut.state[\.mirroredRevision] = sut.state.mirroredRevision
        sut.state[\.reactedRevision] = 1
        sut.state[\.status] = .loading

        // Recording has failed closed, but State remains an ordinary production
        // object and later mutations in the action must still complete.
        sut.state[\.revision] = 42
      }, sourceLocation: performLocation)

      #expect(sut.state.revision == 42)
      #expect(sut.state.status == .loading)
      #expect(service.activeObservationCountForProof == 0)
      #expect(test._rawCommitFieldNames.isEmpty)

      test.expect(
        \.revision,
        alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        })
      await test.perform {
        laterOperationRan = true
      }
    }

    #expect(infrastructureIssues == [
      "VISOR failed while recording an action window: active State journal exceeded its logical commit guard"
    ])
    #expect(infrastructureIssueLocation == performLocation)
    #expect(predicateEvaluations == 0)
    #expect(!laterOperationRan)
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Overflow immediately releases retained prefix values`() async throws {
    let sut = CompileProofViewModel()
    var first: CompileProofViewModel.ReferenceValue? = .init(rawValue: 1)
    var second: CompileProofViewModel.ReferenceValue? = .init(rawValue: 2)
    let current = CompileProofViewModel.ReferenceValue(rawValue: 3)
    let firstProbe = JournalWeakReference(first)
    let secondProbe = JournalWeakReference(second)
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 2,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        sut.state[\.reference] = first!
        sut.state[\.reference] = second!
        sut.state[\.reference] = current
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
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    var infrastructureIssues: [String] = []

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await test.perform {
        service.terminateObservationForProof()
        try? await test._waitForSessionFailureForProof()
        sut.state[\.revision] = 1
        sut.state[\.status] = .loading
      }
    }

    #expect(infrastructureIssues == [
      "VISOR failed while running the observation session: unexpectedTermination"
    ])
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Overflow preserves an exact throwing action error`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    var infrastructureIssues: [String] = []
    var laterOperationRan = false

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      await #expect(throws: JournalActionError.expected) {
        try await test.perform {
          sut.state[\.revision] = 1
          sut.state[\.status] = .loading
          throw JournalActionError.expected
        }
      }

      #expect(sut.state.revision == 1)
      #expect(sut.state.status == .loading)
      #expect(service.activeObservationCountForProof == 0)
      await test.perform {
        laterOperationRan = true
      }
    }

    #expect(infrastructureIssues.count == 1)
    #expect(!laterOperationRan)
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Overflow preserves a produced result and suppresses later VISOR work`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    var infrastructureIssues: [String] = []
    var result: Int?
    var predicateEvaluations = 0
    var laterOperationRan = false

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 1,
      infrastructureIssueRecorder: { message, _ in
        infrastructureIssues.append(message)
      }
    ) { test in
      result = try await test.perform {
        sut.state[\.revision] = 1
        sut.state[\.status] = .loading
        return 42
      }

      #expect(sut.state.revision == 1)
      #expect(sut.state.status == .loading)
      #expect(service.activeObservationCountForProof == 0)
      test.expect(
        \.revision,
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
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Default guard retains the measured mixed-value stress window`() async throws {
    let sut = CompileProofViewModel()
    var copyOnWritePayload = Array(repeating: 0, count: 128)

    try await observe(sut) { test in
      await test.perform {
        for value in 0..<2_048 {
          sut.state[\.count] = value
        }
        for value in 0..<256 {
          sut.state[\.items].append(value)
        }
        for value in 0..<2_048 {
          copyOnWritePayload[value % copyOnWritePayload.count] = value
          sut.state[\.items] = copyOnWritePayload
        }
      }

      #expect(test._rawCommitCount(\.count) == 2_048)
      #expect(test._rawCommitCount(\.items) == 2_304)
      #expect(test._rawCommitFieldNames.count == 4_352)
    }
  }

  @Test
  @MainActor
  func `Next perform and observe end release retained typed history`() async throws {
    let sut = CompileProofViewModel()
    var initial: CompileProofViewModel.ReferenceValue? = .init(rawValue: 1)
    var committed: CompileProofViewModel.ReferenceValue? = .init(rawValue: 2)
    let current = CompileProofViewModel.ReferenceValue(rawValue: 3)
    let initialProbe = JournalWeakReference(initial)
    let committedProbe = JournalWeakReference(committed)
    var endProbe: JournalWeakReference<CompileProofViewModel.ReferenceValue>?

    sut.state[\.reference] = initial!

    try await observe(sut) { test in
      await test.perform {
        sut.state[\.reference] = committed!
      }
      sut.state[\.reference] = current
      initial = nil
      committed = nil

      #expect(initialProbe.value != nil)
      #expect(committedProbe.value != nil)

      await test.perform {
        // Opening this window has already released every typed value from the
        // previous completed window before capturing the current baseline.
        #expect(initialProbe.value == nil)
        #expect(committedProbe.value == nil)
      }

      var retainedUntilEnd:
        CompileProofViewModel.ReferenceValue? = .init(rawValue: 4)
      endProbe = JournalWeakReference(retainedUntilEnd)
      await test.perform {
        sut.state[\.reference] = retainedUntilEnd!
      }
      sut.state[\.reference] = current
      retainedUntilEnd = nil
      #expect(endProbe?.value != nil)
    }

    #expect(endProbe?.value == nil)
  }

  @Test
  @MainActor
  func `Nil production recorder never applies the test guard`() {
    let sut = CompileProofViewModel()

    for value in 0..<10_000 {
      sut.state.setCountDirectly(value)
    }

    #expect(sut.state.count == 9_999)
  }
}
