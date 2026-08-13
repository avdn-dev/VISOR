import Testing
import VISORTesting

@MainActor
private func expectReferenceRejection(
  fieldName: String,
  operation: () -> Void
) {
  withKnownIssue(
    "strict history rejects outer reference '\(fieldName)'",
    {
      operation()
    },
    matching: { issue in
      issue.comments.contains { comment in
        comment.rawValue ==
          "Strict State history does not support an outer reference value for field '\(fieldName)'"
      }
    })
}

@Suite("Strict history matching")
struct HistoryMatchingTests {
  @Test
  @MainActor
  func `Direct and dynamically stored outer references are rejected`() async throws {
    let sut = TestingViewModel()
    var predicateEvaluations = 0

    try await observe(sut) { test in
      await test.perform {}

      expectReferenceRejection(fieldName: "reference") {
        test.expect(\.reference, alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        })
      }

      await test.perform {
        sut.state.anyValue = TestingReference(value: 1)
      }
      expectReferenceRejection(fieldName: "anyValue") {
        test.expect(\.anyValue, alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        })
      }

      await test.perform {}
      expectReferenceRejection(fieldName: "anyValue") {
        test.expect(\.anyValue, alwaysSatisfies: { _ in
          predicateEvaluations += 1
          return true
        })
      }
    }

    #expect(predicateEvaluations == 0)
  }

  @Test
  @MainActor
  func `Optional and container reference histories remain caller-stable values`() async throws {
    let sut = TestingViewModel()
    let stableReference = TestingReference(value: 2)

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
