import Foundation
import Testing
import VISORTesting
@testable import VISOR

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct EffectQueueStorageTests {
  @Test(arguments: 0..<4)
  func `Removing pending entries preserves FIFO order and permits reuse`(removedIndex: Int) {
    // Given
    let ids = (0..<4).map { _ in UUID() }
    var queue = _EffectPendingQueue()
    for id in ids { queue.append(id) }

    // When
    queue.remove(ids[removedIndex])
    queue.remove(ids[removedIndex])

    // Then
    #expect(queue.count == 3)
    for (index, id) in ids.enumerated() where index != removedIndex {
      #expect(queue.popFirst() == id)
    }
    #expect(queue.popFirst() == nil)
    #expect(queue.count == 0)

    // When
    queue.append(ids[removedIndex])

    // Then
    #expect(queue.popFirst() == ids[removedIndex])
    #expect(queue.count == 0)
  }

  @Test
  func `A continuously occupied queue retains only pending entries`() {
    // Given
    let ids = (0..<1_002).map { _ in UUID() }
    var queue = _EffectPendingQueue()
    queue.append(ids[0])
    queue.append(ids[1])

    // When
    for index in 0..<1_000 {
      #expect(queue.popFirst() == ids[index])
      queue.append(ids[index + 2])

      // Then
      #expect(queue.count == 2)
    }
    #expect(queue.popFirst() == ids[1_000])
    #expect(queue.popFirst() == ids[1_001])
    #expect(queue.count == 0)
  }

  @Test
  func `Repeated pending cancellation releases storage behind a suspended operation`() async throws {
    // Given
    let runtime = _EffectRuntime(policy: .serial(capacity: 2))
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = runtime.submit { _ in await operation.run(invocation) }
    try await operation.waitUntilStarted()
    var cancelledStarts = 0

    // When
    for _ in 0..<1_000 {
      let pending = runtime.submit { _ in cancelledStarts += 1 }
      pending.cancel()

      // Then
      await #expect(throws: CancellationError.self) { try await pending.value() }
      #expect(runtime.pendingCount == 0)
    }

    // When
    let last = runtime.submit { _ in 3 }
    operation.resolve(invocation, with: .success(1))

    // Then
    #expect(try await first.value() == 1)
    #expect(try await last.value() == 3)
    #expect(cancelledStarts == 0)
    #expect(runtime.pendingCount == 0)
  }
}
