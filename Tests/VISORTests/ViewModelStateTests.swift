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
}
