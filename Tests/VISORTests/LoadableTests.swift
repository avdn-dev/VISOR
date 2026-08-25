import Testing
import VISOR

// MARK: - TestFailure

enum TestFailure: Error, Equatable, Hashable, Sendable {
  case message(String)
  case negative
}

// MARK: - MappedFailure

enum MappedFailure: Error, Equatable {
  case message(String)
}

// MARK: - LoadableTests

@Suite("Loadable")
struct LoadableTests {

  // MARK: Internal

  @Test(arguments: [
    (Loadable<Int, TestFailure>.loading, true, false, false),
    (Loadable<Int, TestFailure>.empty, false, true, false),
    (Loadable<Int, TestFailure>.loaded(42), false, false, false),
    (Loadable<Int, TestFailure>.failure(.message("fail")), false, false, true),
  ])
  func `Accessors return correct booleans`(
    state: Loadable<Int, TestFailure>,
    isLoading: Bool,
    isEmpty: Bool,
    isFailure: Bool,
  ) {
    #expect(state.isLoading == isLoading)
    #expect(state.isEmpty == isEmpty)
    #expect(state.isFailure == isFailure)
  }

  @Test
  func `Value returns value when loaded and nil otherwise`() {
    #expect(Loadable<String, TestFailure>.loaded("hello").value == "hello")
    #expect(Loadable<String, TestFailure>.loading.value == nil)
    #expect(Loadable<String, TestFailure>.empty.value == nil)
    #expect(Loadable<String, TestFailure>.failure(.message("fail")).value == nil)
  }

