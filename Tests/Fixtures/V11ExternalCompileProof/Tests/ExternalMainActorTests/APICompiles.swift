import ExternalDoubleConsumer
import ExternalModelsMainActor
import ExternalServices
import SwiftUI
import Testing
import VISORTesting

@Suite("External MainActor-default consumer")
struct ExternalMainActorTests {
  @Test
  @MainActor
  func `Generated gateway crosses the package boundary`() async throws {
    let sut = ExternalViewModel()

    try await observe(sut) { test in
      await test.perform(.refresh)
      test.expect(\.phase, hasExactChanges: [.loading, .loaded])
      test.expect(\.count, hasExactChanges: [1])

      await test.perform {
        @Bindable var state = sut.state
        $state[\.count].wrappedValue = 2
        state[\.settings].revision += 1
      }

      test.expect(\.count, hasExactChanges: [2])
      test.expect(
        \.settings,
        hasExactChanges: [.init(revision: 1)])

      await test.perform {
        sut.state.setCountDirectly(3)
      }

      test.expect(\.count, hasExactChanges: [3])
      test.expect(\.count, alwaysSatisfies: { $0 >= 2 })

      await test.perform {
        sut.state.mutateReferenceInterior()
      }

      withKnownIssue(
        "external equality history names and rejects 'reference'",
        {
          test.expect(\.reference, hasExactChanges: [])
        },
        matching: { issue in
          issue.comments.contains { comment in
            comment.rawValue ==
              "Strict State history does not support an outer reference value for field 'reference'"
          }
        })
      withKnownIssue(
        "external predicate history names and rejects 'reference'",
        {
          test.expect(\.reference, alwaysSatisfies: { _ in true })
        },
        matching: { issue in
          issue.comments.contains { comment in
            comment.rawValue ==
              "Strict State history does not support an outer reference value for field 'reference'"
          }
        })
    }
  }

  @Test
  func `Production capability products remain independently consumable`() async {
    _ = ExternalDoubleSupport()
    let service = ExternalSyncService()

    await service.synchronise()

    #expect(service.observationSource.currentSnapshot() == 1)
  }
}
