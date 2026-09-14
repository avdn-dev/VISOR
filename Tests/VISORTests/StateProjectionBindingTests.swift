import Observation
import os
import SwiftUI
import Testing
import VISORObservation
import VISORTesting
@testable import VISOR

// MARK: - ProjectionBindingModel

@MainActor
@Observable
@ViewModel
private final class ProjectionBindingModel {
  enum Sheet { case picker, settings }

  final class State {
    private(set) var activeSheet: Sheet? = .picker
    private(set) var title = "initial"

    var isPickerPresented: Bool {
      activeSheet == .picker
    }
  }

  enum Action: Equatable {
    @StateBinding(\State.isPickerPresented)
    case pickerPresentationChanged(Bool)
    @StateBinding(\State.title)
    case titleChanged(String)
    @StateBinding(\State.activeSheet)
    case activeSheetChanged(Sheet?)
  }

  var actions = [Action]()

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    actions.append(action)
    switch action {
    case .pickerPresentationChanged(let value):
      guard !value, state.activeSheet == .picker else { return .completed }
      updateState(\.activeSheet, to: nil)

    case .titleChanged(let value):
      updateState(\.title, to: value.uppercased())

    case .activeSheetChanged(let value):
      updateState(\.activeSheet, to: value)
    }
    return .completed
  }
}

// MARK: - SourceProjectionBindingModel

@MainActor
@Observable
@ViewModel
private final class SourceProjectionBindingModel {
  final class State {
    @Bound(source: \SourceProjectionBindingModel.source)
    private(set) var count = 0

    var isEnabled: Bool {
      count > 0
    }
  }

  enum Action {
    @StateBinding(\State.isEnabled)
    case enabledChanged(Bool)
  }

  let source: ObservationSource<Int>
  var handledCount = 0

  @discardableResult
  func handle(_: Action) -> ActionCompletion {
    handledCount += 1
    return .completed
  }
}

// MARK: - ProjectionSettings

@MainActor
@Observable
private final class ProjectionSettings {
  var isEnabled = false
  var title = "initial"
}

// MARK: - CustomProjectionBindingModel

@MainActor
@Observable
@ViewModel
private final class CustomProjectionBindingModel {

  // MARK: Lifecycle

  init(state: State = State()) {
    self.state = state
  }

  // MARK: Internal

  final class State {
    private(set) var settings = ProjectionSettings()

    var isEnabled: Bool {
      settings.isEnabled
    }
  }

  enum Action {
    @StateBinding(\State.isEnabled)
    case enabledChanged(Bool)
  }

  let state: State
  var handledCount = 0

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    handledCount += 1
    switch action {
    case .enabledChanged(let value): state.settings.isEnabled = value
    }
    return .completed
  }
}

