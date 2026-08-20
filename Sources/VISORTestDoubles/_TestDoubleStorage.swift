import os

/// Lock-backed storage used by generated Sendable test doubles.
///
/// This is public only because macro expansions are type-checked in the
/// consuming module. Use ``GenerateStub(_:)`` or ``GenerateSpy(_:)`` instead.
nonisolated public struct _TestDoubleStorage<State: Sendable>: Sendable {
  /// Creates generated lock-backed storage.
  ///
  /// - Parameter initialState: The complete initial test-double state.
  public init(_ initialState: sending State) {
    lock = OSAllocatedUnfairLock(initialState: initialState)
  }

  /// Borrows the synchronised State for a read without creating a mutable
  /// snapshot of its copy-on-write storage.
  ///
  /// - Parameter operation: A synchronous read performed while holding the lock.
  /// - Returns: The operation's Sendable result.
  public func withValue<Output: Sendable>(
    _ operation: @Sendable (borrowing State) -> Output
  ) -> Output {
    lock.withLock { state in
      operation(state)
    }
  }

  /// Mutates the synchronised State while retiring displaced values after the
  /// lock is released.
  ///
  /// `retiredValue` runs before `operation` and must select every value that
  /// the operation replaces. Values merely mutated in place, such as an Array
  /// history append, should not be selected.
  ///
  /// - Parameters:
  ///   - retiredValue: Selects displaced references that must be released after unlocking.
  ///   - operation: A synchronous mutation performed while holding the lock.
  /// - Returns: The mutation's Sendable result.
  public func withMutation<Output: Sendable, Retired: Sendable>(
    retiring retiredValue: @Sendable (borrowing State) -> Retired,
    _ operation: @Sendable (inout State) -> Output
  ) -> Output {
    let result = lock.withLock { state in
      let retiredValue = retiredValue(state)
      return (output: operation(&state), retired: retiredValue)
    }

    // Keep only references displaced by the mutation alive until the lock is
    // no longer held. Their deinitialisers may synchronously re-enter the test
    // double. Retaining the complete State here would also share every Array
    // buffer and force copy-on-write on each history append.
    withExtendedLifetime(result.retired) {}
    return result.output
  }

  private let lock: OSAllocatedUnfairLock<State>
}
