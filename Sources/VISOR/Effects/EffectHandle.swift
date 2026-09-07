import os

// MARK: - EffectOutcome

/// The terminal outcome of one managed effect, after its operation unwinds.
public enum EffectOutcome<Output: Sendable>: Sendable {
  case success(Output)
  case failure(any Error)
  case cancelled
  case superseded
}

// MARK: - EffectSupersededError

/// Indicates that a newer invocation replaced the awaited operation.
public struct EffectSupersededError: Error, Equatable, Sendable {
  public init() { }
}

// MARK: - EffectHandle

/// Identifies one submission, independently of subsequent work on its owner.
///
/// Dropping a handle does not cancel the operation. Waiting does not propagate
/// the waiter's cancellation to the operation. Use `cancel()` explicitly.
@MainActor
public struct EffectHandle<Output: Sendable>: Sendable {

  // MARK: Lifecycle

  init(job: _EffectJob<Output>) {
    self.job = job
  }

  // MARK: Public

  /// Waits for the operation and synchronous delivery to finish.
  public var result: EffectOutcome<Output> {
    get async { await job.result }
  }

  /// Returns the output, or throws the failure, `CancellationError`, or
  /// `EffectSupersededError`. A cancellation request alone does not complete
  /// a running operation; its body must first unwind.
  public func value() async throws -> Output {
    switch await result {
    case .success(let output): return output
    case .failure(let error): throw error
    case .cancelled: throw CancellationError()
    case .superseded: throw EffectSupersededError()
    }
  }

  /// Requests cancellation of this submission only.
  public func cancel() {
    job.cancel(.cancelled)
  }

  // MARK: Private

  private let job: _EffectJob<Output>
}

// MARK: - EffectContext

/// A currentness check for multi-stage latest effects.
///
/// Check after suspension before committing intermediate results. The normal
/// `run(for:operation:receive:)` API performs this check for final delivery.
@MainActor
public struct EffectContext: Sendable {
  init(cancellation: _EffectCancellation) {
    self.cancellation = cancellation
  }

  public var isCurrent: Bool {
    cancellation.isCurrent
  }

  public func checkCancellation() throws {
    guard isCurrent else { throw CancellationError() }
  }

  private let cancellation: _EffectCancellation
}

// MARK: - _EffectCancellationReason

enum _EffectCancellationReason: Sendable {
  case cancelled
  case superseded
}

// MARK: - _EffectCancellation

/// Synchronises deinitialisation with task cancellation and delivery claims.
/// No application code or cancellation handler runs while the lock is held.
final class _EffectCancellation: Sendable {

  // MARK: Internal

  var isCurrent: Bool {
    storage.withLock { $0.reason == nil && !$0.isFinished }
  }

  func install(task: Task<Void, Never>) {
    let shouldCancel = storage.withLock { state in
      guard !state.isFinished else { return true }
      state.task = task
      return state.reason != nil
    }
    if shouldCancel { task.cancel() }
  }

  func onCancel(_ action: @escaping @Sendable () -> Void) {
    let shouldRun = storage.withLock { state in
      guard !state.isFinished else { return false }
      state.onCancel = action
      return state.reason != nil
    }
    if shouldRun { action() }
  }

  func cancel(_ reason: _EffectCancellationReason) {
    let callbacks = storage.withLock { state -> (Task<Void, Never>?, (@Sendable () -> Void)?) in
      guard !state.isFinished, state.reason == nil else { return (nil, nil) }
      state.reason = reason
      return (state.task, state.onCancel)
    }
    callbacks.0?.cancel()
    callbacks.1?()
  }

  func finish() -> _EffectCancellationReason? {
    storage.withLock { state in
      state.isFinished = true
      state.task = nil
      state.onCancel = nil
      return state.reason
    }
  }

  // MARK: Private

  private struct State: Sendable {
    var reason: _EffectCancellationReason?
    var task: Task<Void, Never>?
    var onCancel: (@Sendable () -> Void)?
    var isFinished = false
  }

  private let storage = OSAllocatedUnfairLock(initialState: State())
}
