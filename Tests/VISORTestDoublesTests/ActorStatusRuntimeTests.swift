import Testing
import VISORTestDoubles

// MARK: - ActorStatusService

@MainActor
@GenerateSpy
@GenerateStub
protocol ActorStatusService: Sendable {
  func record(_ value: Int)
}

// MARK: - ActorStatusBoundaryTests

@MainActor
struct ActorStatusBoundaryTests {
  @Test
  func `Ordinary actor owned doubles safely cross tasks`() async {
    // Given
    let spy = SpyActorStatusService()
    let stub = StubActorStatusService()

    // When
    await Task.detached {
      await spy.record(3)
      await stub.record(4)
    }.value

    // Then
    #expect(spy.recordReceivedValue == 3)
  }
}
