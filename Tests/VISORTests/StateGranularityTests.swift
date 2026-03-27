import Observation
import SwiftUI
import Testing
import VISOR

// MARK: - Class State Fixtures

/// @Observable class State — per-field tracking.
@Observable
private final class ClassState {
  var fieldA = "a"
  var fieldB = "b"
  @ObservationIgnored var ignored = "ignored"
}

/// Uses updateState that writes through @ObservationIgnored _state,
/// bypassing VM-level withMutation(\.state). Only ClassState's
/// per-field withMutation fires.
@Observable
@MainActor
private final class ClassStateFixedVM: ViewModel {
  typealias State = ClassState
  @ObservationIgnored private var _state = ClassState()
  var state: ClassState {
    get { access(keyPath: \.state); return _state }
    set { withMutation(keyPath: \.state) { _state = newValue } }
  }

  func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
    guard _state[keyPath: keyPath] != value else { return }
    _state[keyPath: keyPath] = value
  }

  func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
    _state[keyPath: keyPath] = value
  }
}

/// Nested class State inside @MainActor VM — the real-world pattern.
@Observable
@MainActor
private final class NestedClassStateVM: ViewModel {
  @Observable
  final class State {
    var fieldA = "a"
    var fieldB = "b"
  }

  @ObservationIgnored private var _state = State()
  var state: State {
    get { access(keyPath: \.state); return _state }
    set { withMutation(keyPath: \.state) { _state = newValue } }
  }

  func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
    guard _state[keyPath: keyPath] != value else { return }
    _state[keyPath: keyPath] = value
  }
}

/// Class WITHOUT @Observable — proves @Observable is required.
private final class PlainClassState {
  var fieldA = "a"
  var fieldB = "b"
}

/// NOT a ViewModel — plain class State can't satisfy Observable constraint.
/// Used to prove @Observable is required for per-field tracking.
@Observable
@MainActor
private final class PlainClassStateVM {
  var state = PlainClassState()
}

// MARK: - Tests

@Suite("State observation granularity")
@MainActor
struct StateGranularityTests {

  // MARK: - Class State: per-field granularity (updateState via _state)

  @Test
  func `updateState on fieldA does not fire fieldB observer`() async {
    let vm = ClassStateFixedVM()

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      vm.updateState(\.fieldA, to: "new")
    }
  }

  @Test
  func `updateState on fieldB fires its own observer`() async {
    let vm = ClassStateFixedVM()

    await confirmation { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      vm.updateState(\.fieldB, to: "new")
    }
  }

  @Test
  func `updateState with same value does not fire observer`() async {
    let vm = ClassStateFixedVM()

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.fieldA
      } onChange: {
        confirmed()
      }
      vm.updateState(\.fieldA, to: "a")
    }
  }

  @Test
  func `repeated updateState on fieldA produces zero spurious fieldB fires`() async {
    let vm = ClassStateFixedVM()

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking { _ = vm.state.fieldB } onChange: { confirmed() }
      vm.updateState(\.fieldA, to: "1")
      withObservationTracking { _ = vm.state.fieldB } onChange: { confirmed() }
      vm.updateState(\.fieldA, to: "2")
      withObservationTracking { _ = vm.state.fieldB } onChange: { confirmed() }
      vm.updateState(\.fieldA, to: "3")
    }
  }

  // MARK: - Bindable(vm.state) — the v3 stateBinding pattern

  @Test
  func `Bindable vm state fieldA write does not fire fieldB observer`() async {
    let vm = NestedClassStateVM()
    let stateBinding = Bindable(vm.state)

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      stateBinding.fieldA.wrappedValue = "via Bindable(vm.state)"
    }
    #expect(vm.state.fieldA == "via Bindable(vm.state)")
  }

  @Test
  func `Bindable vm state fieldB write fires fieldB observer`() async {
    let vm = NestedClassStateVM()
    let stateBinding = Bindable(vm.state)

    await confirmation { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      stateBinding.fieldB.wrappedValue = "via Bindable(vm.state)"
    }
  }

  // MARK: - @Bindable on State directly

  @Test
  func `Bindable projected write fires correct field observer`() async {
    let vm = ClassStateFixedVM()
    @Bindable var state = vm.state

    await confirmation { confirmed in
      withObservationTracking {
        _ = vm.state.fieldA
      } onChange: {
        confirmed()
      }
      $state.fieldA.wrappedValue = "via bindable"
    }
  }

  @Test
  func `Bindable projected write does not fire cross-field observer`() async {
    let vm = ClassStateFixedVM()
    @Bindable var state = vm.state

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      $state.fieldA.wrappedValue = "via bindable"
    }
  }

  @Test
  func `Bindable projected write mutates the state`() {
    let vm = ClassStateFixedVM()
    @Bindable var state = vm.state

    $state.fieldA.wrappedValue = "via bindable"
    #expect(vm.state.fieldA == "via bindable")
  }

  // MARK: - Nested class State (real-world pattern)

  @Test
  func `Nested updateState on fieldA does not fire fieldB observer`() async {
    let vm = NestedClassStateVM()

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      vm.updateState(\.fieldA, to: "new")
    }
  }

  @Test
  func `Nested updateState on fieldB fires its observer`() async {
    let vm = NestedClassStateVM()

    await confirmation { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      vm.updateState(\.fieldB, to: "new")
    }
  }

  @Test
  func `Nested Bindable gives per-field granularity`() async {
    let vm = NestedClassStateVM()
    @Bindable var state = vm.state

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      $state.fieldA.wrappedValue = "via bindable"
    }
  }

  // MARK: - valuesOf on class state field

  @Test
  func `valuesOf on class state field only emits when that field changes`() async throws {
    let vm = ClassStateFixedVM()
    var fieldBEmissions: [String] = []

    let task = Task {
      for await value in valuesOf({ vm.state.fieldB }) {
        fieldBEmissions.append(value)
      }
    }
    try await yieldForTracking()

    // Mutate fieldA 3 times — should NOT cause fieldB emissions
    vm.updateState(\.fieldA, to: "1")
    try await yieldForTracking()
    vm.updateState(\.fieldA, to: "2")
    try await yieldForTracking()
    vm.updateState(\.fieldA, to: "3")
    try await yieldForTracking()

    // Mutate fieldB once — should cause 1 emission
    vm.updateState(\.fieldB, to: "changed")
    try await yieldForTracking()

    task.cancel()

    // Initial "b" + one "changed" = 2 emissions total (no spurious from fieldA)
    #expect(fieldBEmissions == ["b", "changed"])
  }

  // MARK: - @ObservationIgnored in class State

  @Test
  func `ObservationIgnored field mutation does not fire observer`() async {
    let vm = ClassStateFixedVM()

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.ignored
      } onChange: {
        confirmed()
      }
      vm.state.ignored = "changed"
    }
  }

  // MARK: - Plain class (no @Observable): proves Observable is required

  @Test
  func `Plain class field write is invisible without Observable`() async {
    let vm = PlainClassStateVM()

    await confirmation(expectedCount: 0) { confirmed in
      withObservationTracking {
        _ = vm.state.fieldB
      } onChange: {
        confirmed()
      }
      vm.state.fieldB = "new"
    }
  }

}
