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
}
