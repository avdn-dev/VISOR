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
      continuation.resume()
    }
  }

  public func wait() async {
    await wait(for: 1)
  }

  public func wait(for expectedCount: Int) async {
    precondition(expectedCount > 0)
    await withCheckedContinuation { continuation in
      let isAlreadyRecorded = lock.withLock { state in
        guard state.count < expectedCount else { return true }
        state.waiters.append(Waiter(
          expectedCount: expectedCount,
          continuation: continuation))
        return false
      }

      if isAlreadyRecorded {
        continuation.resume()
      }
    }
  }

  // MARK: Private

  private struct State: Sendable {
    var count = 0
    var waiters = [Waiter]()
  }

  private struct Waiter: Sendable {
    let expectedCount: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())
}
