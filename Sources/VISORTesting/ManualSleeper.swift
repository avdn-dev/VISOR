import Foundation
import os

// MARK: - ManualSleeper

/// Package test support for manually resolving injected sleep operations.
///
/// Each sleep is prepared synchronously before its asynchronous operation is
/// returned, so a test can resolve it before the task starts.
nonisolated package final class ManualSleeper: Sendable {

  // MARK: Lifecycle

  package init() { }

  // MARK: Package

  package typealias Sleep = ControllableOperation<
    Void,
    CancellationError,
  >.Invocation<Duration>

  package var sleepCount: Int {
    lock.withLock { $0.count }
  }

  package func makeSleep(
    for duration: Duration
  ) -> @concurrent @Sendable () async throws -> Void {
    let sleep = prepare(for: duration)
    return {
      try await self.operation.run(
        sleep,
        onCancellation: .failure(CancellationError()),
      )
    }
  }

  package func waitUntilPrepared(_ expectedCount: Int) async -> Sleep {
    await prepared.wait(for: expectedCount)
    return preparedSleep(at: expectedCount - 1)
  }

  package func waitUntilPrepared(
    for duration: Duration,
    occurrence: Int = 1,
  ) async -> Sleep {
    precondition(occurrence > 0)
    var expectedSleepCount = 1
    while true {
      let sleeps = lock.withLock { $0 }
      let matching = sleeps.filter { $0.metadata == duration }
      if matching.count >= occurrence {
        return matching[occurrence - 1]
      }
      expectedSleepCount = sleeps.count + 1
      await prepared.wait(for: expectedSleepCount)
    }
  }

  package func preparedSleep(at index: Int) -> Sleep {
    lock.withLock { sleeps in
      precondition(sleeps.indices.contains(index))
      return sleeps[index]
    }
  }

  package func wake(_ sleep: Sleep) {
    operation.resolve(sleep, with: .success(()))
  }

  // MARK: Private

  private let operation = ControllableOperation<Void, CancellationError>()
  private let prepared = TestEventCounter()
  private let lock = OSAllocatedUnfairLock(initialState: [Sleep]())

  private func prepare(for duration: Duration) -> Sleep {
    let sleep = operation.prepare(metadata: duration)
    lock.withLock { $0.append(sleep) }
    prepared.record()
    return sleep
  }
}
