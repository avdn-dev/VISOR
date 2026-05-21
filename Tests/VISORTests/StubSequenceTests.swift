import Testing
import VISOR

@Suite
struct StubSequenceTests {

   @Test func `next returns values in order`() {
      var sequence = StubSequence([1, 2, 3])
      #expect(sequence.next() == 1)
      #expect(sequence.next() == 2)
      #expect(sequence.next() == 3)
   }

   @Test func `remainingCount decreases after next`() {
      var sequence = StubSequence(["a", "b"])
      #expect(sequence.remainingCount == 2)
      _ = sequence.next()
      #expect(sequence.remainingCount == 1)
   }

   @Test func `isEmpty reflects consumed state`() {
      var sequence = StubSequence([true])
      #expect(!sequence.isEmpty)
      _ = sequence.next()
      #expect(sequence.isEmpty)
   }

   @Test func `variadic initialiser preserves order`() {
      var sequence = StubSequence("first", "second")
      #expect(sequence.next() == "first")
      #expect(sequence.next() == "second")
   }

   @Test func `works with Result values`() {
      enum TestError: Error { case failed }
      var sequence = StubSequence<Result<Int, any Error>>([
         .failure(TestError.failed),
         .success(42),
      ])

      #expect(throws: TestError.self) {
         try sequence.next().get()
      }
      let value = try! sequence.next().get()
      #expect(value == 42)
   }

   @Test func `works from a nonisolated helper`() {
      #expect(consumeFromNonisolatedContext() == [1, 2])
   }

   @Test func `empty array initialiser starts empty`() {
      let sequence = StubSequence([Int]())
      #expect(sequence.isEmpty)
      #expect(sequence.remainingCount == 0)
   }
}

private nonisolated func consumeFromNonisolatedContext() -> [Int] {
   var sequence = StubSequence([1, 2])
   return [sequence.next(), sequence.next()]
}
