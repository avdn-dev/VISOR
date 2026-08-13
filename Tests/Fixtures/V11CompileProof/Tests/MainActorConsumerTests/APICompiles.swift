import ConsumerModelsMainActor
import ConsumerServices
import Observation
import SwiftUI
import Testing
import VISORTesting

private enum CompileProofError: Error {
  case expected
}

@Suite("V11 API from a MainActor-by-default consumer")
struct MainActorConsumerTests {
  @Test
  @MainActor
  func `Custom State initialiser assigns an uninitialised stored field`() {
    let state = CompileProofViewModel.State(identifier: "custom")

    #expect(state.identifier == "custom")
  }

  @Test
  @MainActor
  func `Generated LazyViewModel body consumes the hidden owner host`() {
    let screen = LazySourceBackedScreen(service: SyncingService())
    _ = screen.body
  }

  @Test
  @MainActor
  func `Top-down action windows and routed bindings compile and run`() async throws {
    let sut = CompileProofViewModel()
    #expect(sut.state.identifier == "initial")

    try await observe(sut) { test in
      await confirmation(
        "baseline capture does not register Observation",
        expectedCount: 0
      ) { confirm in
        withObservationTracking {
          test._captureBaselineForProof()
        } onChange: {
          confirm()
        }
        sut.state.setCountDirectly(-1)
      }
      sut.state.setCountDirectly(0)

      await test.perform(.refresh)

      test.expect(
        \.phase,
        hasExactChanges: [.loading, .loaded])
      test.expect(
        \.count,
        hasExactChanges: [1])
      #expect(test._rawCommitCount(\.phase) == 2)
      #expect(test._rawCommitCount(\.count) == 1)
      test.expect(
        \.error,
        alwaysSatisfies: { $0 == nil })

      await test.perform(.clear)
      test.expect(\.phase, hasExactChanges: [.idle])

      await test.perform {
        sut.state[\.count] = 2
      }

      test.expect(\.count, hasExactChanges: [2])
      #expect(test._rawCommitCount(\.count) == 1)

      await test.perform {
        @Bindable var state = sut.state
        $state[\.count].wrappedValue = 3
      }

      test.expect(\.count, hasExactChanges: [3])
      #expect(test._rawCommitCount(\.count) == 1)

      let bindableState = Bindable(sut.state)

      await test.perform {
        bindableState[\.count].wrappedValue = 4
      }

      test.expect(\.count, hasExactChanges: [4])
      #expect(test._rawCommitCount(\.count) == 1)

      await confirmation(
        "an equal Binding write does not invalidate Observation",
        expectedCount: 0
      ) { confirm in
        withObservationTracking {
          _ = sut.state.count
        } onChange: {
          confirm()
        }

        await test.perform {
          @Bindable var state = sut.state
          $state[\.count].wrappedValue = 4
        }
      }

      test.expect(\.count, hasExactChanges: [])
      #expect(test._rawCommitCount(\.count) == 1)

      await test.perform {
        sut.state[\.count] = 4
        sut.state[\.count] = 4
        sut.state[\.nonEquatableValue] = .init(rawValue: 1)
      }

      test.expect(\.count, hasExactChanges: [])
      test.expect(
        \.nonEquatableValue,
        alwaysSatisfies: {
          $0.rawValue <= sut.state.nonEquatableValue.rawValue
        })

      await test.perform {
        sut.state[\.settings].revision += 1
      }

      test.expect(
        \.settings,
        hasExactChanges: [.init(revision: 1)])
      #expect(test._rawCommitCount(\.settings) == 1)

      await test.perform {
        sut.state[\.error] = "expected"
        sut.state[\.items].append(1)
      }

      test.expect(\.error, hasExactChanges: ["expected"])
      test.expect(\.items, hasExactChanges: [[1]])
      #expect(test._rawCommitCount(\.error) == 1)
      #expect(test._rawCommitCount(\.items) == 1)

      await confirmation(
        "one ordinary Observation invalidation",
        expectedCount: 1
      ) { confirm in
        withObservationTracking {
          _ = sut.state.count
        } onChange: {
          confirm()
        }

        await test.perform {
          sut.state.setCountDirectly(5)
        }
      }

      test.expect(\.count, hasExactChanges: [5])
      #expect(test._rawCommitCount(\.count) == 1)

      await test.perform {
        sut.state.incrementPackageRevision()
      }

      test.expect(\.packageRevision, hasExactChanges: [1])

      await test.perform {
        sut.state.incrementHiddenRevisions()
      }

      #expect(test._rawCommitFieldNames == [
        "internalRevision",
        "fileRevision",
        "privateRevision",
      ])

