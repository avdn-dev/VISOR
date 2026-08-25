import os

/// Lock-backed storage used by generated Sendable test doubles.
///
/// This is public only because macro expansions are type-checked in the
/// consuming module. Use ``GenerateStub(_:)`` or ``GenerateSpy(_:)`` instead.
nonisolated public struct _TestDoubleStorage<State: Sendable>: Sendable {

  // MARK: Lifecycle

  /// Creates generated lock-backed storage.
  public init(_ initialState: sending State) {
    lock = OSAllocatedUnfairLock(initialState: initialState)
  }

  // MARK: Public

  /// Borrows the synchronised State for a read without creating a mutable
  /// snapshot of its copy-on-write storage.
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
  public func withMutation<Output: Sendable>(
    retiring retiredValue: @Sendable (borrowing State) -> some Sendable,
    _ operation: @Sendable (inout State) -> Output,
  ) -> Output {
    let result = lock.withLock { state in
      let retiredValue = retiredValue(state)
      return (output: operation(&state), retired: retiredValue)
    }

    // Keep only references displaced by the mutation alive until the lock is
    // no longer held. Their deinitialisers may synchronously re-enter the test
    // double. Retaining the complete State here would also share every Array
    // buffer and force copy-on-write on each history append.
    withExtendedLifetime(result.retired) { }
    return result.output
  }

  // MARK: Private

  private let lock: OSAllocatedUnfairLock<State>
}
