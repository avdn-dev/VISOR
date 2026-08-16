import Testing
import VISORTesting

@Suite("Strict history matching")
struct HistoryMatchingTests {
  @Test
  @MainActor
  func `Direct outer reference history is rejected without evaluating the predicate`() async throws {
    let sut = TestingViewModel()
    var issues: [(message: String, location: SourceLocation)] = []
    var predicateEvaluations = 0
    let expectationLocation = SourceLocation(
      fileID: "HistoryMatchingTests/direct-reference",
      filePath: "/HistoryMatchingTests/direct-reference.swift",
      line: 101,
      column: 7)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8_192,
      issueRecorder: { message, location in
        issues.append((message, location))
      }
    ) { test in
      await test.perform {}
      test.expect(
        \.reference,
        alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        },
        sourceLocation: expectationLocation)
    }

    #expect(issues.count == 1)
    #expect(issues.first?.message ==
      "Strict State history does not support an outer reference value for field 'reference'")
    #expect(issues.first?.location == expectationLocation)
    #expect(predicateEvaluations == 0)
  }

  @Test
  @MainActor
  func `Any-held reference commit is rejected without evaluating the predicate`() async throws {
    let sut = TestingViewModel()
    var issues: [(message: String, location: SourceLocation)] = []
    var predicateEvaluations = 0
    let expectationLocation = SourceLocation(
      fileID: "HistoryMatchingTests/any-commit",
      filePath: "/HistoryMatchingTests/any-commit.swift",
      line: 202,
      column: 8)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8_192,
      issueRecorder: { message, location in
        issues.append((message, location))
      }
    ) { test in
      await test.perform {
        sut.state.anyValue = TestingReference()
      }
      test.expect(
        \.anyValue,
        alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        },
        sourceLocation: expectationLocation)
    }

    #expect(issues.count == 1)
    #expect(issues.first?.message ==
      "Strict State history does not support an outer reference value for field 'anyValue'")
    #expect(issues.first?.location == expectationLocation)
    #expect(predicateEvaluations == 0)
  }

  @Test
  @MainActor
  func `Any-held reference baseline is rejected without evaluating the predicate`() async throws {
    let sut = TestingViewModel()
    sut.state.anyValue = TestingReference()
    var issues: [(message: String, location: SourceLocation)] = []
    var predicateEvaluations = 0
    let expectationLocation = SourceLocation(
      fileID: "HistoryMatchingTests/any-baseline",
      filePath: "/HistoryMatchingTests/any-baseline.swift",
      line: 303,
      column: 9)

    try await _observeWithJournalPolicyForProof(
      sut,
      logicalCommitLimit: 8_192,
      issueRecorder: { message, location in
        issues.append((message, location))
      }
    ) { test in
      await test.perform {}
      test.expect(
        \.anyValue,
        alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        },
        sourceLocation: expectationLocation)
    }

    #expect(issues.count == 1)
    #expect(issues.first?.message ==
      "Strict State history does not support an outer reference value for field 'anyValue'")
    #expect(issues.first?.location == expectationLocation)
    #expect(predicateEvaluations == 0)
  }

  @Test
  @MainActor
  func `Optional and container reference histories remain caller-stable values`() async throws {
    let sut = TestingViewModel()
    let stableReference = TestingReference()

    try await observe(sut) { test in
      await test.perform {
        sut.state.optionalReference = stableReference
        sut.state.referenceContainer = [stableReference]
      }

      test.expect(
        \.optionalReference,
        alwaysSatisfies: { value in
          value == nil || value === stableReference
        })
      test.expect(
        \.referenceContainer,
        alwaysSatisfies: { values in
          values.isEmpty || values.first === stableReference
        })
    }
  }
}
