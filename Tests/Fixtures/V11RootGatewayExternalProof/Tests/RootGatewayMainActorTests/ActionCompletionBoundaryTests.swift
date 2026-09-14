import Testing
import VISOR

@Suite("Action completions from a MainActor client", .timeLimit(.minutes(1)))
@MainActor
struct ActionCompletionBoundaryTests {
  @Test
  func `Public completions erase different outputs and compose across package boundaries`() async throws {
    let concurrent = ConcurrentEffects()
    let serial = SerialEffectQueue()
    let number = concurrent.run { 42 }
    let text = serial.enqueue { "saved" }
    let completion = ActionCompletion.all([number.completion, text.completion, .completed])

    await completion.wait()
    await completion.wait()

    #expect(try await number.value() == 42)
    #expect(try await text.value() == "saved")
  }
}
