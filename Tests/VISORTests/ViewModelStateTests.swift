import VISOR
import Testing

@Suite("Loadable")
struct LoadableTests {

  // MARK: - Equatable

  @Test
  func `Equatable loading equals loading`() {
    let a: Loadable<Int> = .loading
    let b: Loadable<Int> = .loading
    #expect(a == b)
  }

  @Test
  func `Equatable loaded with same value are equal`() {
    let a: Loadable<Int> = .loaded(42)
    let b: Loadable<Int> = .loaded(42)
    #expect(a == b)
  }

  @Test
  func `Equatable loaded with different values are not equal`() {
    let a: Loadable<Int> = .loaded(1)
    let b: Loadable<Int> = .loaded(2)
    #expect(a != b)
  }

  @Test
  func `Equatable different cases are not equal`() {
    let a: Loadable<Int> = .loading
    let b: Loadable<Int> = .empty
    #expect(a != b)
  }

  @Test
  func `Equatable error with same message are equal`() {
    let a: Loadable<Int> = .error("fail")
    let b: Loadable<Int> = .error("fail")
    #expect(a == b)
  }

  // MARK: - Hashable

  @Test
  func `Hashable equal values hash equally`() {
    let a: Loadable<Int> = .loaded(42)
    let b: Loadable<Int> = .loaded(42)
    #expect(a.hashValue == b.hashValue)
  }

  @Test
  func `Hashable can be used as Set element`() {
    let set: Set<Loadable<Int>> = [.loading, .loading, .empty, .loaded(1)]
    #expect(set.count == 3)
  }

  // MARK: - value

  @Test
  func `value returns value when loaded`() {
    let state: Loadable<String> = .loaded("hello")
    #expect(state.value == "hello")
  }

  @Test
  func `value returns nil when loading`() {
    let state: Loadable<String> = .loading
    #expect(state.value == nil)
  }

  @Test
  func `value returns nil when empty`() {
    let state: Loadable<String> = .empty
    #expect(state.value == nil)
  }

  @Test
  func `value returns nil when error`() {
    let state: Loadable<String> = .error("fail")
    #expect(state.value == nil)
  }

  // MARK: - isLoading

  @Test
  func `isLoading returns true when loading`() {
    let state: Loadable<Int> = .loading
    #expect(state.isLoading)
  }

  @Test
  func `isLoading returns false when loaded`() {
    let state: Loadable<Int> = .loaded(42)
    #expect(!state.isLoading)
  }

  @Test
  func `isLoading returns false when empty`() {
    let state: Loadable<Int> = .empty
    #expect(!state.isLoading)
  }

  @Test
  func `isLoading returns false when error`() {
    let state: Loadable<Int> = .error("fail")
    #expect(!state.isLoading)
  }

  // MARK: - map

  @Test
  func `map transforms loaded value`() {
    let state: Loadable<Int> = .loaded(5)
    let mapped = state.map { $0 * 2 }
    #expect(mapped == .loaded(10))
  }

  @Test
  func `map preserves loading`() {
    let state: Loadable<Int> = .loading
    let mapped = state.map { $0 * 2 }
    #expect(mapped == .loading)
  }

  @Test
  func `map preserves empty`() {
    let state: Loadable<Int> = .empty
    let mapped = state.map { $0 * 2 }
    #expect(mapped == .empty)
  }

