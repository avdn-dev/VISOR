import Observation
import SwiftUI
import Testing
import VISOR
import VISORObservation
import VISORTesting

// MARK: - BindingActionModel

@MainActor
@Observable
@ViewModel
private final class BindingActionModel {
  final class State {
    private(set) var isEnabled = false
    private(set) var name = "initial"
    private(set) var unbound = 0
  }

  enum Action: Equatable {
    @StateBinding(\State.isEnabled)
    case enabledChanged(Bool)
    @StateBinding(\State.name)
    case nameChanged(value: String)
  }

  var actions = [Action]()

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    actions.append(action)
    switch action {
    case .enabledChanged(let value): updateState(\.isEnabled, to: value)
    case .nameChanged(let value):
      guard !value.isEmpty else { return .completed }
      updateState(\.name, to: value.uppercased())
    }
    return .completed
  }
}

// MARK: - CustomInitialisedBindingModel

@MainActor
@Observable
@ViewModel
private final class CustomInitialisedBindingModel {

  // MARK: Lifecycle

  init(initialValue: Int) {
    state = State()
    updateState(\.value, to: initialValue)
  }

  // MARK: Internal

  final class State {
    private(set) var value = 0
  }

  enum Action {
    @StateBinding(\State.value)
    case valueChanged(Int)
  }

  let state: State
  var handledCount = 0

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    handledCount += 1
    switch action {
    case .valueChanged(let value): updateState(\.value, to: value)
    }
    return .completed
  }
}

// MARK: - SourceBindingModel

@MainActor
@Observable
@ViewModel
private final class SourceBindingModel {
  final class State {
    @Bound(source: \SourceBindingModel.source)
    private(set) var value = 0
  }

  enum Action {
    @StateBinding(\State.value)
    case valueChanged(Int)
  }

  let source: ObservationSource<Int>
  var handledCount = 0

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    handledCount += 1
    switch action {
    case .valueChanged(let value): updateState(\.value, to: value)
    }
    return .completed
  }
}

// MARK: - StateBindingTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct StateBindingTests {
  @Test
  func `Rapid binding events preserve captured values through serial completion and recording`() async throws {
    // Given
    let gate = ControllableOperation<Void, Never>()
    let invocation = gate.prepare()
    var saved = [Bool]()
    let model = QueuedBindingModel { enabled in
      if saved.isEmpty { await gate.run(invocation) }
      saved.append(enabled)
    }

    try await observe(model) { test in
      // When
      try await test.perform {
        model.bindings.isEnabled.wrappedValue = true
        try await gate.waitUntilStarted()
        model.bindings.isEnabled.wrappedValue = false
        model.bindings.isEnabled.wrappedValue = true
        #expect(saved.isEmpty)
        gate.resolve(invocation, with: .success(()))
        await model.finishWrites()
      }

      // Then
      #expect(saved == [true, false, true])
      test.expect(\.isEnabled, hasExactChanges: [true, false, true])
      test.expect(\.completedWrites, hasExactChanges: [1, 2, 3])
    }
  }

  @Test
  func `Binding writes dispatch synchronously in order over stable State`() {
    // Given
    let model = BindingActionModel()
    let original = model.state
    let binding = model.bindings.isEnabled

    // When
    binding.wrappedValue = true
    binding.wrappedValue = false
    binding.wrappedValue = true

    // Then
    #expect(model.state === original)
    #expect(model.state.isEnabled)
    #expect(model.actions == [.enabledChanged(true), .enabledChanged(false), .enabledChanged(true)])
  }

  @Test
  func `Handler can reject and normalise proposed values`() {
    // Given
    let model = BindingActionModel()
    let binding = model.bindings.name

    // When
    binding.wrappedValue = ""

    // Then
    #expect(binding.wrappedValue == "initial")

    // When
    binding.wrappedValue = "colour"

    // Then
    #expect(binding.wrappedValue == "COLOUR")
    #expect(model.actions == [.nameChanged(value: ""), .nameChanged(value: "colour")])
  }

  @Test
  func `Raw State writes are ordinary mutations and never dispatch actions`() {
    // Given
    let model = BindingActionModel()

    // When
    model.handle(.nameChanged(value: "colour"))
    model.state[\.name] = "colour"
    Bindable(model.state)[\.name].wrappedValue = "colour"

    // Then
    #expect(model.state.name == "colour")
    #expect(model.actions == [.nameChanged(value: "colour")])
  }

  @Test
  func `Explicit commits and raw unannotated selectors do not dispatch actions`() {
    // Given
    let model = BindingActionModel()

    // When
    model.updateState(\.name, to: "direct")
    model.state[\.unbound] = 2

    // Then
    #expect(model.state.name == "direct")
    #expect(model.state.unbound == 2)
    #expect(model.actions.isEmpty)
  }

  @Test
  func `Authored initialisers expose model-owned bindings`() {
    // Given
    let model = CustomInitialisedBindingModel(initialValue: 5)

    // When
    model.bindings.value.wrappedValue = 6
    model.bindings.value.wrappedValue = 7

    // Then
    #expect(model.state.value == 7)
    #expect(model.handledCount == 2)
  }

  @Test
  func `Factories expose bindings without connecting State`() {
    // Given
    let factory = CustomInitialisedBindingModel.Factory {
      CustomInitialisedBindingModel(initialValue: 3)
    }

    // When
    let model = factory.makeViewModel()
    model.bindings.value.wrappedValue = 4

    // Then
    #expect(model.state.value == 4)
    #expect(model.handledCount == 1)
  }

  @Test
  func `Retained State and binding do not retain the ViewModel`() {
    // Given
    var model: BindingActionModel? = BindingActionModel()
    weak let reference = model
    let binding = model?.bindings.isEnabled

    // When
    model = nil
    binding?.wrappedValue = true

    // Then
    #expect(reference == nil)
    #expect(binding?.wrappedValue == false)
  }

  @Test
  func `Source reconciliation and later projections never dispatch binding actions`() async throws {
    // Given
    let channel = ObservationChannel(5)
    let model = SourceBindingModel(source: channel.source)

    // When
    try await observe(model) { test in
      await test.perform { channel.publish(6) }

      // Then
      test.expect(\.value, hasExactChanges: [6])
      #expect(model.handledCount == 0)

      // When
      await test.perform { model.bindings.value.wrappedValue = 7 }

      // Then
      test.expect(\.value, hasExactChanges: [7])
      #expect(model.handledCount == 1)
    }
  }
}

// MARK: - QueuedBindingModel

@MainActor
@Observable
@ViewModel
private final class QueuedBindingModel {

  // MARK: Internal

  final class State {
    private(set) var isEnabled = false
    private(set) var completedWrites = 0
  }

  enum Action {
    @StateBinding(\State.isEnabled)
    case enabledChanged(Bool)
  }

  let persist: @MainActor @Sendable (Bool) async -> Void

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    switch action {
    case .enabledChanged(let enabled):
      updateState(\.isEnabled, to: enabled)
      return writes.enqueue(for: self) { [persist] in
        await persist(enabled)
      } receive: { model, _ in
        model.updateState(\.completedWrites, to: model.state.completedWrites + 1)
      }.completion
    }
  }

  func finishWrites() async {
    await writes.finish()
  }

  // MARK: Private

  private let writes = SerialEffectQueue()
}
