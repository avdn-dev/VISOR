//
//  _TestDoubleStorage.swift
//  VISOR
//

import os

/// Lock-backed storage used by VISOR's generated Sendable test doubles.
///
/// This is public only because macro expansions are type-checked in the consuming module.
/// Application code should use `@GenerateStub(.sendable)` or `@GenerateSpy(.sendable)` instead.
nonisolated public struct _TestDoubleStorage<State: Sendable>: Sendable {

  // MARK: Lifecycle

  public init(_ initialState: sending State) {
    lock = OSAllocatedUnfairLock(initialState: initialState)
  }

  // MARK: Public

  public func withValue<Result: Sendable>(
    _ operation: @Sendable (inout State) throws -> Result)
    rethrows -> Result
  {
    try lock.withLock(operation)
  }

  // MARK: Private

  private let lock: OSAllocatedUnfairLock<State>
}
