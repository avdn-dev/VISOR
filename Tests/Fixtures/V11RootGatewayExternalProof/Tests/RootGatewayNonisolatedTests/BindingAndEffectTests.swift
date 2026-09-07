import RootGatewayModelsNonisolated
import SwiftUI
import Testing
import VISOR

@Suite("Binding and effect API from a nonisolated client", .timeLimit(.minutes(1)))
@MainActor
struct BindingAndEffectTests {

  // MARK: Internal

  @Test
  func `Public binding cases dispatch immediately through the model`() {
    // Given
    let model = NonisolatedBindingViewModel()
    let state = model.state
    let binding = model.bindableState[\.isEnabled]

    // When
    binding.wrappedValue = true
    binding.wrappedValue = false
    Bindable(state)[\.isEnabled].wrappedValue = true

    // Then
    #expect(model.state === state)
    #expect(model.handledValues == [true, false, true])
    #expect(state.isEnabled)
  }

  @Test
  func `Public effect handles include synchronous result delivery`() async throws {
    // Given
    let model = NonisolatedBindingViewModel()

    // When
    let handle: EffectHandle<Int> = model.prepare(42)
    let value = try await handle.value()

    // Then
    #expect(value == 42)
    #expect(model.state.preparedValue == 42)
  }

  @Test
  func `Serial and concurrent owners are usable across package boundaries`() async throws {
    // Given
    let queue = SerialEffectQueue(capacity: 2)
    let concurrent = ConcurrentEffects()

    // When
    let saved = queue.enqueue { "saved" }
    let independent = concurrent.run { 7 }
    await queue.finish()
    await concurrent.finish()

    // Then
    #expect(try await saved.value() == "saved")
    #expect(try await independent.value() == 7)
  }

  @Test
  func `LazyViewModel selector syntax compiles in a public view`() {
    // Given
    let view = NonisolatedBindingView()

    // Then
    requireView(view)
    requireView(view.body)
  }

  // MARK: Private

  private func requireView(_: some View) { }
}
