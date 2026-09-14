/// A join-only completion value for one synchronously dispatched action.
///
/// Return `completed` when the action has no asynchronous work, or an effect
/// handle's `completion` to join that submission. Waiting includes the
/// operation unwinding and its synchronous receiver returning, not unrelated
/// work on the same owner or unstructured child tasks.
///
/// Completion means the work has finished, not that it succeeded. Handle
/// failures in the model or inspect the original effect handle's outcome.
/// Dropping this value does not cancel work. Cancelling a waiting task neither
/// cancels the operation nor abandons the wait.
@MainActor
public struct ActionCompletion: Sendable {

  // MARK: Lifecycle

  init<Output>(handle: EffectHandle<Output>) {
    join = { _ = await handle.result }
  }

  private init(join: (@MainActor @Sendable () async -> Void)? = nil) {
    self.join = join
  }

  // MARK: Public

  /// An action whose work is already complete. Creates no task.
  public static let completed = ActionCompletion()

  /// Joins every supplied completion, without starting tasks or changing the
  /// scheduling policy of work already submitted. An empty collection is complete.
  public static func all(_ completions: [ActionCompletion]) -> ActionCompletion {
    guard !completions.isEmpty else { return .completed }
    return ActionCompletion {
      for completion in completions {
        await completion.wait()
      }
    }
  }

  /// Joins this action's work without propagating cancellation or failures.
  public func wait() async {
    await join?()
  }

  // MARK: Private

  private let join: (@MainActor @Sendable () async -> Void)?
}