// MARK: - StateProjectionBindingTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct StateProjectionBindingTests {

  // MARK: Internal

  @Test
  func `Optional action bindings keep reads but stop writes after model deinitialisation`() throws {
    // Given
    var model: ProjectionBindingModel? = ProjectionBindingModel()
    let binding = try #require(model?.bindings.activeSheet)

    // When
    binding.wrappedValue = nil

    // Then
    #expect(model?.state.activeSheet == nil)
    #expect(model?.actions == [.activeSheetChanged(nil)])

    // When
    binding.wrappedValue = .settings

    // Then
    #expect(model?.actions == [.activeSheetChanged(nil), .activeSheetChanged(.settings)])

    // When
    weak let owner = model
    model = nil
    binding.wrappedValue = .picker

    // Then
    #expect(owner == nil)
    #expect(binding.wrappedValue == .settings)
  }

  @Test
  func `Models sharing State still dispatch only to their own binding owner`() {
    let state = CustomProjectionBindingModel.State()
    let first = CustomProjectionBindingModel(state: state)
    let second = CustomProjectionBindingModel(state: state)
    first.bindings.isEnabled.wrappedValue = true
    #expect(second.bindings.isEnabled.wrappedValue)
    #expect(first.handledCount == 1)
    #expect(second.handledCount == 0)
    second.bindings.isEnabled.wrappedValue = false
    #expect(!first.bindings.isEnabled.wrappedValue)
    #expect(first.handledCount == 1)
    #expect(second.handledCount == 1)
  }

  @Test
  func `First binding access tracks only the selected State dependencies`() {
    let model = ProjectionBindingModel()
    let changes = OSAllocatedUnfairLock(initialState: 0)
    withObservationTracking {
      _ = model.bindings.isPickerPresented.wrappedValue
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    #expect(model.actions.isEmpty)
    model.bindings.isPickerPresented.wrappedValue = true
    model.updateState(\.title, to: "unrelated")
    #expect(changes.withLock { $0 } == 0)
    model.updateState(\.activeSheet, to: nil)
    #expect(changes.withLock { $0 } == 1)
  }

  @Test
  func `Authored initialisers and factories expose computed bindings`() {
    let model = CustomProjectionBindingModel()
    model.bindings.isEnabled.wrappedValue = true
    model.bindings.isEnabled.wrappedValue = false
    #expect(!model.state.isEnabled)
    #expect(model.handledCount == 2)

    let factory = CustomProjectionBindingModel.Factory { CustomProjectionBindingModel() }
    let constructed = factory.makeViewModel()
    constructed.bindings.isEnabled.wrappedValue = true
    #expect(constructed.state.isEnabled)
    #expect(constructed.handledCount == 1)
  }

  @Test
  func `Computed reads preserve granular observation of nested observable references`() {
    let model = CustomProjectionBindingModel()
    let binding = model.bindings.isEnabled
    let changes = OSAllocatedUnfairLock(initialState: 0)
    withObservationTracking {
      _ = binding.wrappedValue
    } onChange: {
      changes.withLock { $0 += 1 }
    }

    model.state.settings.title = "unrelated"
    #expect(changes.withLock { $0 } == 0)
    model.state.settings.isEnabled = true
    #expect(changes.withLock { $0 } == 1)
    #expect(binding.wrappedValue)

    withObservationTracking {
      _ = binding.wrappedValue
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    model.updateState(\.settings, to: ProjectionSettings())
    #expect(changes.withLock { $0 } == 2)
    #expect(!binding.wrappedValue)
    #expect(model.handledCount == 0)
  }

  @Test
  func `Repeated writes synchronously dispatch even when the handler rejects them`() {
    let model = ProjectionBindingModel()
    let state = model.state
    let binding = model.bindings.isPickerPresented
    binding.wrappedValue = true
    binding.wrappedValue = true
    #expect(binding.wrappedValue)
    binding.wrappedValue = false
    binding.wrappedValue = false
    #expect(!binding.wrappedValue)
    #expect(model.state === state)
    #expect(model.actions == [
      .pickerPresentationChanged(true),
      .pickerPresentationChanged(true),
      .pickerPresentationChanged(false),
      .pickerPresentationChanged(false),
    ])
  }

  @Test
  func `Projection handlers can protect unrelated presentation state`() {
    let model = ProjectionBindingModel()
    model.updateState(\.activeSheet, to: .settings)
    #expect(model.actions.isEmpty)
    model.bindings.isPickerPresented.wrappedValue = false
    #expect(model.state.activeSheet == .settings)
    #expect(model.actions == [.pickerPresentationChanged(false)])
  }

  @Test
  func `Computed and stored bindings synchronously dispatch actions`() {
    let model = ProjectionBindingModel()
    model.bindings.isPickerPresented.wrappedValue = false
    model.bindings.title.wrappedValue = "colour"
    #expect(model.state.activeSheet == nil)
    #expect(model.state.title == "COLOUR")
    #expect(model.actions == [.pickerPresentationChanged(false), .titleChanged("colour")])
  }

  @Test
  func `Projection reads observe canonical dependencies only`() {
    let model = ProjectionBindingModel()
    let binding = model.bindings.isPickerPresented
    let changes = OSAllocatedUnfairLock(initialState: 0)
    withObservationTracking {
      _ = binding.wrappedValue
    } onChange: {
      changes.withLock { $0 += 1 }
    }

    model.updateState(\.title, to: "unrelated")
    #expect(changes.withLock { $0 } == 0)
    model.updateState(\.activeSheet, to: nil)
    #expect(changes.withLock { $0 } == 1)
    #expect(!binding.wrappedValue)
    #expect(model.actions.isEmpty)
  }

  @Test
  func `Bindings retain readable State without retaining their action owner`() throws {
    var model: ProjectionBindingModel? = ProjectionBindingModel()
    weak let owner = model
    let binding = try #require(model?.bindings.isPickerPresented)
    model = nil
    binding.wrappedValue = false
    #expect(owner == nil)
    #expect(binding.wrappedValue)
  }

  @Test
  func `Generic binding access preserves roots and instances route independently`() {
    let first = ProjectionBindingModel()
    let second = ProjectionBindingModel()
    let copy = bindings(for: first)
    #expect(copy._visorStorage === first.bindings._visorStorage)
    #expect(first.bindings._visorStorage !== second.bindings._visorStorage)
    first.bindings.isPickerPresented.wrappedValue = false
    #expect(first.actions.count == 1)
    #expect(second.actions.isEmpty)
    #expect(second.bindings.isPickerPresented.wrappedValue)
  }

  @Test
  func `Strict mutation recording includes only canonical stored fields`() async throws {
    let model = ProjectionBindingModel()
    #expect(ProjectionBindingModel.State._visorAllFields.map(\.name) == ["activeSheet", "title"])
    try await observe(model) { test in
      await test.perform {
        model.bindings.isPickerPresented.wrappedValue = false
      }
      test.expect(\.activeSheet, hasExactChanges: [nil])
    }
  }

  @Test
  func `Bound source updates change computed reads without redispatching actions`() async throws {
    let channel = ObservationChannel(0)
    let model = SourceProjectionBindingModel(source: channel.source)
    let binding = model.bindings.isEnabled
    #expect(!binding.wrappedValue)
    try await observe(model) { test in
      await test.perform { channel.publish(1) }
      test.expect(\.count, hasExactChanges: [1])
      #expect(binding.wrappedValue)
      #expect(model.handledCount == 0)
    }
  }

  // MARK: Private

  private func bindings<Model: ViewModel>(for model: Model) -> ViewModelBindings<Model> {
    model.bindings
  }
}
