/// Owns replaceable work and delivers only the current invocation's result.
///
/// Retain one instance per independent operation. Releasing it cancels its
/// outstanding work. Preparation must not capture its owner strongly if that
/// owner is expected to deinitialise while preparation is suspended.
@MainActor
public final class LatestEffect {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  /// Replaces previous work and returns a handle for this submission.
  @discardableResult
  public func run<Output: Sendable>(
    operation: @escaping @MainActor @Sendable () async throws -> Output
  ) -> EffectHandle<Output> {
    runtime.submit { _ in try await operation() }
  }

  /// Prepares an output without retaining the delivery target, then applies it
  /// synchronously on MainActor if this invocation is still current.
  @discardableResult
  public func run<Owner: AnyObject, Output: Sendable>(
    for owner: Owner,
    operation: @escaping @MainActor @Sendable () async -> Output,
    receive: @escaping @MainActor @Sendable (Owner, Output) -> Void,
  ) -> EffectHandle<Output> {
    runtime.submit(operation: { _ in await operation() }, receivesFailures: false) { [weak owner] result in
      guard let owner, case .success(let output) = result else { return }
      receive(owner, output)
    }
  }

  /// Delivers the current invocation's success or failure to a weak target.
  /// Cancellation and supersession are reported only through the handle.
  /// Nonthrowing operations prefer the output-only receiver overload.
  @_disfavoredOverload
  @discardableResult
  public func run<Owner: AnyObject, Output: Sendable>(
    for owner: Owner,
    operation: @escaping @MainActor @Sendable () async throws -> Output,
    receive: @escaping @MainActor @Sendable (Owner, Result<Output, any Error>) -> Void,
  ) -> EffectHandle<Output> {
    runtime.submit(operation: { _ in try await operation() }) { [weak owner] result in
      guard let owner else { return }
      receive(owner, result)
    }
  }

  /// Supports intermediate commits. Check the context after each suspension;
  /// final-delivery protection is automatic only in the receiver overloads.
  @discardableResult
  public func runWithContext<Output: Sendable>(
    operation: @escaping @MainActor @Sendable (EffectContext) async throws -> Output
  ) -> EffectHandle<Output> {
    runtime.submit(operation: operation)
  }

  public func cancel() {
    runtime.cancelAll()
  }

  /// Waits for work submitted before this call, including superseded work
  /// still unwinding. Does not wait for future submissions.
  public func finish() async {
    await runtime.finish()
  }

  // MARK: Private

  private let runtime = _EffectRuntime(policy: .latest)
}
