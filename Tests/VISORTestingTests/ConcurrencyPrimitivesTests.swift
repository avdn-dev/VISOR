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
    let invocation = Task { try await operation.run() }
    await operation.waitUntilStarted()

    // When
    operation.resume(returning: 42)

    // Then
    #expect(try await invocation.value == 42)
    await operation.waitUntilFinished()
    #expect(operation.completionCount == 1)
  }

  @Test @MainActor
  func `A controllable operation throws its supplied failure`() async {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let invocation = Task { try await operation.run() }
    await operation.waitUntilStarted()

    // When
    operation.resume(throwing: .expected)

    // Then
    await #expect(throws: ControlledOperationError.expected) {
      try await invocation.value
    }
  }

  @Test @MainActor
  func `A result queued before invocation completes the next call`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()

    // When
    operation.resume(returning: 42)

    // Then
    #expect(try await operation.run() == 42)
    #expect(operation.completionCount == 1)
  }

  @Test @MainActor
  func `Cooperative cancellation is acknowledged and finishes the invocation`() async {
    // Given
    let operation = ControllableOperation<Void, CancellationError>()
    let invocation = Task {
      try await operation.run(cancellingWith: CancellationError())
    }
    await operation.waitUntilStarted()

    // When
    invocation.cancel()
    await operation.waitUntilCancelled()
    await operation.waitUntilFinished()

    // Then
    await #expect(throws: CancellationError.self) {
      try await invocation.value
    }
    #expect(operation.cancellationCount == 1)
    #expect(operation.completionCount == 1)
  }

  @Test @MainActor
  func `Non-cooperative cancellation is acknowledged without releasing the invocation`() async {
    // Given
    let operation = ControllableOperation<Void, Never>()
    let didFinish = TestEventCounter()
    let invocation = Task {
      await operation.run()
      didFinish.record()
    }
    await operation.waitUntilStarted()

    // When
    invocation.cancel()
    await operation.waitUntilCancelled()

    // Then
    #expect(didFinish.count == 0)

    // When
    operation.finish()
    await invocation.value

    // Then
    #expect(didFinish.count == 1)
  }

  @Test @MainActor
  func `Cancellation can cooperatively complete a non-throwing invocation`() async {
    // Given
    let operation = ControllableOperation<Bool, Never>()
    let invocation = Task {
      await operation.run(completingOnCancellationWith: false)
    }
    await operation.waitUntilStarted()

    // When
    invocation.cancel()
    await operation.waitUntilCancelled()

    // Then
    #expect(await invocation.value == false)
    await operation.waitUntilFinished()
  }

  @Test @MainActor
  func `Specific calls can complete independently`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let first = Task { try await operation.run() }
    let second = Task { try await operation.run() }
    await operation.waitUntilStarted(callCount: 2)

    // When
    operation.resume(call: 2, returning: 20)
    operation.resume(call: 1, returning: 10)

    // Then
    #expect(try await first.value == 10)
    #expect(try await second.value == 20)
    await operation.waitUntilFinished(callCount: 2)
  }

  @Test @MainActor
  func `A terminal result completes current and future calls`() async throws {
    // Given
    let operation = ControllableOperation<Int, ControlledOperationError>()
    let first = Task { try await operation.run() }
    await operation.waitUntilStarted()

    // When
    operation.completeAll(returning: 7)

    // Then
    #expect(try await first.value == 7)

    // When
    let second = try await operation.run()

    // Then
    #expect(second == 7)
    #expect(operation.callCount == 2)
  }

  @Test @MainActor
  func `An event counter acknowledges the requested count`() async {
    // Given
    let counter = TestEventCounter()
    let acknowledgement = Task {
      await counter.wait(for: 2)
      return counter.count
    }

    // When
    counter.record()
    counter.record()

    // Then
    #expect(await acknowledgement.value == 2)
  }

  @Test
  func `An event counter records synchronous events outside MainActor`() async {
    // Given
    let counter = TestEventCounter()

    // When
    await Task.detached {
      counter.record()
    }.value

    // Then
    await counter.wait()
    #expect(counter.count == 1)
  }

  @Test
  func `A barrier releases every participant together`() async {
    // Given
    let barrier = TestBarrier(participantCount: 2)
    let first = Task {
      await barrier.arriveAndWait()
      return await barrier.isOpen
    }
    await barrier.waitUntilArrived(1)

    // When
    let second = Task {
      await barrier.arriveAndWait()
      return await barrier.isOpen
    }

    // Then
    #expect(await first.value)
    #expect(await second.value)
    #expect(await barrier.arrivalCount == 2)
  }
}
