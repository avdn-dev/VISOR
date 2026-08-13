import os

/// Lock-backed storage used by generated Sendable test doubles.
///
/// This is public only because macro expansions are type-checked in the
/// consuming module. Use ``GenerateStub(_:)`` or ``GenerateSpy(_:)`` instead.
nonisolated public struct _TestDoubleStorage<State: Sendable>: Sendable {
  public init(_ initialState: sending State) {
    lock = OSAllocatedUnfairLock(initialState: initialState)
  }

  public func withValue<Output: Sendable>(
    _ operation: @Sendable (inout State) -> Output
  ) -> Output {
    let (output, retiredState) = lock.withLock { state -> (Output, State) in
      // Keep references displaced by the mutation alive until the lock is no
      // longer held. Their deinitialisers may synchronously re-enter the test
      // double.
      let retiredState = state
      return (operation(&state), retiredState)
    }

    withExtendedLifetime(retiredState) {}
    return output
  }

  private let lock: OSAllocatedUnfairLock<State>
}
