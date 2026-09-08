import Foundation
import os

// MARK: - _AnyEffectJob

@MainActor
protocol _AnyEffectJob: AnyObject, Sendable {
  var id: UUID { get }
  var cancellation: _EffectCancellation { get }

  func start()
  func cancel(_ reason: _EffectCancellationReason)
  func wait() async
}

// MARK: - _EffectJob

@MainActor
final class _EffectJob<Output: Sendable>: _AnyEffectJob {

  // MARK: Lifecycle

  init(
    operation: @escaping @MainActor @Sendable (EffectContext) async throws -> Output,
    receive: (@MainActor @Sendable (Result<Output, any Error>) -> Void)?,
    receivesFailures: Bool,
    didFinish: @escaping @MainActor @Sendable (UUID) -> Void,
  ) {
    self.operation = operation
    self.receive = receive
    self.receivesFailures = receivesFailures
    self.didFinish = didFinish
    cancellation.onCancel { [weak self] in
      Task { @MainActor [weak self] in
        self?.finishIfPendingCancellation()
      }
    }
  }

  // MARK: Internal

  let id = UUID()
  let cancellation = _EffectCancellation()

  var result: EffectOutcome<Output> {
    get async {
      if let outcome { return outcome }
      return await withCheckedContinuation { waiters.append($0) }
    }
  }

  func wait() async {
    _ = await result
  }

  func start() {
    guard !hasStarted, outcome == nil, let operation else { return }
    guard cancellation.isCurrent else {
      finish(.failure(CancellationError()))
      return
    }
    hasStarted = true
    self.operation = nil
    let context = EffectContext(cancellation: cancellation)
    let task = Task { @MainActor in
      let result: Result<Output, any Error>
      do {
        try context.checkCancellation()
        result = .success(try await operation(context))
      } catch {
        result = .failure(error)
      }
      finish(result)
    }
    cancellation.install(task: task)
  }

  func cancel(_ reason: _EffectCancellationReason) {
    cancellation.cancel(reason)
    finishIfPendingCancellation()
  }

  func reject() {
    finish(.failure(EffectQueueFullError()))
  }

  // MARK: Private

  private static var logger: Logger {
    Logger(subsystem: "VISOR", category: "Effects")
  }

  private var operation: (@MainActor @Sendable (EffectContext) async throws -> Output)?
  private var receive: (@MainActor @Sendable (Result<Output, any Error>) -> Void)?
  private let didFinish: @MainActor @Sendable (UUID) -> Void
  private let receivesFailures: Bool
  private var outcome: EffectOutcome<Output>?
  private var waiters = [CheckedContinuation<EffectOutcome<Output>, Never>]()
  private var hasStarted = false
  private var isFinishing = false

  private func finishIfPendingCancellation() {
    guard !hasStarted, !cancellation.isCurrent else { return }
    finish(.failure(CancellationError()))
  }

  private func finish(_ result: Result<Output, any Error>) {
    guard outcome == nil, !isFinishing else { return }
    isFinishing = true
    let reason = cancellation.finish()
    let completed: EffectOutcome<Output> =
      switch reason {
      case .cancelled: .cancelled
      case .superseded: .superseded
      case nil:
        switch result {
        case .success(let output): .success(output)
        case .failure(let error) where error is CancellationError:
          .cancelled
        case .failure(let error): .failure(error)
        }
      }

    // Cancellation is claimed before delivery. Replacement and delivery both
    // run on MainActor with no suspension between this check and the callback.
    switch completed {
    case .success, .failure:
      if let receive {
        receive(result)
      }
      if case .failure = completed, receive == nil || !receivesFailures {
        Self.logger.error("Managed effect failed without a receiver; inspect its completion handle.")
      }

    case .cancelled, .superseded:
      break
    }
    operation = nil
    receive = nil
    outcome = completed
    let continuations = waiters
    waiters.removeAll()
    for continuation in continuations { continuation.resume(returning: completed) }
    didFinish(id)
  }
}

// MARK: - _EffectRuntime

/// The public owner never appears in a running task's capture graph. Releasing
/// it releases this runtime and cancels all outstanding jobs, including queued
/// jobs whose handles are retained elsewhere.
@MainActor
final class _EffectRuntime {

  // MARK: Lifecycle

  init(policy: Policy) {
    self.policy = policy
  }

  deinit {
    for cancellation in cancellations.values { cancellation.cancel(.cancelled) }
  }

  // MARK: Internal

  enum Policy {
    case latest
    case serial(capacity: Int?)
    case concurrent
  }

  func submit<Output: Sendable>(
    operation: @escaping @MainActor @Sendable (EffectContext) async throws -> Output,
    receivesFailures: Bool = true,
    receive: (@MainActor @Sendable (Result<Output, any Error>) -> Void)? = nil,
  ) -> EffectHandle<Output> {
    let job = _EffectJob(operation: operation, receive: receive, receivesFailures: receivesFailures) { [weak self] id in
      self?.finished(id)
    }
    let handle = EffectHandle(job: job)
    if case .serial(let capacity) = policy, let capacity, jobs.count >= capacity {
      job.reject()
      return handle
    }
    jobs[job.id] = job
    cancellations[job.id] = job.cancellation
    switch policy {
    case .latest:
      let previous = currentID.flatMap { jobs[$0] }
      currentID = job.id
      // Cancellation handlers can submit newer work synchronously. Publish
      // this invocation first and preserve any re-entrant replacement.
      previous?.cancel(.superseded)
      job.start()

    case .concurrent:
      job.start()

    case .serial:
      pending.append(job.id)
      startNext()
    }
    return handle
  }

  func cancelAll() {
    for job in Array(jobs.values) { job.cancel(.cancelled) }
  }

  /// Joins a snapshot of submissions, without following future submissions.
  func finish() async {
    let snapshot = Array(jobs.values)
    for job in snapshot { await job.wait() }
  }

  // MARK: Private

  private let policy: Policy
  private var jobs = [UUID: any _AnyEffectJob]()
  private var cancellations = [UUID: _EffectCancellation]()
  private var currentID: UUID?
  private var pending = [UUID]()
  private var pendingIndex = 0

  private func finished(_ id: UUID) {
    jobs[id] = nil
    cancellations[id] = nil
    if currentID == id { currentID = nil }
    if case .serial = policy { startNext() }
  }

  private func startNext() {
    guard currentID == nil else { return }
    while pendingIndex < pending.count {
      let id = pending[pendingIndex]
      pendingIndex += 1
      guard let job = jobs[id] else { continue }
      currentID = id
      job.start()
      break
    }
    if pendingIndex == pending.count {
      pending.removeAll(keepingCapacity: true)
      pendingIndex = 0
    }
  }
}
