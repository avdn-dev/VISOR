import VISOR
import Testing

@Suite("Loadable")
struct LoadableTests {

  // MARK: - Accessors (parametric)

  @Test(arguments: [
    (Loadable<Int>.loading, true, false, false),
    (Loadable<Int>.empty, false, true, false),
    (Loadable<Int>.loaded(42), false, false, false),
    (Loadable<Int>.error("fail"), false, false, true),
  ])
  func `Accessors return correct booleans`(
    state: Loadable<Int>, isLoading: Bool, isEmpty: Bool, isError: Bool
  ) {
    #expect(state.isLoading == isLoading)
    #expect(state.isEmpty == isEmpty)
    #expect(state.isError == isError)
  }

  @Test
  func `Value returns value when loaded and nil otherwise`() {
    #expect(Loadable<String>.loaded("hello").value == "hello")
    #expect(Loadable<String>.loading.value == nil)
    #expect(Loadable<String>.empty.value == nil)
    #expect(Loadable<String>.error("fail").value == nil)
  }

  @Test
  func `Error returns message when error and nil otherwise`() {
    #expect(Loadable<String>.error("something went wrong").error == "something went wrong")
    #expect(Loadable<String>.loading.error == nil)
    #expect(Loadable<String>.empty.error == nil)
    #expect(Loadable<String>.loaded("hello").error == nil)
  }

  // MARK: - map

  @Test
  func `map transforms loaded value`() {
    let state: Loadable<Int> = .loaded(5)
    let mapped = state.map { $0 * 2 }
    #expect(mapped == .loaded(10))
  }

  @Test
  func `map preserves non-loaded cases`() {
    #expect(Loadable<Int>.loading.map { $0 * 2 } == .loading)
    #expect(Loadable<Int>.empty.map { $0 * 2 } == .empty)
    #expect(Loadable<Int>.error("fail").map { $0 * 2 } == .error("fail"))
  }

  // MARK: - flatMap

  @Test
  func `flatMap transforms loaded value`() {
    let state: Loadable<Int> = .loaded(5)
    let result = state.flatMap { .loaded("\($0)") }
    #expect(result == .loaded("5"))
  }

  @Test
  func `flatMap can return different case`() {
    let state: Loadable<Int> = .loaded(0)
    let result = state.flatMap { $0 == 0 ? .empty : .loaded("\($0)") }
    #expect(result == .empty)
  }

  @Test
  func `flatMap can return error from loaded`() {
    let state: Loadable<Int> = .loaded(-1)
    let result = state.flatMap { $0 < 0 ? .error("negative") : .loaded("\($0)") }
    #expect(result == .error("negative"))
  }

  @Test
  func `flatMap preserves non-loaded cases`() {
    let loading: Loadable<Int> = .loading
    let result1: Loadable<String> = loading.flatMap { .loaded("\($0)") }
    #expect(result1 == .loading)

    let empty: Loadable<Int> = .empty
    let result2: Loadable<String> = empty.flatMap { .loaded("\($0)") }
    #expect(result2 == .empty)

    let error: Loadable<Int> = .error("fail")
    let result3: Loadable<String> = error.flatMap { .loaded("\($0)") }
    #expect(result3 == .error("fail"))
  }

  // MARK: - Equatable

  @Test
  func `Equatable same cases are equal`() {
    #expect(Loadable<Int>.loading == .loading)
    #expect(Loadable<Int>.empty == .empty)
    #expect(Loadable<Int>.loaded(42) == .loaded(42))
    #expect(Loadable<Int>.error("fail") == .error("fail"))
  }

  @Test
  func `Equatable different cases are not equal`() {
    #expect(Loadable<Int>.loading != .empty)
    #expect(Loadable<Int>.loading != .loaded(0))
    #expect(Loadable<Int>.loading != .error(""))
    #expect(Loadable<Int>.empty != .loaded(0))
    #expect(Loadable<Int>.loaded(1) != .loaded(2))
    #expect(Loadable<String>.error("a") != .error("b"))
  }

  @Test
  func `Hashable consistency with Equatable`() {
    let a: Loadable<Int> = .loaded(42)
    let b: Loadable<Int> = .loaded(42)
    #expect(a.hashValue == b.hashValue)

    let set: Set<Loadable<Int>> = [.loading, .empty, .loaded(1), .error("e")]
    #expect(set.count == 4)
  }

  // MARK: - map edge cases

  @Test
  func `map transforms value type`() {
    let state: Loadable<Int> = .loaded(42)
    let mapped: Loadable<String> = state.map { "\($0)" }
    #expect(mapped == .loaded("42"))
  }

  @Test
  func `map does not invoke closure for non-loaded cases`() {
    var callCount = 0
    _ = Loadable<Int>.loading.map { callCount += 1; return $0 }
    _ = Loadable<Int>.empty.map { callCount += 1; return $0 }
    _ = Loadable<Int>.error("e").map { callCount += 1; return $0 }
    #expect(callCount == 0)
  }

  // MARK: - flatMap edge cases

  @Test
  func `flatMap flattens nested Loadable`() {
    let nested: Loadable<Loadable<Int>> = .loaded(.loaded(42))
    let flat = nested.flatMap { $0 }
    #expect(flat == .loaded(42))
  }

  // MARK: - Void Value

  @Test
  func `Works with Void value type`() {
    let loaded: Loadable<Void> = .loaded(())
    #expect(loaded.value != nil)

    let loading: Loadable<Void> = .loading
    #expect(loading.value == nil)
  }
}
