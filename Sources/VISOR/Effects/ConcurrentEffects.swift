/// Owns independent operations that may overlap. Each submission has its own
/// completion handle; releasing the collection cancels outstanding work.
@MainActor
public final class ConcurrentEffects {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  @discardableResult
  public func run<Output: Sendable>(
    operation: @escaping @MainActor @Sendable () async throws -> Output
  ) -> EffectHandle<Output> {
    runtime.submit { _ in try await operation() }
  }

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

  /// Delivers success or failure to a weak target. Nonthrowing operations
  /// prefer the output-only receiver overload.
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

  public func cancelAll() {
    runtime.cancelAll()
  }

  public func finish() async {
    await runtime.finish()
  }

  // MARK: Private

  private let runtime = _EffectRuntime(policy: .concurrent)
}
