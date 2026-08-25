import Foundation
import os

// MARK: - ControllableOperation

/// A deterministic asynchronous operation whose result and lifecycle are
/// controlled by a test.
///
/// Prepare every invocation synchronously before running it. The returned
/// token fixes that invocation's identity and optional metadata independently
/// of task scheduling.
nonisolated public final class ControllableOperation<
  Success: Sendable,
  Failure: Error & Sendable,
>: Sendable {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  /// A stable identity for one prepared operation invocation.
  public struct Invocation<Metadata: Sendable>: Sendable {

    // MARK: Public

    public let ordinal: Int
    public let metadata: Metadata

    // MARK: Private

    fileprivate let operationID: UUID
  }

  public var startedCount: Int {
    lock.withLock { $0.startedCalls.count }
  }

  public var cancelledCount: Int {
    lock.withLock { $0.cancelledCalls.count }
  }

  public var finishedCount: Int {
    lock.withLock { $0.finishedCalls.count }
  }

  /// Reserves an invocation identity synchronously.
  public func prepare() -> Invocation<Void> {
    prepare(metadata: ())
  }

  /// Reserves an invocation identity synchronously and carries its
  /// domain-specific metadata with the returned token.
  public func prepare<Metadata: Sendable>(
    metadata: Metadata
  ) -> Invocation<Metadata> {
    let ordinal = lock.withLock { state in
      let ordinal = state.nextOrdinal
      state.nextOrdinal += 1
      state.preparedCalls.insert(ordinal)
      return ordinal
    }
    return Invocation(
      ordinal: ordinal,
      metadata: metadata,
      operationID: operationID,
    )
  }

  /// Runs a prepared invocation until the test resolves it.
  ///
  /// Pass a result through `onCancellation` when cancellation should resolve
  /// the invocation cooperatively. The default records cancellation without
  /// releasing the invocation.
  public func run(
    _ invocation: Invocation<some Sendable>,
    onCancellation cancellationResult: Result<Success, Failure>? = nil,
  ) async throws(Failure) -> Success {
    let ordinal = validatedOrdinal(of: invocation)
    lock.withLock { state in
      precondition(
        state.startedCalls.insert(ordinal).inserted,
        "A controllable operation invocation must start exactly once",
      )
    }
    started.record()

    let result = await withTaskCancellationHandler {
      await withCheckedContinuation {
        (continuation: OperationContinuation) in
        let registration = lock.withLock { state in
          let didRecordCancellation = recordCancellationIfNeeded(
            ordinal: ordinal,
            result: cancellationResult,
            isCancelled: Task.isCancelled,
            state: &state,
          )

          let immediate: OperationResult?
          if state.resolvedCalls.contains(ordinal) {
            guard let cancellationResult else {
              preconditionFailure(
                "A non-cooperative controllable operation resolved without an explicit result"
              )
            }
            immediate = cancellationResult
          } else if let queued = state.queuedResults.removeValue(forKey: ordinal) {
            state.resolvedCalls.insert(ordinal)
            immediate = queued
          } else if let terminalResult = state.terminalResult {
            state.resolvedCalls.insert(ordinal)
            immediate = terminalResult
          } else {
            state.pending[ordinal] = continuation
            immediate = nil
          }
          return (didRecordCancellation, immediate)
        }

        if registration.0 {
          cancelled.record()
        }
        if let immediate = registration.1 {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      let cancellation = lock.withLock { state in
        let didRecordCancellation = recordCancellationIfNeeded(
          ordinal: ordinal,
          result: cancellationResult,
          isCancelled: true,
          state: &state,
        )
        let continuation = cancellationResult.flatMap { _ in
          state.pending.removeValue(forKey: ordinal)
        }
        return (didRecordCancellation, continuation)
      }
      if cancellation.0 {
        cancelled.record()
      }
      if let continuation = cancellation.1, let cancellationResult {
        continuation.resume(returning: cancellationResult)
      }
    }

    recordFinished(ordinal: ordinal)
    return try result.get()
  }

  /// Waits until at least the requested number of invocations have started.
  public func waitUntilStarted(
    count expectedCount: Int = 1
  ) async throws(CancellationError) {
    try await started.wait(untilEventCount: expectedCount)
  }

  /// Waits until at least the requested number of invocations have cancelled.
  public func waitUntilCancelled(
    count expectedCount: Int = 1
  ) async throws(CancellationError) {
    try await cancelled.wait(untilEventCount: expectedCount)
  }

  /// Waits until at least the requested number of invocations have finished.
  public func waitUntilFinished(
    count expectedCount: Int = 1
  ) async throws(CancellationError) {
    try await finished.wait(untilEventCount: expectedCount)
  }

  /// Resolves one prepared invocation, whether or not it has started.
  public func resolve(
    _ invocation: Invocation<some Sendable>,
    with result: Result<Success, Failure>,
  ) {
    let ordinal = validatedOrdinal(of: invocation)
    let resolution = lock.withLock { state in
      precondition(
        state.terminalResult == nil,
        "A terminal controllable operation cannot be resolved",
      )
      precondition(
        !state.resolvedCalls.contains(ordinal) && state.queuedResults[ordinal] == nil,
        "A controllable operation invocation must be resolved exactly once",
      )
      return resolve(ordinal: ordinal, with: result, state: &state)
    }
    resume(resolution)
  }

  /// Resolves every prepared, running, and future invocation with the same result.
  ///
  /// Invocations that have already finished keep their result. Calling this
  /// method again replaces the result used by later invocations.
  public func resolveAllInvocations(
    with result: Result<Success, Failure>
  ) {
    let resolutions = lock.withLock { state in
      state.terminalResult = result
      state.queuedResults.removeAll()
      let pending = state.pending
      state.pending.removeAll()
      return pending.compactMap { ordinal, continuation -> Resolution? in
        guard state.resolvedCalls.insert(ordinal).inserted else { return nil }
        return Resolution(continuation: continuation, result: result)
      }
    }
    for resolution in resolutions {
      resume(resolution)
    }
  }

  // MARK: Private

  private typealias OperationResult = Result<Success, Failure>
  private typealias OperationContinuation = CheckedContinuation<OperationResult, Never>

  private struct State: Sendable {
    var nextOrdinal = 1
    var preparedCalls = Set<Int>()
    var startedCalls = Set<Int>()
    var pending = [Int: OperationContinuation]()
    var queuedResults = [Int: OperationResult]()
    var terminalResult: OperationResult?
    var cancelledCalls = Set<Int>()
    var resolvedCalls = Set<Int>()
    var finishedCalls = Set<Int>()
  }

  private struct Resolution {
    let continuation: OperationContinuation?
    let result: OperationResult
  }

  private let operationID = UUID()
  private let started = TestEventCounter()
  private let cancelled = TestEventCounter()
  private let finished = TestEventCounter()
  private let lock = OSAllocatedUnfairLock(initialState: State())

  private func validatedOrdinal(
    of invocation: Invocation<some Sendable>
  ) -> Int {
    precondition(
      invocation.operationID == operationID,
      "A controllable operation invocation belongs to its preparing operation",
    )
    precondition(
      lock.withLock { $0.preparedCalls.contains(invocation.ordinal) },
      "A controllable operation invocation must be prepared before use",
    )
    return invocation.ordinal
  }

  private func recordCancellationIfNeeded(
    ordinal: Int,
    result: OperationResult?,
    isCancelled: Bool,
    state: inout State,
  ) -> Bool {
    guard isCancelled else { return false }
    guard !state.finishedCalls.contains(ordinal) else { return false }
    guard state.cancelledCalls.insert(ordinal).inserted else { return false }
    if result != nil {
      state.resolvedCalls.insert(ordinal)
      state.queuedResults.removeValue(forKey: ordinal)
    }
    return true
  }

  private func recordFinished(ordinal: Int) {
    let didFinish = lock.withLock { state in
      state.finishedCalls.insert(ordinal).inserted
    }
    if didFinish {
      finished.record()
    }
  }

  private func resolve(
    ordinal: Int,
    with result: OperationResult,
    state: inout State,
  ) -> Resolution? {
    if let continuation = state.pending.removeValue(forKey: ordinal) {
      state.resolvedCalls.insert(ordinal)
      return Resolution(continuation: continuation, result: result)
    }
    state.queuedResults[ordinal] = result
    return nil
  }

  private func resume(_ resolution: Resolution?) {
    guard let resolution else { return }
    resolution.continuation?.resume(returning: resolution.result)
  }
}
