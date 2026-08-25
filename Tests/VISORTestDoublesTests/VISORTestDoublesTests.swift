import os
import Testing
import VISORTestDoubles

// MARK: - FixtureService

@GenerateStub
protocol FixtureService {
  @VISORTestDoubles.DefaultValue(7)
  var count: Int { get }

  @VISORTestDoubles.DefaultReturn("ready")

  func label() -> String
}

// MARK: - ConcurrentFixtureService

@GenerateSpy(.sendable)
nonisolated protocol ConcurrentFixtureService: Sendable {
  func record(_ value: Int)
}

// MARK: - TestDoubleCopyReference

nonisolated private final class TestDoubleCopyReference: Sendable { }

// MARK: - TestDoubleCopyCounter

nonisolated private final class TestDoubleCopyCounter: Sendable {

  // MARK: Internal

  var value: Int {
    lock.withLock { $0 }
  }

  func increment() {
    lock.withLock { $0 += 1 }
  }

  // MARK: Private

  private let lock = OSAllocatedUnfairLock(initialState: 0)

}

// MARK: - TestDoubleCopyProbe

nonisolated private struct TestDoubleCopyProbe: Sendable {
  init(copyCounter: TestDoubleCopyCounter) {
    self.copyCounter = copyCounter
  }

  mutating func mutate() {
    guard !isKnownUniquelyReferenced(&reference) else { return }
    copyCounter.increment()
    reference = TestDoubleCopyReference()
  }

  private var reference = TestDoubleCopyReference()
  private let copyCounter: TestDoubleCopyCounter

}

// MARK: - TestDoubleCopyState

nonisolated private struct TestDoubleCopyState: Sendable {
  var retiredValue: String?
  var probe: TestDoubleCopyProbe
}

// MARK: - VISORTestDoublesTests

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
      probe: TestDoubleCopyProbe(copyCounter: copyCounter),
    ))

    for value in 0..<100 {
      storage.withMutation(retiring: { $0.retiredValue }) { state in
        state.retiredValue = "replacement-\(value)"
        state.probe.mutate()
      }
    }

    #expect(copyCounter.value == 0)
  }
}