  @Test
  func `Failure returns typed failure when failed and nil otherwise`() {
    #expect(
      Loadable<String, TestFailure>.failure(.message("something went wrong")).failure
        == .message("something went wrong")
    )
    #expect(Loadable<String, TestFailure>.loading.failure == nil)
    #expect(Loadable<String, TestFailure>.empty.failure == nil)
    #expect(Loadable<String, TestFailure>.loaded("hello").failure == nil)
  }

  @Test
  func `map transforms loaded value`() {
    let state = Loadable<Int, TestFailure>.loaded(5)
    let mapped = state.map { $0 * 2 }
    #expect(mapped == .loaded(10))
  }

  @Test
  func `map preserves non-loaded cases`() {
    #expect(Loadable<Int, TestFailure>.loading.map { $0 * 2 } == .loading)
    #expect(Loadable<Int, TestFailure>.empty.map { $0 * 2 } == .empty)
    #expect(
      Loadable<Int, TestFailure>.failure(.message("fail")).map { $0 * 2 }
        == .failure(.message("fail"))
    )
  }

  @Test
  func `mapFailure transforms typed failure`() {
    let state = Loadable<Int, TestFailure>.failure(.message("offline"))
    let mapped: Loadable<Int, MappedFailure> = state.mapFailure { failure in
      switch failure {
      case .message(let message): .message(message)
      case .negative: .message("negative")
      }
    }

    #expect(mapped == Loadable<Int, MappedFailure>.failure(.message("offline")))
  }

  @Test
  func `mapFailure preserves non-failure cases`() {
    let loaded = Loadable<Int, TestFailure>.loaded(42)
    let mapped: Loadable<Int, MappedFailure> = loaded.mapFailure { _ in .message("unused") }

    #expect(mapped == .loaded(42))
  }

  @Test
  func `flatMap transforms loaded value`() {
    let state = Loadable<Int, TestFailure>.loaded(5)
    let result = state.flatMap { .loaded("\($0)") }
    #expect(result == .loaded("5"))
  }

  @Test
  func `flatMap can return different case`() {
    let state = Loadable<Int, TestFailure>.loaded(0)
    let result = state.flatMap { $0 == 0 ? .empty : .loaded("\($0)") }
    #expect(result == .empty)
  }

  @Test
  func `flatMap can return failure from loaded`() {
    let state = Loadable<Int, TestFailure>.loaded(-1)
    let result = state.flatMap { $0 < 0 ? .failure(.negative) : .loaded("\($0)") }
    #expect(result == .failure(.negative))
  }

  @Test
  func `flatMap preserves non-loaded cases`() {
    let loading = Loadable<Int, TestFailure>.loading
    let result1: Loadable<String, TestFailure> = loading.flatMap { .loaded("\($0)") }
    #expect(result1 == .loading)

    let empty = Loadable<Int, TestFailure>.empty
    let result2: Loadable<String, TestFailure> = empty.flatMap { .loaded("\($0)") }
    #expect(result2 == .empty)

    let failure = Loadable<Int, TestFailure>.failure(.message("fail"))
    let result3: Loadable<String, TestFailure> = failure.flatMap { .loaded("\($0)") }
    #expect(result3 == .failure(.message("fail")))
  }

  @Test
  func `Equatable same cases are equal`() {
    #expect(Loadable<Int, TestFailure>.loading == .loading)
    #expect(Loadable<Int, TestFailure>.empty == .empty)
    #expect(Loadable<Int, TestFailure>.loaded(42) == .loaded(42))
    #expect(Loadable<Int, TestFailure>.failure(.message("fail")) == .failure(.message("fail")))
  }

  @Test
  func `Equatable different cases are not equal`() {
    #expect(Loadable<Int, TestFailure>.loading != .empty)
    #expect(Loadable<Int, TestFailure>.loading != .loaded(0))
    #expect(Loadable<Int, TestFailure>.loading != .failure(.message("")))
    #expect(Loadable<Int, TestFailure>.empty != .loaded(0))
    #expect(Loadable<Int, TestFailure>.loaded(1) != .loaded(2))
    #expect(
      Loadable<String, TestFailure>.failure(.message("a"))
        != .failure(.message("b"))
    )
  }

  @Test
  func `Hashable consistency with Equatable`() {
    let a = Loadable<Int, TestFailure>.loaded(42)
    let b = Loadable<Int, TestFailure>.loaded(42)
    #expect(a.hashValue == b.hashValue)

    let set: Set<Loadable<Int, TestFailure>> = [
      .loading,
      .empty,
      .loaded(1),
      .failure(.message("e")),
    ]
    #expect(set.count == 4)
  }

  @Test
  func `Sendable conformance includes value and failure`() {
    let state = Loadable<Int, TestFailure>.failure(.negative)

    requireSendable(state)
  }

  @Test
  func `map transforms value type`() {
    let state = Loadable<Int, TestFailure>.loaded(42)
    let mapped: Loadable<String, TestFailure> = state.map { "\($0)" }
    #expect(mapped == .loaded("42"))
  }

  @Test
  func `map does not invoke closure for non-loaded cases`() {
    var callCount = 0
    _ = Loadable<Int, TestFailure>.loading.map {
      callCount += 1
      return $0
    }
    _ = Loadable<Int, TestFailure>.empty.map {
      callCount += 1
      return $0
    }
    _ = Loadable<Int, TestFailure>.failure(.message("e")).map {
      callCount += 1
      return $0
    }
    #expect(callCount == 0)
  }

  @Test
  func `flatMap flattens nested Loadable`() {
    let nested = Loadable<Loadable<Int, TestFailure>, TestFailure>.loaded(.loaded(42))
    let flat = nested.flatMap { $0 }
    #expect(flat == .loaded(42))
  }

  @Test
  func `Loaded empty collection is distinct from empty case`() {
    let loaded = Loadable<[String], TestFailure>.loaded([])
    let empty = Loadable<[String], TestFailure>.empty

    #expect(loaded != empty)
    #expect(loaded.value == [])
    #expect(loaded.isEmpty == false)
    #expect(empty.value == nil)
    #expect(empty.isEmpty == true)
  }

  @Test
  func `Loadable supports Void as Value type`() {
    let loaded = Loadable<Void, TestFailure>.loaded(())
    #expect(loaded.value != nil)

    let loading = Loadable<Void, TestFailure>.loading
    #expect(loading.value == nil)
  }

  // MARK: Private

  private func requireSendable(_: some Sendable) { }
}
