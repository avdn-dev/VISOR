import Testing
import VISORTestDoubles

// MARK: - StubSequenceTests

@Suite
struct StubSequenceTests {

  @Test
  func `next returns values in order`() {
    var sequence = StubSequence([1, 2, 3])
    #expect(sequence.next() == 1)
    #expect(sequence.next() == 2)
    #expect(sequence.next() == 3)
  }

  @Test
  func `remainingCount decreases after next`() {
    var sequence = StubSequence(["a", "b"])
    #expect(sequence.remainingCount == 2)
    _ = sequence.next()
    #expect(sequence.remainingCount == 1)
  }

  @Test
  func `isEmpty reflects consumed state`() {
    var sequence = StubSequence([true])
    #expect(!sequence.isEmpty)
    _ = sequence.next()
    #expect(sequence.isEmpty)
  }

  @Test
  func `variadic initialiser preserves order`() {
    var sequence = StubSequence("first", "second")
    #expect(sequence.next() == "first")
    #expect(sequence.next() == "second")
  }

  @Test
  func `copies advance independently`() {
    var original = StubSequence([1, 2])
    var copy = original

    #expect(original.next() == 1)
    #expect(copy.next() == 1)
    #expect(original.next() == 2)
    #expect(copy.next() == 2)
    #expect(original.isEmpty)
    #expect(copy.isEmpty)
  }

  @Test
  func `works with Result values`() throws {
    enum TestError: Error { case failed }
    var sequence = StubSequence<Result<Int, any Error>>([
      .failure(TestError.failed),
      .success(42),
    ])

    #expect(throws: TestError.self) {
      try sequence.next().get()
    }
    let value = try sequence.next().get()
    #expect(value == 42)
  }

  @Test
  func `works from a nonisolated helper`() {
    #expect(consumeFromNonisolatedContext() == [1, 2])
  }

  @Test
  func `empty array initialiser starts empty`() {
    let sequence = StubSequence([Int]())
    #expect(sequence.isEmpty)
    #expect(sequence.remainingCount == 0)
  }

  @Test
  func `exhausted diagnostic names value type`() {
    let message = StubSequenceDiagnostics.exhaustedMessage(for: Int.self)

    #expect(message.contains("StubSequence<"))
    #expect(message.contains("Int"))
    #expect(message.contains("next()"))
  }
}

private nonisolated func consumeFromNonisolatedContext() -> [Int] {
  var sequence = StubSequence([1, 2])
  return [sequence.next(), sequence.next()]
}
