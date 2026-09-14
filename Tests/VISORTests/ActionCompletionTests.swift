import Testing
import VISOR
import VISORTesting

// MARK: - ActionCompletionTests

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ActionCompletionTests {

  @Test
  func `Completed values and empty compositions can be awaited repeatedly`() async {
    let completed = ActionCompletion.completed
    await completed.wait()
    await completed.wait()
    await ActionCompletion.all([]).wait()
    await ActionCompletion.all([completed, completed]).wait()
  }

  @Test
  func `Completion joins only its invocation and includes synchronous delivery`() async throws {
    let effects = ConcurrentEffects()
    let operation = ControllableOperation<Int, Never>()
    defer { operation.resolveAllInvocations(with: .success(0)) }
    let first = operation.prepare()
    let later = operation.prepare()
    var received = [Int]()
    let recipient = CompletionRecipient()
    let completion = effects.run(for: recipient) {
      await operation.run(first)
    } receive: { _, value in
      received.append(value)
    }.completion
    let unrelated = effects.run { await operation.run(later) }
    try await operation.waitUntilStarted(count: 2)

    operation.resolve(first, with: .success(1))
    await completion.wait()
    #expect(received == [1])
    #expect(operation.finishedCount == 1)

    operation.resolve(later, with: .success(2))
    await unrelated.completion.wait()
    #expect(try await unrelated.value() == 2)
  }

  @Test
  func `Cancelling a waiter neither cancels work nor abandons the join`() async throws {
    let effects = ConcurrentEffects()
    let operation = ControllableOperation<Int, Never>()
    defer { operation.resolveAllInvocations(with: .success(1)) }
    let invocation = operation.prepare()
    let completion = effects.run { await operation.run(invocation) }.completion
    let entered = TestEventCounter()
    let waiter = Task {
      entered.record()
      await completion.wait()
      #expect(operation.finishedCount == 1)
    }
    try await entered.wait(untilEventCount: 1)
    try await operation.waitUntilStarted()
    waiter.cancel()
    #expect(operation.cancelledCount == 0)
    operation.resolve(invocation, with: .success(1))
    await waiter.value
    #expect(operation.cancelledCount == 0)
  }

  @Test
  func `Composition and copied completions join every submission without serialising work`() async throws {
    let effects = ConcurrentEffects()
    let operation = ControllableOperation<Int, Never>()
    defer { operation.resolveAllInvocations(with: .success(0)) }
    let first = operation.prepare()
    let second = operation.prepare()
    let firstCompletion = effects.run { await operation.run(first) }.completion
    let secondCompletion = effects.run { await operation.run(second) }.completion
    let combined = ActionCompletion.all([.completed, firstCompletion, secondCompletion])
    let waiter = Task {
      await combined.wait()
      #expect(operation.finishedCount == 2)
    }
    let copyWaiter = Task { await combined.wait() }
    try await operation.waitUntilStarted(count: 2)
    operation.resolve(second, with: .success(2))
    await secondCompletion.wait()
    #expect(operation.finishedCount == 1)
    operation.resolve(first, with: .success(1))
    await waiter.value
    await copyWaiter.value
    await combined.wait()
  }

  @Test
  func `Completion joins failures without changing the original outcome`() async {
    let effects = ConcurrentEffects()
    let recipient = CompletionRecipient()
    let handle = effects.run(for: recipient, operation: { () async throws -> Int in
      throw CompletionFailure.expected
    }) { _, result in
      if case .success = result { Issue.record("Expected failure delivery") }
    }
    await handle.completion.wait()
    await #expect(throws: CompletionFailure.expected) { try await handle.value() }
  }

  @Test(arguments: [false, true])
  func `Cancellation and supersession complete only after running work unwinds`(supersede: Bool) async throws {
    let effect = LatestEffect()
    let operation = ControllableOperation<Int, Never>()
    defer { operation.resolveAllInvocations(with: .success(1)) }
    let invocation = operation.prepare()
    let handle = effect.run { await operation.run(invocation) }
    let waiter = Task {
      await handle.completion.wait()
      #expect(operation.finishedCount == 1)
    }
    try await operation.waitUntilStarted()
    if supersede {
      await effect.run { 2 }.completion.wait()
    } else {
      handle.cancel()
    }
    try await operation.waitUntilCancelled()
    #expect(operation.finishedCount == 0)
    operation.resolve(invocation, with: .success(1))
    await waiter.value
    if supersede {
      await #expect(throws: EffectSupersededError.self) { try await handle.value() }
    } else {
      await #expect(throws: CancellationError.self) { try await handle.value() }
    }
  }

}

// MARK: - CompletionRecipient

@MainActor
private final class CompletionRecipient { }

// MARK: - CompletionFailure

private enum CompletionFailure: Error {
  case expected
}
