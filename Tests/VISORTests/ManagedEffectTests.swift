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