  @Test
  func `map preserves error`() {
    let state: Loadable<Int> = .error("fail")
    let mapped = state.map { $0 * 2 }
    #expect(mapped == .error("fail"))
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
  func `flatMap preserves loading`() {
    let state: Loadable<Int> = .loading
    let result: Loadable<String> = state.flatMap { .loaded("\($0)") }
    #expect(result == .loading)
  }

  @Test
  func `flatMap preserves error`() {
    let state: Loadable<Int> = .error("fail")
    let result: Loadable<String> = state.flatMap { .loaded("\($0)") }
    #expect(result == .error("fail"))
  }

  // MARK: - Equatable Edge Cases

  @Test
  func `Equatable error with different messages are not equal`() {
    let a: Loadable<Int> = .error("fail")
    let b: Loadable<Int> = .error("crash")
    #expect(a != b)
  }

  @Test
  func `Equatable loading and error are not equal`() {
    let a: Loadable<Int> = .loading
    let b: Loadable<Int> = .error("fail")
    #expect(a != b)
  }

  @Test
  func `Equatable empty and loaded are not equal`() {
    let a: Loadable<Int> = .empty
    let b: Loadable<Int> = .loaded(0)
    #expect(a != b)
  }

  // MARK: - Complex Value Types

  @Test
  func `Works with array value type`() {
    let state: Loadable<[String]> = .loaded(["a", "b"])
    #expect(state.value == ["a", "b"])
  }

  @Test
  func `Works with optional value type`() {
    let state: Loadable<Int?> = .loaded(nil)
    #expect(state.value == Optional<Int>.none)
  }

  @Test
  func `Equatable with struct value`() {
    struct Item: Equatable { let id: Int; let name: String }
    let a: Loadable<Item> = .loaded(Item(id: 1, name: "test"))
    let b: Loadable<Item> = .loaded(Item(id: 1, name: "test"))
    let c: Loadable<Item> = .loaded(Item(id: 2, name: "other"))
    #expect(a == b)
    #expect(a != c)
  }

  // MARK: - Empty States

  @Test
  func `Equatable empty equals empty`() {
    let a: Loadable<Int> = .empty
    let b: Loadable<Int> = .empty
    #expect(a == b)
  }

  @Test
  func `Hashable all cases produce distinct hashes for typical values`() {
    let states: [Loadable<Int>] = [.loading, .empty, .loaded(0), .error("x")]
    let set = Set(states)
    #expect(set.count == 4)
  }

  // MARK: - Sendable

  @Test
  func `Sendable conformance allows cross-isolation transfer`() async {
    let state: Loadable<Int> = .loaded(42)
    let result = await Task.detached { state }.value
    #expect(result == .loaded(42))
  }

  // MARK: - Void Value

  @Test
  func `Works with Void value type`() {
    let loaded: Loadable<Void> = .loaded(())
    #expect(loaded.value != nil)

    let loading: Loadable<Void> = .loading
    #expect(loading.value == nil)

    let empty: Loadable<Void> = .empty
    #expect(empty.value == nil)

    let error: Loadable<Void> = .error("fail")
    #expect(error.value == nil)
  }

  // MARK: - Nested Loadable

  @Test
  func `Nested Loadable type`() {
    let inner: Loadable<Int> = .loaded(5)
    let outer: Loadable<Loadable<Int>> = .loaded(inner)
    #expect(outer.value == .loaded(5))
  }

  // MARK: - Dictionary Value

  @Test
  func `value with dictionary`() {
    let state: Loadable<[String: Int]> = .loaded(["a": 1, "b": 2])
    #expect(state.value == ["a": 1, "b": 2])
  }

  // MARK: - Tuple-like Struct Value

  @Test
  func `value with tuple-like struct`() {
    struct Pair: Equatable { let first: Int; let second: String }
    let state: Loadable<Pair> = .loaded(Pair(first: 1, second: "x"))
    #expect(state.value == Pair(first: 1, second: "x"))
  }

  // MARK: - Switch Exhaustiveness

  @Test
  func `switch exhaustiveness covers all cases`() {
    let cases: [Loadable<Int>] = [.loading, .empty, .loaded(0), .error("x")]
    var branchesHit = 0
    for state in cases {
      switch state {
      case .loading: branchesHit += 1
      case .empty: branchesHit += 1
      case .loaded: branchesHit += 1
      case .error: branchesHit += 1
      }
    }
    #expect(branchesHit == 4)
  }

  // MARK: - Pairwise Inequality

  @Test
  func `Equatable loaded vs error are not equal`() {
    let a: Loadable<Int> = .loaded(0)
    let b: Loadable<Int> = .error("zero")
    #expect(a != b)
  }

  // MARK: - Hashable Distinct Errors

  @Test
  func `Hashable different error messages produce distinct set entries`() {
    let set: Set<Loadable<Int>> = [.error("a"), .error("b")]
    #expect(set.count == 2)
  }
}
