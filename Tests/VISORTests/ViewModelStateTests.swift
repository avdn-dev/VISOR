import VISOR
import Testing

@Suite("ViewModelState")
struct ViewModelStateTests {

  // MARK: - Equatable

  @Test
  func `Equatable loading equals loading`() {
    let a: ViewModelState<Int> = .loading
    let b: ViewModelState<Int> = .loading
    #expect(a == b)
  }

  @Test
  func `Equatable loaded with same state are equal`() {
    let a: ViewModelState<Int> = .loaded(state: 42)
    let b: ViewModelState<Int> = .loaded(state: 42)
    #expect(a == b)
  }

  @Test
  func `Equatable loaded with different state are not equal`() {
    let a: ViewModelState<Int> = .loaded(state: 1)
    let b: ViewModelState<Int> = .loaded(state: 2)
    #expect(a != b)
  }

  @Test
  func `Equatable different cases are not equal`() {
    let a: ViewModelState<Int> = .loading
    let b: ViewModelState<Int> = .empty
    #expect(a != b)
  }

  @Test
  func `Equatable error with same message are equal`() {
    let a: ViewModelState<Int> = .error("fail")
    let b: ViewModelState<Int> = .error("fail")
    #expect(a == b)
  }

  // MARK: - Hashable

  @Test
  func `Hashable equal states hash equally`() {
    let a: ViewModelState<Int> = .loaded(state: 42)
    let b: ViewModelState<Int> = .loaded(state: 42)
    #expect(a.hashValue == b.hashValue)
  }

  @Test
  func `Hashable can be used as Set element`() {
    let set: Set<ViewModelState<Int>> = [.loading, .loading, .empty, .loaded(state: 1)]
    #expect(set.count == 3)
  }

  // MARK: - loadedState

  @Test
  func `loadedState returns state when loaded`() {
    let state: ViewModelState<String> = .loaded(state: "hello")
    #expect(state.loadedState == "hello")
  }

  @Test
  func `loadedState returns nil when loading`() {
    let state: ViewModelState<String> = .loading
    #expect(state.loadedState == nil)
  }

  @Test
  func `loadedState returns nil when empty`() {
    let state: ViewModelState<String> = .empty
    #expect(state.loadedState == nil)
  }

  @Test
  func `loadedState returns nil when error`() {
    let state: ViewModelState<String> = .error("fail")
    #expect(state.loadedState == nil)
  }

  // MARK: - Equatable Edge Cases

  @Test
  func `Equatable error with different messages are not equal`() {
    let a: ViewModelState<Int> = .error("fail")
    let b: ViewModelState<Int> = .error("crash")
    #expect(a != b)
  }

  @Test
  func `Equatable loading and error are not equal`() {
    let a: ViewModelState<Int> = .loading
    let b: ViewModelState<Int> = .error("fail")
    #expect(a != b)
  }

  @Test
  func `Equatable empty and loaded are not equal`() {
    let a: ViewModelState<Int> = .empty
    let b: ViewModelState<Int> = .loaded(state: 0)
    #expect(a != b)
  }

  // MARK: - Complex State Types

  @Test
  func `Works with array state type`() {
    let state: ViewModelState<[String]> = .loaded(state: ["a", "b"])
    #expect(state.loadedState == ["a", "b"])
  }

  @Test
  func `Works with optional state type`() {
    let state: ViewModelState<Int?> = .loaded(state: nil)
    #expect(state.loadedState == Optional<Int>.none)
  }

  @Test
  func `Equatable with struct state`() {
    struct Item: Equatable { let id: Int; let name: String }
    let a: ViewModelState<Item> = .loaded(state: Item(id: 1, name: "test"))
    let b: ViewModelState<Item> = .loaded(state: Item(id: 1, name: "test"))
    let c: ViewModelState<Item> = .loaded(state: Item(id: 2, name: "other"))
    #expect(a == b)
    #expect(a != c)
  }

  // MARK: - Empty States

  @Test
  func `Equatable empty equals empty`() {
    let a: ViewModelState<Int> = .empty
    let b: ViewModelState<Int> = .empty
    #expect(a == b)
  }

  @Test
  func `Hashable all cases produce distinct hashes for typical values`() {
    let states: [ViewModelState<Int>] = [.loading, .empty, .loaded(state: 0), .error("x")]
    let set = Set(states)
    #expect(set.count == 4)
  }

  // MARK: - Sendable

  @Test
  func `Sendable conformance allows cross-isolation transfer`() async {
    let state: ViewModelState<Int> = .loaded(state: 42)
    let result = await Task.detached { state }.value
    #expect(result == .loaded(state: 42))
  }

  // MARK: - Void State

  @Test
  func `Works with Void state type`() {
    let loaded: ViewModelState<Void> = .loaded(state: ())
    #expect(loaded.loadedState != nil)

    let loading: ViewModelState<Void> = .loading
    #expect(loading.loadedState == nil)

    let empty: ViewModelState<Void> = .empty
    #expect(empty.loadedState == nil)

    let error: ViewModelState<Void> = .error("fail")
    #expect(error.loadedState == nil)
  }

  // MARK: - Nested State

  @Test
  func `Nested ViewModelState type`() {
    let inner: ViewModelState<Int> = .loaded(state: 5)
    let outer: ViewModelState<ViewModelState<Int>> = .loaded(state: inner)
    #expect(outer.loadedState == .loaded(state: 5))
  }

  // MARK: - Dictionary State

  @Test
  func `loadedState with dictionary state`() {
    let state: ViewModelState<[String: Int]> = .loaded(state: ["a": 1, "b": 2])
    #expect(state.loadedState == ["a": 1, "b": 2])
  }

  // MARK: - Tuple-like Struct State

  @Test
  func `loadedState with tuple-like struct`() {
    struct Pair: Equatable { let first: Int; let second: String }
    let state: ViewModelState<Pair> = .loaded(state: Pair(first: 1, second: "x"))
    #expect(state.loadedState == Pair(first: 1, second: "x"))
  }

  // MARK: - Switch Exhaustiveness

  @Test
  func `switch exhaustiveness covers all cases`() {
    let cases: [ViewModelState<Int>] = [.loading, .empty, .loaded(state: 0), .error("x")]
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
    let a: ViewModelState<Int> = .loaded(state: 0)
    let b: ViewModelState<Int> = .error("zero")
    #expect(a != b)
  }

  // MARK: - Hashable Distinct Errors

  @Test
  func `Hashable different error messages produce distinct set entries`() {
    let set: Set<ViewModelState<Int>> = [.error("a"), .error("b")]
    #expect(set.count == 2)
  }
}
