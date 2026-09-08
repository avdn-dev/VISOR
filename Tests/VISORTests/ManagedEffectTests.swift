import Testing
import VISOR
import VISORTesting

// MARK: - ManagedEffectTestError

private enum ManagedEffectTestError: Error, Equatable {
  case expected
}

// MARK: - EffectRecipient

@MainActor
private final class EffectRecipient {

  // MARK: Lifecycle

  deinit { }

  // MARK: Internal

  var values = [Int]()
  var failures = 0
  let latest = LatestEffect()
}

// MARK: - ManagedEffectTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ManagedEffectTests {
  @Test
  func `Completed handles cannot cancel a later invocation`() async throws {
    // Given
    let effect = LatestEffect()
    let completed = effect.run { 1 }
    _ = try await completed.value()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let current = effect.run { await operation.run(invocation) }
    try await operation.waitUntilStarted()

    // When
    completed.cancel()
    operation.resolve(invocation, with: .success(2))

    // Then
    #expect(try await completed.value() == 1)
    #expect(try await current.value() == 2)
    #expect(operation.cancelledCount == 0)
  }

  @Test
  func `Cancellation and supersession retain their first reason`() async throws {
    // Given
    let effect = LatestEffect()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = effect.run { await operation.run(invocation) }
    try await operation.waitUntilStarted()

    // When
    first.cancel()
    let second = effect.run { 2 }
    operation.resolve(invocation, with: .success(1))

    // Then
    await #expect(throws: CancellationError.self) { try await first.value() }
    #expect(try await second.value() == 2)
  }

  @Test
  func `Cancel all removes pending work and permits new serial submissions`() async throws {
    // Given
    let queue = SerialEffectQueue()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = queue.enqueue { await operation.run(invocation) }
    try await operation.waitUntilStarted()
    var cancelledStarts = 0
    let pending = (0..<20).map { _ in queue.enqueue { cancelledStarts += 1 } }

    // When
    queue.cancelAll()
    let new = queue.enqueue { 3 }
    for handle in pending {
      await #expect(throws: CancellationError.self) { try await handle.value() }
    }
    operation.resolve(invocation, with: .success(1))

    // Then
    #expect(try await new.value() == 3)
    #expect(cancelledStarts == 0)
    await #expect(throws: CancellationError.self) { try await first.value() }
  }

  @Test
  func `Concurrent receivers deliver failures and successes independently`() async throws {
    // Given
    let effects = ConcurrentEffects()
    let target = EffectRecipient()

    // When
    let failure = effects.run(for: target, operation: { () async throws -> Int in
      throw ManagedEffectTestError.expected
    }) { target, result in
      if case .failure = result { target.failures += 1 }
    }
    let success = effects.run(for: target) { 2 } receive: { target, value in
      target.values.append(value)
    }
    await effects.finish()

    // Then
    #expect(target.failures == 1)
    #expect(target.values == [2])
    #expect(try await success.value() == 2)
    await #expect(throws: ManagedEffectTestError.expected) { try await failure.value() }
  }

  @Test
  func `Full queue delivers admission failure without executing preparation`() async throws {
    // Given
    let queue = SerialEffectQueue(capacity: 1)
    let target = EffectRecipient()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = queue.enqueue { await operation.run(invocation) }
    try await operation.waitUntilStarted()
    var didPrepare = false

    // When
    let rejected = queue.enqueue(for: target, operation: { () async throws -> Int in
      didPrepare = true
      return 2
    }) { target, result in
      if case .failure(let error) = result, error is EffectQueueFullError { target.failures += 1 }
    }

    // Then
    #expect(target.failures == 1)
    #expect(!didPrepare)
    await #expect(throws: EffectQueueFullError.self) { try await rejected.value() }

    // When
    operation.resolve(invocation, with: .success(1))
    _ = try await first.value()
  }

  @Test
  func `Latest suppresses stale success even when preparation ignores cancellation`() async throws {
    // Given
    let effect = LatestEffect()
    let target = EffectRecipient()
    let operation = ControllableOperation<Int, Never>()
    let firstInvocation = operation.prepare()
    let first = effect.run(for: target) {
      await operation.run(firstInvocation)
    } receive: { target, value in target.values.append(value) }
    try await operation.waitUntilStarted()

    // When
    let second = effect.run(for: target) { 2 } receive: { target, value in
      target.values.append(value)
    }
    _ = try await second.value()
    operation.resolve(firstInvocation, with: .success(1))

    // Then
    guard case .superseded = await first.result else {
      Issue.record("Expected the earlier invocation to be superseded")
      return
    }
    #expect(target.values == [2])
    #expect(operation.cancelledCount == 1)
  }

  @Test
  func `Rapid replacements skip preparations that have not started`() async throws {
    // Given
    let effect = LatestEffect()
    let target = EffectRecipient()
    var starts = [Int]()

    // When
    let first = effect.run { starts.append(1)
      return 1
    }
    let second = effect.run { starts.append(2)
      return 2
    }
    let third = effect.run(for: target) { starts.append(3)
      return 3
    } receive: { target, value in
      target.values.append(value)
    }
    _ = try await third.value()
    await effect.finish()

    // Then
    #expect(starts == [3])
    #expect(target.values == [3])
    await #expect(throws: EffectSupersededError.self) { try await first.value() }
    await #expect(throws: EffectSupersededError.self) { try await second.value() }
  }

  @Test
  func `Stale failure is suppressed and current failure is delivered`() async throws {
    // Given
    let effect = LatestEffect()
    let target = EffectRecipient()
    let operation = ControllableOperation<Int, ManagedEffectTestError>()
    let invocation = operation.prepare()
    let first = effect.run(for: target) {
      try await operation.run(invocation)
    } receive: { target, result in
      if case .failure = result { target.failures += 1 }
    }
    try await operation.waitUntilStarted()

    // When
    let second = effect.run(for: target, operation: { () async throws -> Int in
      throw ManagedEffectTestError.expected
    }) { target, result in
      if case .failure = result { target.failures += 1 }
    }
    _ = await second.result
    operation.resolve(invocation, with: .failure(.expected))
    _ = await first.result

    // Then
    #expect(target.failures == 1)
    await #expect(throws: ManagedEffectTestError.expected) { try await second.value() }
  }

  @Test
  func `Reentrant receiver can replace itself without losing the new invocation`() async throws {
    // Given
    let target = EffectRecipient()
    var replacement: EffectHandle<Int>?

    // When
    let first = target.latest.run(for: target) { 1 } receive: { target, value in
      target.values.append(value)
      replacement = target.latest.run(for: target) { 2 } receive: { target, value in
        target.values.append(value)
      }
    }
    _ = try await first.value()
    let second = try #require(replacement)
    _ = try await second.value()

    // Then
    #expect(target.values == [1, 2])
  }

  @Test
  func `Cancellation callbacks can replace the incoming latest invocation`() async throws {
    // Given
    let target = EffectRecipient()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    var replacement: EffectHandle<Int>?
    var starts = [Int]()
    let first = target.latest.run(for: target) {
      starts.append(1)
      return await withTaskCancellationHandler {
        await operation.run(invocation)
      } onCancel: { [weak target] in
        // This invocation is only cancelled synchronously from MainActor below.
        MainActor.assumeIsolated {
          guard let target else { return }
          replacement = target.latest.run(for: target) {
            starts.append(3)
            return 3
          } receive: { target, value in
            target.values.append(value)
          }
        }
      }
    } receive: { target, value in
      target.values.append(value)
    }
    try await operation.waitUntilStarted()

    // When
    let second = target.latest.run(for: target) {
      starts.append(2)
      return 2
    } receive: { target, value in
      target.values.append(value)
    }
    operation.resolve(invocation, with: .success(1))
    let newest = try #require(replacement)
    _ = try await newest.value()
    await target.latest.finish()

    // Then
    #expect(starts == [1, 3])
    #expect(target.values == [3])
    await #expect(throws: EffectSupersededError.self) { try await first.value() }
    await #expect(throws: EffectSupersededError.self) { try await second.value() }
  }

  @Test
  func `Cancelling a running handle waits for cleanup and suppresses delivery`() async throws {
    // Given
    let effect = LatestEffect()
    let target = EffectRecipient()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let handle = effect.run(for: target) { await operation.run(invocation) } receive: { target, value in
      target.values.append(value)
    }
    try await operation.waitUntilStarted()
    var completed = false
    let waiter = Task { _ = await handle.result
      completed = true
    }

    // When
    handle.cancel()
    try await operation.waitUntilCancelled()

    // Then
    #expect(!completed)
    #expect(operation.finishedCount == 0)

    // When
    operation.resolve(invocation, with: .success(1))
    await waiter.value

    // Then
    #expect(completed)
    #expect(target.values.isEmpty)
    await #expect(throws: CancellationError.self) { try await handle.value() }
  }

  @Test
  func `Cancelling a waiter does not cancel its operation`() async throws {
    // Given
    let effects = ConcurrentEffects()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let handle = effects.run { await operation.run(invocation) }
    try await operation.waitUntilStarted()
    let waiter = Task { try await handle.value() }

    // When
    waiter.cancel()
    operation.resolve(invocation, with: .success(3))

    // Then
    #expect(try await waiter.value == 3)
    #expect(operation.cancelledCount == 0)
  }

  @Test
  func `Weak delivery permits the model and its effect owner to deinitialise`() async throws {
    // Given
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    var target: EffectRecipient? = EffectRecipient()
    weak let reference = target
    let handle: EffectHandle<Int>
    do {
      let owner = try #require(target)
      handle = owner.latest.run(for: owner) {
        await operation.run(invocation)
      } receive: { target, value in target.values.append(value) }
    }
    try await operation.waitUntilStarted()

    // When
    target = nil
    try await operation.waitUntilCancelled()
    operation.resolve(invocation, with: .success(1))

    // Then
    #expect(reference == nil)
    await #expect(throws: CancellationError.self) { try await handle.value() }
  }

  @Test
  func `Serial queue preserves order across awaits and a failed operation`() async throws {
    // Given
    let queue = SerialEffectQueue()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    var order = [Int]()
    let first = queue.enqueue { order.append(1)
      return await operation.run(invocation)
    }
    try await operation.waitUntilStarted()

    // When
    let failed = queue.enqueue { () async throws -> Int in
      order.append(2)
      throw ManagedEffectTestError.expected
    }
    let last = queue.enqueue { order.append(3)
      return 3
    }

    // Then
    #expect(order == [1])

    // When
    operation.resolve(invocation, with: .success(1))
    _ = try await last.value()

    // Then
    #expect(order == [1, 2, 3])
    #expect(try await first.value() == 1)
    await #expect(throws: ManagedEffectTestError.expected) { try await failed.value() }
  }

  @Test
  func `Pending cancellation completes without starting or blocking later queued work`() async throws {
    // Given
    let queue = SerialEffectQueue()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = queue.enqueue { await operation.run(invocation) }
    try await operation.waitUntilStarted()
    var ranCancelledWork = false
    let pending = queue.enqueue { ranCancelledWork = true
      return 2
    }
    let last = queue.enqueue { 3 }

    // When
    pending.cancel()

    // Then
    await #expect(throws: CancellationError.self) { try await pending.value() }
    #expect(!ranCancelledWork)
    #expect(operation.finishedCount == 0)

    // When
    operation.resolve(invocation, with: .success(1))
    _ = try await first.value()

    // Then
    #expect(try await last.value() == 3)
  }

  @Test
  func `Cancelling serial work never overlaps the next invocation with cleanup`() async throws {
    // Given
    let queue = SerialEffectQueue()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = queue.enqueue { await operation.run(invocation) }
    try await operation.waitUntilStarted()
    var nextStarted = false

    // When
    first.cancel()
    let next = queue.enqueue { nextStarted = true
      return 2
    }
    try await operation.waitUntilCancelled()

    // Then
    #expect(!nextStarted)

    // When
    operation.resolve(invocation, with: .success(1))
    _ = try await next.value()

    // Then
    #expect(nextStarted)
    await #expect(throws: CancellationError.self) { try await first.value() }
  }

  @Test
  func `Bounded queue rejects admission and becomes available after completion`() async throws {
    // Given
    let queue = SerialEffectQueue(capacity: 1)
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = queue.enqueue { await operation.run(invocation) }
    try await operation.waitUntilStarted()
    var rejectedWorkStarted = false

    // When
    let rejected = queue.enqueue { rejectedWorkStarted = true
      return 2
    }

    // Then
    await #expect(throws: EffectQueueFullError.self) { try await rejected.value() }
    #expect(!rejectedWorkStarted)

    // When
    operation.resolve(invocation, with: .success(1))
    _ = try await first.value()
    let accepted = queue.enqueue { 3 }

    // Then
    #expect(try await accepted.value() == 3)
  }

  @Test
  func `Releasing a queue cancels running and pending handles`() async throws {
    // Given
    var queue: SerialEffectQueue? = SerialEffectQueue()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    let first = try #require(queue?.enqueue { await operation.run(invocation) })
    try await operation.waitUntilStarted()
    var pendingStarted = false
    let pending = try #require(queue?.enqueue { pendingStarted = true
      return 2
    })

    // When
    queue = nil
    try await operation.waitUntilCancelled()

    // Then
    await #expect(throws: CancellationError.self) { try await pending.value() }
    #expect(!pendingStarted)

    // When
    operation.resolve(invocation, with: .success(1))

    // Then
    await #expect(throws: CancellationError.self) { try await first.value() }
  }

  @Test
  func `Concurrent effects overlap without replacing each other`() async throws {
    // Given
    let effects = ConcurrentEffects()
    let operation = ControllableOperation<Int, Never>()
    let firstInvocation = operation.prepare()
    let secondInvocation = operation.prepare()

    // When
    let first = effects.run { await operation.run(firstInvocation) }
    let second = effects.run { await operation.run(secondInvocation) }
    try await operation.waitUntilStarted(count: 2)
    operation.resolve(secondInvocation, with: .success(2))

    // Then
    #expect(try await second.value() == 2)
    #expect(operation.cancelledCount == 0)

    // When
    operation.resolve(firstInvocation, with: .success(1))

    // Then
    #expect(try await first.value() == 1)
  }

  @Test
  func `Context rejects stale intermediate commits`() async throws {
    // Given
    let effect = LatestEffect()
    let operation = ControllableOperation<Int, Never>()
    let invocation = operation.prepare()
    var committed = false
    let first = effect.runWithContext { context in
      _ = await operation.run(invocation)
      guard context.isCurrent else { return }
      committed = true
    }
    try await operation.waitUntilStarted()

    // When
    let second = effect.run { 2 }
    _ = try await second.value()
    operation.resolve(invocation, with: .success(1))
    _ = await first.result

    // Then
    #expect(!committed)
  }
}
