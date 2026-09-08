import Testing
import VISOR

@Suite(.timeLimit(.minutes(1)))
struct OneShotLatchTests {
  @Test
  func `A nonisolated consumer can resolve across a task boundary`() async {
    // Given
    let latch = OneShotLatch<Int>()

    // When
    let resolution = Task { latch.resolve(42) }
    let value = await latch.wait()

    // Then
    #expect(await resolution.value)
    #expect(value == 42)
    #expect(latch.resolvedValue == 42)
  }
}
