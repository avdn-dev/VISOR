import VISOR
import Testing

@Suite("Destination")
@MainActor
struct DestinationTests {

  @Test
  func `Equatable same cases are equal`() {
    let a: Destination<TestScene> = .push(.detail(id: "1"))
    let b: Destination<TestScene> = .push(.detail(id: "1"))
    #expect(a == b)
  }

  @Test
  func `Equatable different cases are not equal`() {
    let a: Destination<TestScene> = .push(.detail(id: "1"))
    let b: Destination<TestScene> = .push(.detail(id: "2"))
    #expect(a != b)
  }

  @Test
  func `Equatable different kinds are not equal`() {
    let a: Destination<TestScene> = .tab(.home)
    let b: Destination<TestScene> = .push(.nested)
    #expect(a != b)
  }

  @Test
  func `Hashable equal destinations hash equally`() {
    let a: Destination<TestScene> = .sheet(.preferences)
    let b: Destination<TestScene> = .sheet(.preferences)
    #expect(a.hashValue == b.hashValue)
  }

  @Test
  func `Hashable can be used as Set element`() {
    let set: Set<Destination<TestScene>> = [
      .tab(.home),
      .tab(.home),
      .push(.nested),
    ]
    #expect(set.count == 2)
  }

  // MARK: - Pairwise Cross-Case Inequality

  @Test
  func `All four destination types are pairwise unequal`() {
    let tab: Destination<TestScene> = .tab(.home)
    let push: Destination<TestScene> = .push(.nested)
    let sheet: Destination<TestScene> = .sheet(.preferences)
    let fullScreen: Destination<TestScene> = .fullScreen(.onboarding)

    #expect(tab != push)
    #expect(tab != sheet)
    #expect(tab != fullScreen)
    #expect(push != sheet)
    #expect(push != fullScreen)
    #expect(sheet != fullScreen)
  }

  // MARK: - Hashable Different Associated Values

  @Test
  func `Hashable different associated values in same case`() {
    let set: Set<Destination<TestScene>> = [
      .push(.detail(id: "a")),
      .push(.detail(id: "b")),
    ]
    #expect(set.count == 2)
  }

  @Test
  func `Hashable all four types produce distinct set entries`() {
    let set: Set<Destination<TestScene>> = [
      .tab(.home),
      .push(.nested),
      .sheet(.preferences),
      .fullScreen(.onboarding),
    ]
    #expect(set.count == 4)
  }

  // MARK: - Same-Case Equality

  @Test
  func `Equatable tab same value`() {
    let a: Destination<TestScene> = .tab(.home)
    let b: Destination<TestScene> = .tab(.home)
    #expect(a == b)
  }

  @Test
  func `Equatable fullScreen same value`() {
    let a: Destination<TestScene> = .fullScreen(.onboarding)
    let b: Destination<TestScene> = .fullScreen(.onboarding)
    #expect(a == b)
  }
}
