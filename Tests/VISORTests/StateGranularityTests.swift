import Observation
import SwiftUI
import Testing
import VISOR

// MARK: - Class State Fixtures

/// @Observable class State — per-field tracking.
@Observable
private final class ClassState: @preconcurrency Equatable {
  var fieldA = "a"
  var fieldB = "b"
  @ObservationIgnored var ignored = "ignored"

  init(fieldA: String = "a", fieldB: String = "b", ignored: String = "ignored") {
    self.fieldA = fieldA
    self.fieldB = fieldB
    self.ignored = ignored
  }

  static func == (lhs: ClassState, rhs: ClassState) -> Bool {
    lhs.fieldA == rhs.fieldA && lhs.fieldB == rhs.fieldB && lhs.ignored == rhs.ignored
  }
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
  final class State: @preconcurrency Equatable {
    var fieldA = "a"
    var fieldB = "b"

    init(fieldA: String = "a", fieldB: String = "b") {
      self.fieldA = fieldA
      self.fieldB = fieldB
    }

    static func == (lhs: State, rhs: State) -> Bool {
      lhs.fieldA == rhs.fieldA && lhs.fieldB == rhs.fieldB
    }
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
private final class PlainClassState: @preconcurrency Equatable {
  var fieldA = "a"
  var fieldB = "b"

  init(fieldA: String = "a", fieldB: String = "b") {
    self.fieldA = fieldA
    self.fieldB = fieldB
  }

  static func == (lhs: PlainClassState, rhs: PlainClassState) -> Bool {
    lhs.fieldA == rhs.fieldA && lhs.fieldB == rhs.fieldB
  }
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

  @Test("updateState fieldA does NOT fire fieldB observer")
  func fixed_updateState_noCrossFieldFire() async {
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

  @Test("updateState fieldB DOES fire its observer")
  func fixed_updateState_sameFieldFires() async {
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

  @Test("updateState dedup still works")
  func fixed_updateState_sameValue_noFire() async {
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

  @Test("3 fieldA updateState calls → 0 spurious fieldB fires")
  func fixed_repeatedUpdateState_noCrossFieldFires() async {
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

  @Test("Bindable(vm.state).fieldA write does NOT fire fieldB observer")
  func bindableVMState_noCrossField() async {
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

  @Test("Bindable(vm.state).fieldB write DOES fire fieldB observer")
  func bindableVMState_sameFieldFires() async {
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

  @Test("@Bindable<State> projected write fires correct field observer")
  func bindable_projectedWrite_firesCorrectObserver() async {
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

  @Test("@Bindable<State> projected write does NOT fire cross-field")
  func bindable_projectedWrite_noCrossFieldFire() async {
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

  @Test("@Bindable<State> projected write mutates the state")
  func bindable_projectedWrite_mutatesState() {
    let vm = ClassStateFixedVM()
    @Bindable var state = vm.state

    $state.fieldA.wrappedValue = "via bindable"
    #expect(vm.state.fieldA == "via bindable")
  }

  // MARK: - Nested class State (real-world pattern)

  @Test("Nested: updateState fieldA does NOT fire fieldB observer")
  func nested_updateState_noCrossFieldFire() async {
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

  @Test("Nested: updateState fieldB DOES fire its observer")
  func nested_updateState_sameFieldFires() async {
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

  @Test("Nested: Equatable compares by value")
  func nested_equatableByValue() {
    let vm = NestedClassStateVM()
    let other = NestedClassStateVM.State(fieldA: "a", fieldB: "b")
    #expect(vm.state == other)
    vm.updateState(\.fieldA, to: "new")
    #expect(vm.state != other)
  }

  @Test("Nested: @Bindable gives per-field granularity")
  func nested_bindable_noCrossFieldFire() async {
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

  @Test("valuesOf on class state field only emits when THAT field changes")
  func valuesOf_classState_perFieldEmission() async throws {
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

  @Test("@ObservationIgnored field: mutation does NOT fire observer")
  func observationIgnored_mutationInvisible() async {
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

  @Test("@ObservationIgnored field: still included in Equatable comparison")
  func observationIgnored_stillInEquatable() {
    let a = ClassState(fieldA: "a", fieldB: "b", ignored: "x")
    let b = ClassState(fieldA: "a", fieldB: "b", ignored: "y")
    #expect(a != b)
  }

  // MARK: - Plain class (no @Observable): proves Observable is required

  @Test("Plain class: field write is INVISIBLE (no per-field tracking)")
  func plainClass_fieldWriteInvisible() async {
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

  // MARK: - Equatable

  @Test("Equatable compares by value, not reference")
  func classState_equatableByValue() {
    let vm = ClassStateFixedVM()
    let other = ClassState(fieldA: "a", fieldB: "b")
    #expect(vm.state == other)

    vm.state.fieldA = "new"
    #expect(vm.state != other)
  }

  @Test("Snapshot comparison uses a fresh expected instance, not a captured reference")
  func snapshot_compareAgainstExpected() {
    let vm = ClassStateFixedVM()
    vm.updateState(\.fieldA, to: "updated")
    vm.updateState(\.fieldB, to: "changed")

    #expect(vm.state == ClassState(fieldA: "updated", fieldB: "changed"))
  }
}
