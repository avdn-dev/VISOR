/// Executes every accepted operation in submission order, across suspension
/// and failure. Releasing the queue cancels running and pending operations.
///
/// This is an in-memory queue. Use a service-owned queue for work that must
/// outlive a screen, and persisted work for delivery across process termination.
@MainActor
public final class SerialEffectQueue {

  // MARK: Lifecycle

  /// Creates an unbounded queue. Use `init(capacity:)` to bound admission.
  public init() {
    runtime = _EffectRuntime(policy: .serial(capacity: nil))
  }

  /// Bounds outstanding work, including the running operation. A full queue
  /// returns a failed handle containing `EffectQueueFullError`.
  public init(capacity: Int) {
    precondition(capacity > 0, "SerialEffectQueue capacity must be positive")
    runtime = _EffectRuntime(policy: .serial(capacity: capacity))
  }

  // MARK: Public

  @discardableResult
  public func enqueue<Output: Sendable>(
    operation: @escaping @MainActor @Sendable () async throws -> Output
  ) -> EffectHandle<Output> {
    runtime.submit { _ in try await operation() }
  }

  @discardableResult
  public func enqueue<Owner: AnyObject, Output: Sendable>(
    for owner: Owner,
    operation: @escaping @MainActor @Sendable () async -> Output,
    receive: @escaping @MainActor @Sendable (Owner, Output) -> Void,
  ) -> EffectHandle<Output> {
    runtime.submit(operation: { _ in await operation() }, receivesFailures: false) { [weak owner] result in
      guard let owner, case .success(let output) = result else { return }
      receive(owner, output)
    }
  }

  /// Delivers success or failure to a weak target. Nonthrowing operations
  /// prefer the output-only receiver overload.
  @_disfavoredOverload
  @discardableResult
  public func enqueue<Owner: AnyObject, Output: Sendable>(
    for owner: Owner,
    operation: @escaping @MainActor @Sendable () async throws -> Output,
    receive: @escaping @MainActor @Sendable (Owner, Result<Output, any Error>) -> Void,
  ) -> EffectHandle<Output> {
    runtime.submit(operation: { _ in try await operation() }) { [weak owner] result in
      guard let owner else { return }
      receive(owner, result)
    }
  }

  public func cancelAll() {
    runtime.cancelAll()
  }

  public func finish() async {
    await runtime.finish()
  }

  // MARK: Private

  private let runtime: _EffectRuntime
}