      await test.perform {
        sut.state.incrementSettingsDirectly()
      }

      test.expect(
        \.settings,
        hasExactChanges: [.init(revision: 2)])
      #expect(test._rawCommitCount(\.settings) == 1)

      await #expect(throws: CompileProofViewModel.MutationError.self) {
        try await test.perform {
          try sut.state.incrementSettingsThenThrow()
        }
      }

      test.expect(
        \.settings,
        hasExactChanges: [.init(revision: 3)])
      #expect(test._rawCommitCount(\.settings) == 1)

      await #expect(throws: CompileProofViewModel.MutationError.self) {
        try await test.perform {
          try sut.state.leaveSettingsThenThrow()
        }
      }

      test.expect(\.settings, hasExactChanges: [])
      #expect(test._rawCommitCount(\.settings) == 1)

      await test.perform {
        sut.state.appendItemDirectly(2)
      }

      test.expect(\.items, hasExactChanges: [[1, 2]])
      #expect(test._rawCommitCount(\.items) == 1)

      await confirmation(
        "equal writes do not invalidate Observation",
        expectedCount: 0
      ) { confirm in
        withObservationTracking {
          _ = sut.state.count
        } onChange: {
          confirm()
        }

        await test.perform {
          sut.state.setCountDirectly(5)
          sut.state.setCountDirectly(5)
        }
      }

      test.expect(\.count, hasExactChanges: [])
      #expect(test._rawCommitCount(\.count) == 2)

      sut.state[\.nonEquatableValue] = .init(rawValue: 0)
      await test.perform {
        sut.state[\.nonEquatableValue] = .init(rawValue: 1)
      }

      withKnownIssue(
        "alwaysSatisfies includes the action baseline",
        {
          test.expect(
            \.nonEquatableValue,
            alwaysSatisfies: { $0.rawValue > 0 })
        },
        matching: { issue in
          issue.comments.contains { comment in
            comment.rawValue.hasPrefix(
              "The baseline for 'nonEquatableValue' did not always satisfy the predicate"
            )
          }
        })

      await test.perform {
        sut.state.mutateReferenceInterior()
      }

      #expect(test._rawCommitCount(\.reference) == 0)
      withKnownIssue(
        "strict history rejects outer reference values",
        {
          test.expect(\.reference, hasExactChanges: [])
        },
        matching: { issue in
          issue.comments.contains { comment in
            comment.rawValue ==
              "Strict State history does not support an outer reference value for field 'reference'"
          }
        })

      let replacement = CompileProofViewModel.ReferenceValue(rawValue: 2)
      await test.perform {
        sut.state[\.reference] = replacement
      }

      #expect(sut.state.reference === replacement)
      #expect(test._rawCommitCount(\.reference) == 1)
      withKnownIssue(
        "replacement does not make reference history stable",
        {
          test.expect(\.reference, alwaysSatisfies: { _ in true })
        },
        matching: { issue in
          issue.comments.contains { comment in
            comment.rawValue ==
              "Strict State history does not support an outer reference value for field 'reference'"
          }
        })

      withObservationTracking {
        _ = sut.state.count
      } onChange: {
        MainActor.assumeIsolated {
          sut.state.setErrorDirectly("reentrant")
        }
      }

      await test.perform {
        sut.state.setCountDirectly(6)
      }

      #expect(test._rawCommitFieldNames == ["error", "count"])
      test.expect(\.error, hasExactChanges: ["reentrant"])
      test.expect(\.count, hasExactChanges: [6])

      sut.state.setCountDirectly(7)
      await test.perform {}
      sut.state.setCountDirectly(8)
      test.expect(\.count, alwaysSatisfies: { $0 == 7 })

      await test.perform {}
      test.expect(\.count, alwaysSatisfies: { $0 == 8 })

      let result = try await test.perform { 42 }

      #expect(result == 42)
      test.expect(\.count, hasExactChanges: [])

      let throwingResult = try await test.perform { () async throws -> Int in
        43
      }

      #expect(throwingResult == 43)
      test.expect(\.count, hasExactChanges: [])

      await #expect(throws: CompileProofError.self) {
        try await test.perform { () async throws -> Void in
          throw CompileProofError.expected
        }
      }

      test.expect(\.count, hasExactChanges: [])
    }
  }

  @Test
  func `Actor service source remains isolation neutral`() async {
    let service = SyncingService()

    await service.synchronise()

    let snapshot = service.observationSource.currentSnapshot()
    #expect(snapshot == SyncSnapshot(revision: 1))
  }
}
