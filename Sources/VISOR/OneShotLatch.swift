import os

/// Publishes one winning value to every current and future waiter.
///
/// Resolution is synchronous and thread-safe. The first call to ``resolve(_:)``
/// wins; subsequent calls leave that value unchanged. Waiting suspends the caller
/// without blocking a thread and does not create or own any tasks.
///
/// Cancellation does not resolve the latch or remove a waiter. Its owner must
/// eventually resolve it, including on cancellation or timeout where appropriate.
/// Represent failures with `Result` or a domain-specific outcome rather than
/// giving the latch responsibility for cancellation or error policy.
nonisolated public final class OneShotLatch<Value: Sendable>: Sendable {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  /// The winning value, or `nil` while unresolved.
  ///
  /// For an optional `Value`, resolving with `nil` produces `.some(nil)` here.
  /// An unresolved snapshot does not reserve the next resolution; use the return
  /// value of ``resolve(_:)`` to determine whether a caller won.
  public var resolvedValue: Value? {
    lock.withLock { $0.value }
  }

  /// Publishes a value and resumes all waiters, returning whether this call won.
  @discardableResult
  public func resolve(_ value: Value) -> Bool {
    let resolution: (didWin: Bool, waiters: [Waiter]) = lock.withLock { state in
      guard state.value == nil else { return (false, []) }
      state.value = .some(value)
      let waiters = state.waiters
      state.waiters.removeAll()
      return (true, waiters)
    }
    // Resume outside the lock so resumed work cannot re-enter locked state.
    for waiter in resolution.waiters {
      waiter.resume(returning: value)
    }
    return resolution.didWin
  }

  /// Returns the winning value, suspending on the caller's actor until resolved.
  /// Task cancellation alone does not end this wait.
  nonisolated(nonsending) public func wait() async -> Value {
    await withCheckedContinuation { continuation in
      let immediate: Value? = lock.withLock { state in
        if let value = state.value {
          return .some(value)
        }
        state.waiters.append(continuation)
        return nil
      }
      if let immediate {
        continuation.resume(returning: immediate)
      }
    }
  }

  // MARK: Private

  private typealias Waiter = CheckedContinuation<Value, Never>

  private struct State: Sendable {
    var value: Value?
    var waiters = [Waiter]()
  }

  /// Only bounded, non-suspending state transitions run under this lock.
  private let lock = OSAllocatedUnfairLock(initialState: State())

}
