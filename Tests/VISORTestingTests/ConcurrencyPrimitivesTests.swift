import Testing
import VISORTesting

// MARK: - ControlledOperationError

private enum ControlledOperationError: Error, Sendable {
  case expected
}

// MARK: - ConcurrencyPrimitivesTests

@Suite("Concurrency test primitives")
struct ConcurrencyPrimitivesTests {

  @Test @MainActor
  func `A controllable operation returns its supplied value`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let invocation = operation.prepare()
    let task = Task { try await operation.run(invocation) }
    try await operation.waitUntilStarted()

    // When
    operation.resolve(invocation, with: .success(42))

    // Then
    #expect(try await task.value == 42)
    try await operation.waitUntilFinished()
    #expect(operation.finishedCount == 1)
  }

  @Test @MainActor
  func `A controllable operation throws its supplied failure`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let invocation = operation.prepare()
    let task = Task { try await operation.run(invocation) }
    try await operation.waitUntilStarted()

    // When
    operation.resolve(invocation, with: .failure(.expected))

    // Then
    await #expect(throws: ControlledOperationError.expected) {
      try await task.value
    }
  }

  @Test @MainActor
  func `A result queued before invocation completes the next call`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let invocation = operation.prepare()

    // When
    operation.resolve(invocation, with: .success(42))

    // Then
    #expect(try await operation.run(invocation) == 42)
    #expect(operation.finishedCount == 1)
  }

  @Test @MainActor
  func `Cooperative cancellation is acknowledged and finishes the invocation`() async throws {
    // Given
    let operation = ControllableOperation<Void, CancellationError>()
    let invocation = operation.prepare()
    let task = Task {
      try await operation.run(
        invocation,
        onCancellation: .failure(CancellationError()),
      )
    }
    try await operation.waitUntilStarted()

    // When
    task.cancel()
    try await operation.waitUntilCancelled()
    try await operation.waitUntilFinished()

    // Then
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(operation.cancelledCount == 1)
    #expect(operation.finishedCount == 1)
  }

  @Test @MainActor
  func `Non-cooperative cancellation is acknowledged without releasing the invocation`() async throws {
    // Given
    let operation = ControllableOperation<Void, Never>()
    let didFinish = TestEventCounter()
    let invocation = operation.prepare()
    let task = Task {
      await operation.run(invocation)
      didFinish.record()
    }
    try await operation.waitUntilStarted()

    // When
    task.cancel()
    try await operation.waitUntilCancelled()

    // Then
    #expect(didFinish.count == 0)

    // When
    operation.resolveAllInvocations(with: .success(()))
    await task.value

    // Then
    #expect(didFinish.count == 1)
  }

  @Test @MainActor
  func `Cancellation can cooperatively complete a non-throwing invocation`() async throws {
    // Given
    let operation = ControllableOperation<Bool, Never>()
    let invocation = operation.prepare()
    let task = Task {
      await operation.run(invocation, onCancellation: .success(false))
    }
    try await operation.waitUntilStarted()

    // When
    task.cancel()
    try await operation.waitUntilCancelled()

    // Then
    #expect(await task.value == false)
    try await operation.waitUntilFinished()
  }

  @Test @MainActor
  func `Specific calls can complete independently`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let firstInvocation = operation.prepare()
    let secondInvocation = operation.prepare()
    let first = Task { try await operation.run(firstInvocation) }
    let second = Task { try await operation.run(secondInvocation) }
    try await operation.waitUntilStarted(count: 2)

    // When
    operation.resolve(secondInvocation, with: .success(20))
    operation.resolve(firstInvocation, with: .success(10))

    // Then
    #expect(try await first.value == 10)
    #expect(try await second.value == 20)
    try await operation.waitUntilFinished(count: 2)
  }

  @Test
  func `A prepared invocation fixes identity and metadata before asynchronous start`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()

    // When
    let invocation = operation.prepare(metadata: Duration.seconds(3))
    operation.resolve(invocation, with: .success(42))
    let result = try await Task.detached {
      try await operation.run(invocation)
    }.value

    // Then
    #expect(invocation.ordinal == 1)
    #expect(invocation.metadata == .seconds(3))
    #expect(operation.startedCount == 1)
    #expect(result == 42)
  }

  @Test
  func `A deadline can fire after synchronous preparation and before task start`() async throws {
    // Given
    let sleeper = ManualSleeper()

    // When
    let operation = sleeper.makeSleep(for: .seconds(3))
    let sleep = sleeper.preparedSleep(at: 0)
    sleeper.wake(sleep)

    // Then
    #expect(sleeper.sleepCount == 1)
    #expect(sleep.metadata == .seconds(3))
    try await Task.detached { try await operation() }.value
  }

  @Test
  func `A deadline sleep can be selected by duration`() async throws {
    // Given
    let sleeper = ManualSleeper()
    let shortSleepOperation = sleeper.makeSleep(for: .seconds(1))
    let longSleepOperation = sleeper.makeSleep(for: .seconds(5))
    let shortOperation = Task { try await shortSleepOperation() }
    let longOperation = Task { try await longSleepOperation() }

    // When
    let longSleep = try await sleeper.waitUntilPrepared(for: .seconds(5))
    let shortSleep = try await sleeper.waitUntilPrepared(for: .seconds(1))
    sleeper.wake(longSleep)
    sleeper.wake(shortSleep)

    // Then
    try await shortOperation.value
    try await longOperation.value
  }

  @Test @MainActor
  func `A terminal result completes current and future calls`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let firstInvocation = operation.prepare()
    let first = Task { try await operation.run(firstInvocation) }
    try await operation.waitUntilStarted()

    // When
    operation.resolveAllInvocations(with: .success(7))

    // Then
    #expect(try await first.value == 7)

    // When
    let secondInvocation = operation.prepare()
    let second = try await operation.run(secondInvocation)

    // Then
    #expect(second == 7)
    #expect(operation.startedCount == 2)
  }

  @Test @MainActor
  func `An event counter acknowledges the requested count`() async throws {
    // Given
    let counter = TestEventCounter()
    let acknowledgement = Task {
      try await counter.wait(untilEventCount: 2)
      return counter.count
    }

    // When
    counter.record()
    counter.record()

    // Then
    #expect(try await acknowledgement.value == 2)
  }

  @Test
  func `An event counter records synchronous events outside MainActor`() async throws {
    // Given
    let counter = TestEventCounter()

    // When
    await Task.detached {
      counter.record()
    }.value

    // Then
    try await counter.wait()
    #expect(counter.count == 1)
  }

  @Test
  func `A cancelled event counter wait is removed without poisoning the counter`() async throws {
    // Given
    let counter = TestEventCounter()
    let waitStarted = TestEventCounter()
    let waiter = Task {
      waitStarted.record()
      try await counter.wait()
    }
    try await waitStarted.wait()
    await Task.yield()

    // When
    waiter.cancel()

    // Then
    await #expect(throws: CancellationError.self) {
      try await waiter.value
    }

    // When
    counter.record()

    // Then
    try await counter.wait()
    #expect(counter.count == 1)
  }

  @Test
  func `A barrier releases every participant together`() async throws {
    // Given
    let barrier = TestBarrier(participantCount: 2)
    let first = Task {
      try await barrier.arriveAndWait()
      return await barrier.isOpen
    }
    try await barrier.waitUntilArrived(count: 1)

    // When
    let second = Task {
      try await barrier.arriveAndWait()
      return await barrier.isOpen
    }

    // Then
    #expect(try await first.value)
    #expect(try await second.value)
    #expect(await barrier.arrivalCount == 2)
  }

  @Test
  func `A cancelled barrier participant keeps its recorded arrival`() async throws {
    // Given
    let barrier = TestBarrier(participantCount: 2)
    let first = Task {
      try await barrier.arriveAndWait()
    }
    try await barrier.waitUntilArrived(count: 1)

    // When
    first.cancel()

    // Then
    await #expect(throws: CancellationError.self) {
      try await first.value
    }
    #expect(await barrier.arrivalCount == 1)

    // When
    try await barrier.arriveAndWait()

    // Then
    #expect(await barrier.isOpen)
    #expect(await barrier.arrivalCount == 2)
  }

  @Test
  func `A cancelled arrival observer does not poison later barrier use`() async throws {
    // Given
    let barrier = TestBarrier(participantCount: 1)
    let waitStarted = TestEventCounter()
    let observer = Task {
      waitStarted.record()
      try await barrier.waitUntilArrived(count: 1)
    }
    try await waitStarted.wait()
    await Task.yield()

    // When
    observer.cancel()

    // Then
    await #expect(throws: CancellationError.self) {
      try await observer.value
    }

    // When
    try await barrier.arriveAndWait()

    // Then
    #expect(await barrier.isOpen)
  }
}
