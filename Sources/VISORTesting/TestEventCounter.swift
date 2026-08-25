import os

// MARK: - TestEventCounter

/// A deterministic count of test events that supports asynchronous acknowledgement.
public final class TestEventCounter: Sendable {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public var count: Int {
    lock.withLock { $0.count }
  }

  public func record() {
    let readyContinuations = lock.withLock { state in
      state.count += 1
      let readyWaiters = state.waiters.filter { state.count >= $0.expectedCount }
      state.waiters.removeAll { state.count >= $0.expectedCount }
      return readyWaiters.map(\.continuation)
    }

    for continuation in readyContinuations {
      continuation.resume(returning: .success(()))
    }
  }

  /// Waits until at least one event has been recorded.
  ///
  /// - Throws: `CancellationError` when the waiting task is cancelled before
  ///   the event is acknowledged.
  public func wait() async throws(CancellationError) {
    try await wait(for: 1)
  }

  /// Waits until the requested number of events has been recorded.
  ///
  /// - Throws: `CancellationError` when the waiting task is cancelled before
  ///   the requested count is acknowledged.
  public func wait(
    for expectedCount: Int
  ) async throws(CancellationError) {
    precondition(expectedCount > 0)

    let waiterID = lock.withLock { state in
      defer { state.nextWaiterID += 1 }
      return state.nextWaiterID
    }
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let registration = lock.withLock { state in
          guard !Task.isCancelled else { return Registration.cancelled }
          guard state.count < expectedCount else { return Registration.ready }
          state.waiters.append(Waiter(
            id: waiterID,
            expectedCount: expectedCount,
            continuation: continuation,
          ))
          return Registration.waiting
        }

        switch registration {
        case .waiting:
          break
        case .ready:
          continuation.resume(returning: .success(()))
        case .cancelled:
          continuation.resume(returning: .failure(CancellationError()))
        }
      }
    } onCancel: {
      let continuation: WaitContinuation? = lock.withLock { state in
        guard let index = state.waiters.firstIndex(where: { $0.id == waiterID }) else {
          return nil
        }
        return state.waiters.remove(at: index).continuation
      }
      if let continuation {
        continuation.resume(returning: .failure(CancellationError()))
      }
    }
    return try result.get()
  }

  // MARK: Private

  private struct State: Sendable {
    var count = 0
    var nextWaiterID = 1
    var waiters = [Waiter]()
  }

  private struct Waiter: Sendable {
    let id: Int
    let expectedCount: Int
    let continuation: WaitContinuation
  }

  private enum Registration {
    case waiting
    case ready
    case cancelled
  }

  private typealias WaitContinuation = CheckedContinuation<WaitResult, Never>
  private typealias WaitResult = Result<Void, CancellationError>

  private let lock = OSAllocatedUnfairLock(initialState: State())
}
