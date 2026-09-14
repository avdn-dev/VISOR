import RootGatewayModelsNonisolated
import SwiftUI
import Testing
import VISOR

@Suite("Binding and effect API from a nonisolated client", .timeLimit(.minutes(1)))
@MainActor
struct BindingAndEffectTests {

  // MARK: Internal

  @Test
  func `Generic action dispatch returns public completion without an async overload`() async {
    let model = NonisolatedBindingViewModel()
    let immediate = dispatch(.enabledChanged(true), to: model)
    #expect(model.state.isEnabled)
    await immediate.wait()
    let preparation = dispatch(.prepare(42), to: model)
    await ActionCompletion.all([immediate, preparation]).wait()
    #expect(model.state.preparedValue == 42)
  }

  @Test
  func `Public binding cases dispatch immediately through the model`() {
    // Given
    let model = NonisolatedBindingViewModel()
    let state = model.state
    let binding = model.bindings.isEnabled

    // When
    binding.wrappedValue = true
    binding.wrappedValue = false
    model.bindings.isEnabled.wrappedValue = true

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

  @Test
  func `Public computed bindings route actions across package boundaries`() {
    let model = NonisolatedBindingViewModel()
    let binding = model.bindings.isDisabled
    #expect(binding.wrappedValue)
    binding.wrappedValue = false
    binding.wrappedValue = false
    #expect(model.handledValues == [true, true])
    #expect(model.state.isEnabled)
    model.updateState(\.isEnabled, to: false)
    #expect(binding.wrappedValue)
    #expect(model.handledValues == [true, true])
  }

  @Test
  func `Typed namespaces forward action bindings through generic code`() {
    // Given
    let model = NonisolatedBindingViewModel()
    let controls: ViewModelBindings<NonisolatedBindingViewModel> = bindings(for: model)

    // When
    controls.isEnabled.wrappedValue = true

    // Then
    #expect(model.state.isEnabled)
    #expect(model.handledValues == [true])
  }

  // MARK: Private

  private func dispatch<Model: ViewModel>(_ action: Model.Action, to model: Model) -> ActionCompletion {
    model.handle(action)
  }

  private func bindings<Model: ViewModel>(for model: Model) -> ViewModelBindings<Model> {
    model.bindings
  }

  private func requireView(_: some View) { }
}
