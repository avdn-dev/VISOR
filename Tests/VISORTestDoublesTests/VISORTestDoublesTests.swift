import os
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

nonisolated private final class TestDoubleCopyReference: Sendable { }

nonisolated private final class TestDoubleCopyCounter: Sendable {
  private let lock = OSAllocatedUnfairLock(initialState: 0)

  var value: Int {
    lock.withLock { $0 }
  }

  func increment() {
    lock.withLock { $0 += 1 }
  }
}

nonisolated private struct TestDoubleCopyProbe: Sendable {
  private var reference = TestDoubleCopyReference()
  private let copyCounter: TestDoubleCopyCounter

  init(copyCounter: TestDoubleCopyCounter) {
    self.copyCounter = copyCounter
  }

  mutating func mutate() {
    guard !isKnownUniquelyReferenced(&reference) else { return }
    copyCounter.increment()
    reference = TestDoubleCopyReference()
  }
}

nonisolated private struct TestDoubleCopyState: Sendable {
  var retiredValue: String?
  var probe: TestDoubleCopyProbe
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
  func `Selective retirement keeps unrelated COW storage unique`() {
    let copyCounter = TestDoubleCopyCounter()
    let storage = _TestDoubleStorage(TestDoubleCopyState(
      retiredValue: "retired",
      probe: TestDoubleCopyProbe(copyCounter: copyCounter)))

    for value in 0..<100 {
      storage.withMutation(retiring: { $0.retiredValue }) { state in
        state.retiredValue = "replacement-\(value)"
        state.probe.mutate()
      }
    }

    #expect(copyCounter.value == 0)
  }

  @Test
  func `StubSequence preserves order`() {
    var sequence = StubSequence("first", "second")

    #expect(sequence.next() == "first")
    #expect(sequence.next() == "second")
    #expect(sequence.isEmpty)
  }
}
