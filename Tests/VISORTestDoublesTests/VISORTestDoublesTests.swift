import Testing
import VISORTestDoubles

@GenerateStub
protocol FixtureService {
  @VISORTestDoubles.DefaultValue(7)
  var count: Int { get }

  @VISORTestDoubles.DefaultReturn("ready")
  func label() -> String
}

@GenerateSpy(.sendable)
nonisolated protocol ConcurrentFixtureService: Sendable {
  func record(_ value: Int)
}

@Suite
struct VISORTestDoublesTests {
  @Test
  func `Ordinary stub uses qualified custom defaults`() {
    let stub = StubFixtureService()

    #expect(stub.count == 7)
    #expect(stub.label() == "ready")
  }

  @Test
  func `Sendable spy records concurrent calls`() async {
    let spy = SpyConcurrentFixtureService()

    await withTaskGroup(of: Void.self) { group in
      for value in 0..<100 {
        group.addTask {
          spy.record(value)
        }
      }
    }

    #expect(spy.recordCallCount == 100)
    #expect(Set(spy.recordReceivedInvocations) == Set(0..<100))
  }

  @Test
  func `StubSequence preserves order`() {
    var sequence = StubSequence("first", "second")

    #expect(sequence.next() == "first")
    #expect(sequence.next() == "second")
    #expect(sequence.isEmpty)
  }
}
