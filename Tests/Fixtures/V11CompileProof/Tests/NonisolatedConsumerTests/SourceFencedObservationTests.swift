import ConsumerModelsNonisolated
import ConsumerServices
import Testing
import VISORTesting

private enum SourceFencedProofError: Error {
  case expected
}

@Suite("Source-fenced observation from a nonisolated-by-default consumer")
struct SourceFencedObservationTests {
  @Test
  @MainActor
  func `Generated recipe reconciles before body and fences actions`() async throws {
    let service = SyncingService()
    let statusService = StatusService()
    let reactionGate = ObservationReactionGate()
    await service.publish(SyncSnapshot(revision: 1))
    await statusService.publish(.ready)
    let sut = SourceBackedViewModel(
      service: service,
      statusService: statusService,
      reactionGate: reactionGate)

    #expect(sut.state.revision == -1)

    try await _observeForProof(
      sut,
      beforePauseDrain: {
        if service.observationSource.currentSnapshot().revision == 10 {
          service.publishSynchronously(SyncSnapshot(revision: 11))
        }
        if statusService.observationSource.currentSnapshot().status == .loading {
          statusService.publishSynchronously(.held)
        }
      }
    ) { test in
      #expect(service.activeObservationCountForProof == 1)
      #expect(statusService.activeObservationCountForProof == 1)
      #expect(sut.state.revision == 1)
      #expect(sut.state.mirroredRevision == 1)
      #expect(sut.state.reactedRevision == 1)
      #expect(sut.state.projectedRevisionSumSeenByReaction == 2)
      #expect(sut.state.status == .ready)
      #expect(sut.state.reactedStatus == .ready)
      #expect(sut.state.revisionSeenByStatusReaction == 1)

      await test.perform {
        await service.synchronise()
      }

      test.expect(\.revision, hasExactChanges: [2])
      test.expect(\.mirroredRevision, hasExactChanges: [2])
      test.expect(\.reactedRevision, hasExactChanges: [2])
      test.expect(
        \.projectedRevisionSumSeenByReaction,
        hasExactChanges: [4])

      await #expect(throws: SourceFencedProofError.expected) {
        try await test.perform {
          await service.synchronise()
          throw SourceFencedProofError.expected
        }
      }

      test.expect(\.revision, hasExactChanges: [3])
      test.expect(\.mirroredRevision, hasExactChanges: [3])
      test.expect(\.reactedRevision, hasExactChanges: [3])
      test.expect(
        \.projectedRevisionSumSeenByReaction,
        hasExactChanges: [6])

      let fencedAction = Task { @MainActor in
        await test.perform {
          await service.publish(SyncSnapshot(revision: 10))
          await statusService.publish(.loading)
        }
      }

      await reactionGate.waitUntilStarted()
      #expect(sut.state.revision == 10)
      #expect(sut.state.status == .loading)
      #expect(sut.state.reactedStatus == .ready)
      reactionGate.open()
      await fencedAction.value

      test.expect(\.revision, hasExactChanges: [10])
      test.expect(\.mirroredRevision, hasExactChanges: [10])
      test.expect(\.status, hasExactChanges: [.loading])
      test.expect(\.reactedStatus, hasExactChanges: [.loading])
      #expect(test._rawCommitCount(\.revision) == 1)

      await test.perform {}
      #expect(sut.state.revision == 11)
      #expect(sut.state.status == .held)
      test.expect(\.revision, hasExactChanges: [])
      test.expect(\.status, hasExactChanges: [])
    }

    #expect(service.activeObservationCountForProof == 0)
    #expect(statusService.activeObservationCountForProof == 0)
    await service.publish(SyncSnapshot(revision: 4))
    #expect(sut.state.revision == 11)
  }
}
