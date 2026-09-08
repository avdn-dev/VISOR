import Testing
import VISOR

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct OneShotLatchTests {
  @Test
  func `A MainActor default consumer can resolve from a cancellation handler`() async {
    // Given
    let latch = OneShotLatch<Result<Int, CancellationError>>()
    let waiter = Task { @MainActor in
      await withTaskCancellationHandler {
        await latch.wait()
      } onCancel: {
        latch.resolve(.failure(CancellationError()))
      }
    }

    // When
    waiter.cancel()
    let result = await waiter.value

    // Then
    #expect(throws: CancellationError.self) { try result.get() }
    #expect(!latch.resolve(.success(42)))
  }
}
