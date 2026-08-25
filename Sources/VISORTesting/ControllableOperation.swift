// MARK: - ControllableOperation

/// A deterministic test operation whose result and lifecycle are controlled by the test.
///
/// Each invocation receives a one-based call number and suspends until it is resumed explicitly,
/// completed by a terminal result, or cooperatively cancelled. Tests can acknowledge invocation,
/// cancellation, and completion without relying on scheduler turns or elapsed time.
@MainActor
public final class ControllableOperation<Success: Sendable, Failure: Error & Sendable> {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public var callCount: Int {
    started.count
  }

  public var cancellationCount: Int {
    cancelled.count
  }

  public var completionCount: Int {
    completed.count
  }

  /// Runs an invocation that records cancellation but remains suspended until explicitly resumed.
  public func run() async throws(Failure) -> Success {
    try await run(cancellationResult: nil)
  }

  /// Runs an invocation that cooperatively completes with `failure` when its task is cancelled.
  public func run(cancellingWith failure: Failure) async throws(Failure) -> Success {
    try await run(cancellationResult: .failure(failure))
  }

  /// Runs an invocation that cooperatively completes with `value` when its task is cancelled.
  public func run(completingOnCancellationWith value: Success) async throws(Failure) -> Success {
    try await run(cancellationResult: .success(value))
  }

  public func waitUntilStarted() async {
    await waitUntilStarted(callCount: 1)
  }

  public func waitUntilStarted(callCount expectedCallCount: Int) async {
    await started.wait(for: expectedCallCount)
  }

  public func waitUntilCancelled() async {
    await waitUntilCancelled(callCount: 1)
  }

  public func waitUntilCancelled(callCount expectedCallCount: Int) async {
    await cancelled.wait(for: expectedCallCount)
  }

  public func waitUntilFinished() async {
    await waitUntilFinished(callCount: 1)
  }

  public func waitUntilFinished(callCount expectedCallCount: Int) async {
    await completed.wait(for: expectedCallCount)
  }

  public func resume(returning value: Success) {
    resumeFirstPending(with: .success(value))
  }

  public func resume(throwing failure: Failure) {
    resumeFirstPending(with: .failure(failure))
  }

  public func resume(call: Int, returning value: Success) {
    resume(call: call, with: .success(value))
  }

  public func resume(call: Int, throwing failure: Failure) {
    resume(call: call, with: .failure(failure))
  }

  /// Completes every current and future invocation with the same successful result.
  public func completeAll(returning value: Success) {
    completeAll(with: .success(value))
  }

  /// Completes every current and future invocation with the same failure.
  public func completeAll(throwing failure: Failure) {
    completeAll(with: .failure(failure))
  }

  // MARK: Private

  private typealias OperationResult = Result<Success, Failure>

  private let started = TestEventCounter()
  private let cancelled = TestEventCounter()
  private let completed = TestEventCounter()
  private var pending = [Int: CheckedContinuation<OperationResult, Never>]()
  private var queuedResults = [Int: OperationResult]()
  private var terminalResult: OperationResult?
  private var cancelledCalls = Set<Int>()
  private var resolvedCalls = Set<Int>()
  private var completedCalls = Set<Int>()

  private func run(cancellationResult: OperationResult?) async throws(Failure) -> Success {
    let call = started.count + 1
    started.record()

    let result = await withTaskCancellationHandler {
      await withCheckedContinuation {
        (continuation: CheckedContinuation<OperationResult, Never>) in
        if Task.isCancelled {
          recordCancellation(call: call, result: cancellationResult)
        }

        if resolvedCalls.contains(call) {
          guard let cancellationResult else {
            preconditionFailure(
              "A non-cooperative controllable operation resolved without an explicit result"
            )
          }
          continuation.resume(returning: cancellationResult)
        } else if let result = queuedResults.removeValue(forKey: call) {
          resolvedCalls.insert(call)
          continuation.resume(returning: result)
        } else if let terminalResult {
          resolvedCalls.insert(call)
          continuation.resume(returning: terminalResult)
        } else {
          pending[call] = continuation
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.recordCancellation(call: call, result: cancellationResult)
      }
    }

    recordCompletion(call: call)
    return try result.get()
  }

  private func recordCancellation(
    call: Int,
    result: OperationResult?,
  ) {
    guard !completedCalls.contains(call) else { return }
    guard cancelledCalls.insert(call).inserted else { return }

    cancelled.record()
    guard let result else { return }
    guard resolvedCalls.insert(call).inserted else { return }
    queuedResults.removeValue(forKey: call)
    pending.removeValue(forKey: call)?.resume(returning: result)
  }

  private func recordCompletion(call: Int) {
    guard completedCalls.insert(call).inserted else { return }
    completed.record()
  }

  private func resumeFirstPending(with result: OperationResult) {
    let call = (1...max(started.count, 1)).first {
      !resolvedCalls.contains($0) && queuedResults[$0] == nil
    } ?? started.count + 1
    resume(call: call, with: result)
  }

  private func resume(call: Int, with result: OperationResult) {
    precondition(call > 0, "Controllable operation call numbers are one-based")
    precondition(terminalResult == nil, "A terminal controllable operation cannot be resumed")
    precondition(
      !resolvedCalls.contains(call) && queuedResults[call] == nil,
      "A controllable operation invocation must be resumed exactly once",
    )

    if let continuation = pending.removeValue(forKey: call) {
      resolvedCalls.insert(call)
      continuation.resume(returning: result)
    } else {
      queuedResults[call] = result
    }
  }

  private func completeAll(with result: OperationResult) {
    terminalResult = result
    queuedResults.removeAll()
    let pending = pending
    self.pending.removeAll()
    for (call, continuation) in pending {
      guard resolvedCalls.insert(call).inserted else { continue }
      continuation.resume(returning: result)
    }
  }
}

extension ControllableOperation where Success == Void {
  /// Completes every current and future invocation successfully.
  public func finish() {
    completeAll(returning: ())
  }
}
