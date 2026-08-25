import Foundation
import os

// MARK: - ObservationSourceError

/// A failure encountered while iterating an ``ObservationSource`` directly.
///
/// Cancellation is a normal sequence-lifecycle event and finishes iteration
/// without throwing. These cases instead indicate that the source can no
/// longer provide coherent snapshots. Every case is terminal for that source:
/// stop its consumer and replace the producer-owned channel to recover.
nonisolated public enum ObservationSourceError: Error, Equatable, Sendable {
  /// The source stopped without a normal producer-lifecycle completion.
  case terminatedUnexpectedly

  /// The observation runtime rejected an inconsistent operation.
  ///
  /// - Parameter detail: A diagnostic description of the failed invariant.
  case runtimeFailure(detail: String)
}

// MARK: LocalizedError

extension ObservationSourceError: LocalizedError {
  /// A human-readable explanation suitable for diagnostics.
  public var errorDescription: String? {
    switch self {
    case .terminatedUnexpectedly:
      "The observation source terminated unexpectedly."
    case .runtimeFailure(let detail):
      "The observation source runtime failed: \(detail)"
    }
  }
}

// MARK: - _ObservationGroupID

nonisolated package struct _ObservationGroupID: Hashable, Sendable {
  fileprivate let rawValue: UUID
}

// MARK: - _ObservationGroupCore

nonisolated private final class _ObservationGroupCore: Sendable {

  // MARK: Fileprivate

  fileprivate let id = _ObservationGroupID(rawValue: UUID())

  fileprivate func withLock<Result: Sendable>(
    _ body: @Sendable () throws -> Result
  ) rethrows -> Result {
    try lock.withLock { _ in try body() }
  }

  // MARK: Private

  private let lock = OSAllocatedUnfairLock(initialState: ())

}

// MARK: - ObservationSource

/// A stable, read-only latest-State capability.
///
/// Published snapshots must retain stable contents after publication. The
/// runtime does not deep-copy values or diagnose transitive mutable aliases.
/// Iterate the source directly to receive its baseline and latest revisions;
/// every iterator owns an independent subscription.
nonisolated public struct ObservationSource<Value: Sendable>:
  AsyncSequence,
  Sendable
{

  // MARK: Public

  /// The snapshot emitted by this sequence.
  public typealias Element = Value

  /// An independently owned iterator over this source.
  public typealias AsyncIterator = ObservationSnapshots<Value>.Iterator

  /// An explicit spelling for this source's initial-plus-latest sequence.
  ///
  /// Use this sequence from a service-owned task when one producer reacts to
  /// another producer's durable latest State. Each iterator opens a separate
  /// subscription, emits the atomic baseline, and then emits the newest
  /// available snapshot after publications. Intermediate snapshots may be
  /// coalesced while the consumer is busy.
  ///
  /// This sequence is deliberately outside generated ViewModel readiness,
  /// acknowledgements, and `VISORTesting.perform` fences. ViewModels should use
  /// `@Bound` and `@Reaction` instead. Lossless occurrences require an explicit
  /// buffered event sequence.
  public var snapshots: ObservationSnapshots<Value> {
    ObservationSnapshots(source: self)
  }

  /// Creates a source whose snapshot never changes.
  ///
  /// Retain the returned source as stable producer or test-double state. Do
  /// not recreate it from a computed source property because each call would
  /// have a different source identity.
  public static func constant(_ snapshot: sending Value) -> Self {
    ObservationChannel(snapshot).source
  }

  /// Returns the source's latest published snapshot synchronously.
  public func currentSnapshot() -> Value {
    core.currentSnapshot()
  }

  /// Opens an independently owned initial-plus-latest snapshot stream.
  ///
  /// Direct iteration is equivalent to iterating ``snapshots``. Each iterator
  /// owns a separate subscription. Iteration throws ``ObservationSourceError``
  /// if the source can no longer provide coherent snapshots.
  public func makeAsyncIterator() -> AsyncIterator {
    snapshots.makeAsyncIterator()
  }

  // MARK: Package

  package var _visorIdentity: _ObservationSourceID {
    core.sourceID
  }

  package var _visorGroupIdentity: _ObservationGroupID {
    core.group.id
  }

  package var _visorActiveSubscriptionCount: Int {
    core.activeSubscriptionCount()
  }

  /// Generated control-plane code opens synchronously. Registration and the
  /// baseline read occur in one critical section, leaving no suspension gap.
  package func _visorOpen() throws -> _OpenObservation<Value> {
    try core.open()
  }

  package func _visorErase() -> _AnyObservationSource {
    _AnyObservationSource(
      sourceID: core.sourceID,
      group: core.group,
      validatePrepareLocked: {
        try core.validateOpenAssumingGroupLocked()
      },
      prepareLocked: {
        _AnyPreparedObservation(
          try core.prepareOpenAssumingGroupLocked()
        )
      },
    )
  }

  // MARK: Fileprivate

  fileprivate let core: _ObservationCore<Value>

}

// MARK: - ObservationSnapshots

/// An independently owned initial-plus-latest sequence from one source.
nonisolated public struct ObservationSnapshots<Value: Sendable>:
  AsyncSequence,
  Sendable
{

  // MARK: Public

  /// The snapshot emitted by this sequence.
  public typealias Element = Value

  /// A single-consumer iterator over an ``ObservationSource``.
  ///
  /// The iterator intentionally does not conform to `Sendable`: its mutable
  /// subscription state must be consumed serially by one task.
  nonisolated public final class Iterator:
    AsyncIteratorProtocol
  {

    // MARK: Lifecycle

    fileprivate init(source: ObservationSource<Value>) {
      self.source = source
    }

    deinit {
      observation?.subscription._visorCancel()
    }

    // MARK: Public

    /// Returns the baseline or newest available snapshot.
    ///
    /// - Returns: The next snapshot, or `nil` after cancellation or normal
    ///   iterator completion.
    /// - Throws: ``ObservationSourceError`` when the source terminates or its
    ///   runtime detects an invalid state transition.
    public func next() async throws(ObservationSourceError) -> Value? {
      guard !isFinished else { return nil }

      do {
        try Task.checkCancellation()
        if observation == nil {
          let observation = try source._visorOpen()
          self.observation = observation
          try Task.checkCancellation()
          return observation.baseline.snapshot
        }

        guard let envelope = try await observation?.subscription._visorNext() else {
          finish()
          return nil
        }
        return envelope.snapshot
      } catch is CancellationError {
        finish()
        return nil
      } catch let failure as _ObservationSourceFailure {
        finish()
        throw ObservationSourceError(failure)
      } catch {
        finish()
        throw .runtimeFailure(detail: String(describing: error))
      }
    }

    // MARK: Private

    private let source: ObservationSource<Value>
    private var observation: _OpenObservation<Value>?
    private var isFinished = false

    private func finish() {
      guard !isFinished else { return }
      isFinished = true
      observation?.subscription._visorCancel()
      observation = nil
    }
  }

  /// Opens an iterator with an independent source subscription.
  public func makeAsyncIterator() -> Iterator {
    Iterator(source: source)
  }

  // MARK: Fileprivate

  fileprivate let source: ObservationSource<Value>

}

// MARK: - ObservationChannel

/// A producer-owned latest-State channel.
///
/// `Value: Sendable` protects isolation transfer, but cannot prove transitive
/// value semantics. Producers must publish stable full snapshots.
nonisolated public final class ObservationChannel<Value: Sendable>: Sendable {

  // MARK: Lifecycle

  /// Creates a producer channel with its initial snapshot.
  public init(_ initialSnapshot: sending Value) {
    let core = _ObservationCore(
      initialSnapshot,
      group: _ObservationGroupCore(),
    )
    self.core = core
    source = ObservationSource(core: core)
  }

  /// Creates another performance lane coordinated with the anchor channel.
  ///
  /// When one observation session opens or checkpoints several coordinated
  /// channels, their participating baselines or pause revisions are captured
  /// under one coordination lock. Publication to any coordinated channel
  /// therefore falls wholly before or after that multi-channel capture.
  /// Checkpoint acknowledgement occurs after the capture lock is released.
  ///
  /// Coordination does not make sequential `publish` calls transactional,
  /// coordinate handler execution, or add undeclared channels to a session.
  /// Use one snapshot when values must share one publication revision.
  public init(
    _ initialSnapshot: sending Value,
    coordinatedWith anchor: ObservationChannel<some Sendable>,
  ) {
    let core = _ObservationCore(
      initialSnapshot,
      group: anchor.core.group,
    )
    self.core = core
    source = ObservationSource(core: core)
  }

  // MARK: Public

  /// The stable, read-only capability distributed to consumers.
  public let source: ObservationSource<Value>

  /// Publication is deliberately synchronous. An actor service can mutate its
  /// domain state and publish the matching snapshot in the same actor turn.
  ///
  /// - Parameter snapshot: A stable snapshot that will not be mutated through
  ///   a shared reference after publication.
  public func publish(_ snapshot: sending Value) {
    core.publish(snapshot)
  }

  // MARK: Package

  package func _visorTerminate(
    with failure: _ObservationSourceFailure = .unexpectedTermination
  ) {
    core.terminate(with: failure)
  }

  // MARK: Private

  private let core: _ObservationCore<Value>

}

// MARK: - _ObservationSourceFailure

nonisolated package enum _ObservationSourceFailure:
  Error,
  Equatable,
  Sendable
{
  case unexpectedTermination
  case failed(String)
  /// The current revision reached `UInt64.max`; no later publication can be ordered.
  case revisionExhausted
  case protocolViolation(String)
  case safetyDeadlineExceeded(
    phase: String,
    sourceIDs: [_ObservationSourceID],
    omittedSourceCount: Int,
  )
}

extension ObservationSourceError {
  fileprivate init(_ failure: _ObservationSourceFailure) {
    switch failure {
    case .unexpectedTermination:
      self = .terminatedUnexpectedly

    case .revisionExhausted:
      self = .runtimeFailure(
        detail: "The observation source exhausted its internal revision space."
      )

    case .failed(let detail), .protocolViolation(let detail):
      self = .runtimeFailure(detail: detail)

    case .safetyDeadlineExceeded(
      let phase,
      let sourceIDs,
      let omittedSourceCount,
    ):
      let visibleSourceCount = sourceIDs.count
      let totalSourceCount = visibleSourceCount + omittedSourceCount
      self = .runtimeFailure(
        detail: "Safety deadline exceeded during \(phase) for \(totalSourceCount) source(s)"
      )
    }
  }
}

// MARK: - _ObservationSourceID

nonisolated package struct _ObservationSourceID: Hashable, Sendable {
  fileprivate let rawValue: UUID
}

// MARK: - _ObservationEpoch

nonisolated package struct _ObservationEpoch: Hashable, Sendable {
  fileprivate let rawValue: UUID
}

// MARK: - _ObservationEnvelope

nonisolated package struct _ObservationEnvelope<Value: Sendable>: Sendable {
  package let sourceID: _ObservationSourceID
  package let epoch: _ObservationEpoch
  package let revision: UInt64
  package let snapshot: Value
}

// MARK: - _ObservationCheckpoint

nonisolated package struct _ObservationCheckpoint<Value: Sendable>: Sendable {
  fileprivate let subscriptionID: UUID
  package let envelope: _ObservationEnvelope<Value>
}

// MARK: - _OpenObservation

nonisolated package struct _OpenObservation<Value: Sendable>: Sendable {
  package let baseline: _ObservationEnvelope<Value>
  package let subscription: _ObservationSubscription<Value>
}

// MARK: - _PreparedObservation

nonisolated package struct _PreparedObservation<Value: Sendable>: Sendable {
  package var baseline: _ObservationEnvelope<Value> {
    openObservation.baseline
  }

  package func _visorActivate() -> _OpenObservation<Value> {
    openObservation
  }

  package func _visorCancel() {
    openObservation.subscription._visorCancel()
  }

  fileprivate let openObservation: _OpenObservation<Value>

}

// MARK: - _ObservationSubscription

nonisolated package struct _ObservationSubscription<Value: Sendable>: Sendable {

  // MARK: Package

  package func _visorNext() async throws -> _ObservationEnvelope<Value>? {
    try await core.next(for: id)
  }

  package func _visorAcknowledge(
    _ envelope: _ObservationEnvelope<Value>
  ) throws {
    try core.acknowledge(envelope, for: id)
  }

  package func _visorCheckpointAndPause() throws -> _ObservationCheckpoint<Value> {
    try core.checkpointAndPause(id: id)
  }

  package func _visorWaitUntilAcknowledged(
    _ checkpoint: _ObservationCheckpoint<Value>
  ) async throws {
    try await core.waitUntilAcknowledged(checkpoint, for: id)
  }

  package func _visorClaimForDirectReconciliation(
    _ checkpoint: _ObservationCheckpoint<Value>
  ) throws -> _ObservationEnvelope<Value> {
    try core.claimForDirectReconciliation(checkpoint, for: id)
  }

  package func _visorResume(
    after checkpoint: _ObservationCheckpoint<Value>
  ) throws {
    try core.resume(after: checkpoint, for: id)
  }

  package func _visorCancel() {
    core.cancel(id: id)
  }

  package func _visorErase() -> _AnyObservationSubscription {
    _AnyObservationSubscription(self)
  }

  // MARK: Fileprivate

  fileprivate let id: UUID
  fileprivate let core: _ObservationCore<Value>

}

// MARK: - _PreparedObservationStorage

nonisolated private protocol _PreparedObservationStorage: Sendable { }

// MARK: - _PreparedObservationBox

nonisolated private struct _PreparedObservationBox<Value: Sendable>:
  _PreparedObservationStorage,
  Sendable
{
  let observation: _PreparedObservation<Value>
}

// MARK: - _AnyPreparedObservation

nonisolated package struct _AnyPreparedObservation: Sendable {

  // MARK: Lifecycle

  fileprivate init(
    _ observation: _PreparedObservation<some Sendable>
  ) {
    sourceID = observation.baseline.sourceID
    groupID = observation.openObservation.subscription.core.group.id
    storage = _PreparedObservationBox(observation: observation)
    cancelOperation = { observation._visorCancel() }
  }

  // MARK: Package

  package let sourceID: _ObservationSourceID
  package let groupID: _ObservationGroupID

  package func _visorUnwrap<Value: Sendable>(
    as _: Value.Type = Value.self
  ) throws -> _PreparedObservation<Value> {
    guard let box = storage as? _PreparedObservationBox<Value> else {
      throw _ObservationSourceFailure.protocolViolation(
        "A prepared source was adopted by a lane with another value type"
      )
    }
    return box.observation
  }

  package func _visorCancel() {
    cancelOperation()
  }

  // MARK: Fileprivate

  fileprivate let storage: any _PreparedObservationStorage

  // MARK: Private

  private let cancelOperation: @Sendable () -> Void

}

// MARK: - _AnyObservationSource

nonisolated package struct _AnyObservationSource: Sendable {

  // MARK: Lifecycle

  fileprivate init(
    sourceID: _ObservationSourceID,
    group: _ObservationGroupCore,
    validatePrepareLocked: @escaping @Sendable () throws -> Void,
    prepareLocked: @escaping @Sendable () throws -> _AnyPreparedObservation,
  ) {
    self.sourceID = sourceID
    groupID = group.id
    self.group = group
    self.validatePrepareLocked = validatePrepareLocked
    self.prepareLocked = prepareLocked
  }

  // MARK: Package

  package let sourceID: _ObservationSourceID
  package let groupID: _ObservationGroupID

  // MARK: Fileprivate

  fileprivate let group: _ObservationGroupCore
  fileprivate let validatePrepareLocked: @Sendable () throws -> Void
  fileprivate let prepareLocked: @Sendable () throws -> _AnyPreparedObservation

}

// MARK: - _AnyDeliveryResumption

nonisolated private struct _AnyDeliveryResumption: Sendable {
  init(_ resumption: _NextResumption<some Sendable>) {
    resumeValue = {
      resumption.continuation.resume(returning: resumption.envelope)
    }
    resumeCancellation = {
      resumption.continuation.resume(throwing: CancellationError())
    }
  }

  let resumeValue: @Sendable () -> Void
  let resumeCancellation: @Sendable () -> Void

}

// MARK: - _ObservationRetirementStorage

nonisolated private protocol _ObservationRetirementStorage: Sendable { }

// MARK: - _ObservationRetirementBox

nonisolated private struct _ObservationRetirementBox<Value: Sendable>:
  _ObservationRetirementStorage,
  Sendable
{
  let envelope: _ObservationEnvelope<Value>
}

// MARK: - _AnyObservationRetirement

/// Keeps a user-supplied snapshot alive until the caller has left every source
/// and group critical section. A snapshot's `deinit` can execute arbitrary
/// synchronous code, including re-entering its producer channel.
nonisolated private struct _AnyObservationRetirement: Sendable {
  init(_ envelope: _ObservationEnvelope<some Sendable>) {
    storage = _ObservationRetirementBox(envelope: envelope)
  }

  func afterUnlock(_ operation: () -> Void) {
    withExtendedLifetime(storage, operation)
  }

  private let storage: any _ObservationRetirementStorage

}

// MARK: - _AnyResumeOutcome

nonisolated private struct _AnyResumeOutcome: Sendable {

  // MARK: Lifecycle

  init(_ outcome: _ResumeOutcome<some Sendable>) {
    resumption = outcome.resumption.map(_AnyDeliveryResumption.init)
    retirement = _AnyObservationRetirement(outcome.retiredPauseEnvelope)
  }

  // MARK: Internal

  func resumeValueAfterUnlock() {
    retirement.afterUnlock {
      resumption?.resumeValue()
    }
  }

  func resumeCancellationAfterUnlock() {
    retirement.afterUnlock {
      resumption?.resumeCancellation()
    }
  }

  // MARK: Private

  private let resumption: _AnyDeliveryResumption?
  private let retirement: _AnyObservationRetirement

}

// MARK: - _AnyObservationCheckpoint

nonisolated package struct _AnyObservationCheckpoint: Sendable {

  // MARK: Lifecycle

  fileprivate init<Value: Sendable>(
    checkpoint: _ObservationCheckpoint<Value>,
    subscription: _ObservationSubscription<Value>,
  ) {
    sourceID = checkpoint.envelope.sourceID
    groupID = subscription.core.group.id
    group = subscription.core.group
    storage = _ObservationCheckpointBox(checkpoint: checkpoint)
    waitOperation = {
      try await subscription._visorWaitUntilAcknowledged(checkpoint)
    }
    resumeLockedOperation = {
      _AnyResumeOutcome(
        try subscription.core.resumeAssumingGroupLocked(
          after: checkpoint,
          for: subscription.id,
        )
      )
    }
    cancelOperation = { subscription._visorCancel() }
  }

  // MARK: Package

  package let sourceID: _ObservationSourceID
  package let groupID: _ObservationGroupID

  package func _visorUnwrap<Value: Sendable>(
    as _: Value.Type = Value.self
  ) throws -> _ObservationCheckpoint<Value> {
    guard let box = storage as? _ObservationCheckpointBox<Value> else {
      throw _ObservationSourceFailure.protocolViolation(
        "A checkpoint was adopted by a lane with another value type"
      )
    }
    return box.checkpoint
  }

  // MARK: Fileprivate

  fileprivate let group: _ObservationGroupCore
  fileprivate let storage: any _ObservationCheckpointStorage
  fileprivate let resumeLockedOperation:
    @Sendable () throws -> _AnyResumeOutcome

  fileprivate func waitUntilAcknowledged() async throws {
    try await waitOperation()
  }

  fileprivate func cancel() {
    cancelOperation()
  }

  // MARK: Private

  private let waitOperation: @Sendable () async throws -> Void
  private let cancelOperation: @Sendable () -> Void

}

// MARK: - _ObservationCheckpointStorage

nonisolated private protocol _ObservationCheckpointStorage: Sendable { }

// MARK: - _ObservationCheckpointBox

nonisolated private struct _ObservationCheckpointBox<Value: Sendable>:
  _ObservationCheckpointStorage,
  Sendable
{
  let checkpoint: _ObservationCheckpoint<Value>
}

// MARK: - _AnyObservationSubscription

nonisolated package struct _AnyObservationSubscription: Sendable {

  // MARK: Lifecycle

  fileprivate init(
    _ subscription: _ObservationSubscription<some Sendable>
  ) {
    sourceID = subscription.core.sourceID
    groupID = subscription.core.group.id
    group = subscription.core.group
    subscriptionID = subscription.id
    validateCheckpointLockedOperation = {
      try subscription.core.validateCheckpointAssumingGroupLocked(
        id: subscription.id
      )
    }
    checkpointLockedOperation = {
      let outcome = try subscription.core
        .checkpointAndPauseAssumingGroupLocked(id: subscription.id)
      return (
        _AnyObservationCheckpoint(
          checkpoint: outcome.checkpoint,
          subscription: subscription,
        ),
        outcome.resumption.map(_AnyDeliveryResumption.init),
      )
    }
    cancelOperation = { subscription._visorCancel() }
  }

  // MARK: Package

  package let sourceID: _ObservationSourceID
  package let groupID: _ObservationGroupID

  package func _visorCancel() {
    cancelOperation()
  }

  // MARK: Fileprivate

  fileprivate let group: _ObservationGroupCore
  fileprivate let subscriptionID: UUID
  fileprivate let checkpointLockedOperation:
    @Sendable () throws -> (_AnyObservationCheckpoint, _AnyDeliveryResumption?)
  fileprivate let validateCheckpointLockedOperation: @Sendable () throws -> Void

  // MARK: Private

  private let cancelOperation: @Sendable () -> Void

}

// MARK: - _ObservationRuntime

/// Provisional underscored operations used by generated session code.
nonisolated package enum _ObservationRuntime {

  // MARK: Package

  package static func _visorPrepareAll(
    _ sources: [_AnyObservationSource]
  ) throws -> [_AnyPreparedObservation] {
    guard Set(sources.map(\.sourceID)).count == sources.count else {
      throw _ObservationSourceFailure.protocolViolation(
        "One generated session lane must own each source subscription"
      )
    }

    let groups = sourceGroups(sources)
    let resolved = OSAllocatedUnfairLock(
      initialState: [PreparedResult]()
    )

    do {
      for entries in groups {
        try Task.checkCancellation()
        guard let group = entries.first?.source.group else { continue }
        try group.withLock {
          for entry in entries {
            try entry.source.validatePrepareLocked()
          }
          for entry in entries {
            try Task.checkCancellation()
            let observation = try entry.source.prepareLocked()
            resolved.withLock {
              $0.append(
                PreparedResult(
                  index: entry.index,
                  observation: observation,
                )
              )
            }
          }
        }
      }

      let ordered = resolved.withLock { $0.sorted { $0.index < $1.index } }
      guard ordered.count == sources.count else {
        throw _ObservationSourceFailure.protocolViolation(
          "The grouped source preparation returned an incomplete result"
        )
      }
      return ordered.map(\.observation)
    } catch {
      for result in resolved.withLock({ $0 }) {
        result.observation._visorCancel()
      }
      throw error
    }
  }

  package static func _visorCheckpointAndPauseAll(
    _ subscriptions: [_AnyObservationSubscription]
  ) throws -> [_AnyObservationCheckpoint] {
    guard
      Set(subscriptions.map(\.subscriptionID)).count
      == subscriptions.count
    else {
      throw _ObservationSourceFailure.protocolViolation(
        "A subscription cannot appear twice in one checkpoint"
      )
    }

    let groups = subscriptionGroups(subscriptions)
    let checkpointResults = OSAllocatedUnfairLock(
      initialState: [CheckpointResult]()
    )
    let resumptions = OSAllocatedUnfairLock(
      initialState: [_AnyDeliveryResumption]()
    )

    do {
      for entries in groups {
        try Task.checkCancellation()
        guard let group = entries.first?.subscription.group else { continue }
        try group.withLock {
          for entry in entries {
            try entry.subscription.validateCheckpointLockedOperation()
          }
          for entry in entries {
            try Task.checkCancellation()
            let (checkpoint, resumption) = try entry.subscription
              .checkpointLockedOperation()
            checkpointResults.withLock {
              $0.append(
                CheckpointResult(
                  index: entry.index,
                  checkpoint: checkpoint,
                )
              )
            }
            if let resumption {
              resumptions.withLock { $0.append(resumption) }
            }
          }
        }
      }

      for resumption in resumptions.withLock({ $0 }) {
        resumption.resumeValue()
      }

      let ordered = checkpointResults.withLock {
        $0.sorted { $0.index < $1.index }
      }
      guard ordered.count == subscriptions.count else {
        throw _ObservationSourceFailure.protocolViolation(
          "The grouped checkpoint returned an incomplete result"
        )
      }
      return ordered.map(\.checkpoint)
    } catch {
      for resumption in resumptions.withLock({ $0 }) {
        resumption.resumeCancellation()
      }
      for subscription in subscriptions {
        subscription._visorCancel()
      }
      throw error
    }
  }

  package static func _visorWaitUntilAcknowledgedAll(
    _ checkpoints: [_AnyObservationCheckpoint]
  ) async throws {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        for checkpoint in checkpoints {
          group.addTask {
            try await checkpoint.waitUntilAcknowledged()
          }
        }
        try await group.waitForAll()
      }
    } catch {
      for checkpoint in checkpoints {
        checkpoint.cancel()
      }
      throw error
    }
  }

  package static func _visorResumeAll(
    after checkpoints: [_AnyObservationCheckpoint]
  ) throws {
    let groups = checkpointGroups(checkpoints)
    let outcomes = OSAllocatedUnfairLock(
      initialState: [_AnyResumeOutcome]()
    )

    do {
      for entries in groups {
        try Task.checkCancellation()
        guard let group = entries.first?.checkpoint.group else { continue }
        try group.withLock {
          for entry in entries {
            try Task.checkCancellation()
            let outcome = try entry.checkpoint.resumeLockedOperation()
            outcomes.withLock { $0.append(outcome) }
          }
        }
      }
      for outcome in outcomes.withLock({ $0 }) {
        outcome.resumeValueAfterUnlock()
      }
    } catch {
      for outcome in outcomes.withLock({ $0 }) {
        outcome.resumeCancellationAfterUnlock()
      }
      for checkpoint in checkpoints {
        checkpoint.cancel()
      }
      throw error
    }
  }

  // MARK: Private

  private struct IndexedSource: Sendable {
    let index: Int
    let source: _AnyObservationSource
  }

  private struct PreparedResult: Sendable {
    let index: Int
    let observation: _AnyPreparedObservation
  }

  private struct CheckpointResult: Sendable {
    let index: Int
    let checkpoint: _AnyObservationCheckpoint
  }

  private struct IndexedSubscription: Sendable {
    let index: Int
    let subscription: _AnyObservationSubscription
  }

  private struct IndexedCheckpoint: Sendable {
    let checkpoint: _AnyObservationCheckpoint
  }

  private static func sourceGroups(
    _ sources: [_AnyObservationSource]
  ) -> [[IndexedSource]] {
    var positions = [_ObservationGroupID: Int]()
    var result = [[IndexedSource]]()
    for (index, source) in sources.enumerated() {
      if let position = positions[source.groupID] {
        result[position].append(IndexedSource(index: index, source: source))
      } else {
        positions[source.groupID] = result.count
        result.append([IndexedSource(index: index, source: source)])
      }
    }
    return result
  }

  private static func subscriptionGroups(
    _ subscriptions: [_AnyObservationSubscription]
  ) -> [[IndexedSubscription]] {
    var positions = [_ObservationGroupID: Int]()
    var result = [[IndexedSubscription]]()
    for (index, subscription) in subscriptions.enumerated() {
      if let position = positions[subscription.groupID] {
        result[position].append(
          IndexedSubscription(index: index, subscription: subscription)
        )
      } else {
        positions[subscription.groupID] = result.count
        result.append([
          IndexedSubscription(index: index, subscription: subscription)
        ])
      }
    }
    return result
  }

  private static func checkpointGroups(
    _ checkpoints: [_AnyObservationCheckpoint]
  ) -> [[IndexedCheckpoint]] {
    var positions = [_ObservationGroupID: Int]()
    var result = [[IndexedCheckpoint]]()
    for checkpoint in checkpoints {
      if let position = positions[checkpoint.groupID] {
        result[position].append(
          IndexedCheckpoint(checkpoint: checkpoint)
        )
      } else {
        positions[checkpoint.groupID] = result.count
        result.append([
          IndexedCheckpoint(checkpoint: checkpoint)
        ])
      }
    }
    return result
  }
}

// MARK: - _AcknowledgementWaiter

nonisolated private struct _AcknowledgementWaiter: Sendable {
  let revision: UInt64
  let continuation: CheckedContinuation<Void, any Error>
}

// MARK: - _SubscriptionState

nonisolated private struct _SubscriptionState<Value: Sendable>: Sendable {
  var lastIssuedRevision: UInt64
  var lastAcknowledgedRevision: UInt64?
  var pauseEnvelope: _ObservationEnvelope<Value>?
  var nextWaiter: CheckedContinuation<_ObservationEnvelope<Value>?, any Error>?
  var acknowledgementWaiters = [UUID: _AcknowledgementWaiter]()
}

// MARK: - _CoreState

nonisolated private struct _CoreState<Value: Sendable>: Sendable {
  var current: _ObservationEnvelope<Value>
  var subscriptions = [UUID: _SubscriptionState<Value>]()
  var terminalFailure: _ObservationSourceFailure?
}

// MARK: - _NextResumption

nonisolated private struct _NextResumption<Value: Sendable>: Sendable {
  let continuation: CheckedContinuation<_ObservationEnvelope<Value>?, any Error>
  let envelope: _ObservationEnvelope<Value>
}

// MARK: - _CheckpointOutcome

nonisolated private struct _CheckpointOutcome<Value: Sendable>: Sendable {
  let checkpoint: _ObservationCheckpoint<Value>
  let resumption: _NextResumption<Value>?
}

// MARK: - _ResumeOutcome

nonisolated private struct _ResumeOutcome<Value: Sendable>: Sendable {
  let resumption: _NextResumption<Value>?
  let retiredPauseEnvelope: _ObservationEnvelope<Value>
}

// MARK: - _PublicationSuccess

nonisolated private struct _PublicationSuccess<Value: Sendable>: Sendable {
  let resumptions: [_NextResumption<Value>]
  let retiredEnvelope: _ObservationEnvelope<Value>
}

// MARK: - _TerminationResumptions

nonisolated private struct _TerminationResumptions<Value: Sendable>: Sendable {
  var next = [CheckedContinuation<_ObservationEnvelope<Value>?, any Error>]()
  var acknowledgements = [CheckedContinuation<Void, any Error>]()
  var retiredSubscriptions = [_SubscriptionState<Value>]()
}

// MARK: - _NextResolution

nonisolated private enum _NextResolution<Value: Sendable> {
  case suspended
  case value(_ObservationEnvelope<Value>?)
  case failure(any Error)
}

// MARK: - _VoidResolution

nonisolated private enum _VoidResolution {
  case suspended
  case success
  case failure(any Error)
}

// MARK: - _ObservationCore

nonisolated private final class _ObservationCore<Value: Sendable>: Sendable {

  // MARK: Lifecycle

  fileprivate init(
    _ initialSnapshot: sending Value,
    group: _ObservationGroupCore,
  ) {
    let sourceID = _ObservationSourceID(rawValue: UUID())
    let epoch = _ObservationEpoch(rawValue: UUID())
    self.sourceID = sourceID
    self.group = group
    self.epoch = epoch
    lock = OSAllocatedUnfairLock(
      initialState: _CoreState(
        current: _ObservationEnvelope(
          sourceID: sourceID,
          epoch: epoch,
          revision: 0,
          snapshot: initialSnapshot,
        )
      )
    )
  }

  // MARK: Fileprivate

  fileprivate let sourceID: _ObservationSourceID
  fileprivate let group: _ObservationGroupCore

  fileprivate func currentSnapshot() -> Value {
    lock.withLock { $0.current.snapshot }
  }

  fileprivate func activeSubscriptionCount() -> Int {
    lock.withLock { $0.subscriptions.count }
  }

  fileprivate func open() throws -> _OpenObservation<Value> {
    try group.withLock {
      try openAssumingGroupLocked()
    }
  }

  fileprivate func validateOpenAssumingGroupLocked() throws {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
    }
  }

  fileprivate func openAssumingGroupLocked() throws -> _OpenObservation<Value> {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }

      let id = UUID()
      let baseline = state.current
      state.subscriptions[id] = _SubscriptionState(
        lastIssuedRevision: baseline.revision,
        lastAcknowledgedRevision: nil,
        pauseEnvelope: nil,
        nextWaiter: nil,
      )

      return _OpenObservation(
        baseline: baseline,
        subscription: _ObservationSubscription(id: id, core: self),
      )
    }
  }

  fileprivate func prepareOpenAssumingGroupLocked() throws
    -> _PreparedObservation<Value>
  {
    _PreparedObservation(
      openObservation: try openAssumingGroupLocked()
    )
  }

  fileprivate func publish(_ snapshot: sending Value) {
    let snapshot = snapshot
    let outcome = withExtendedLifetime(snapshot) {
      group.withLock {
        lock.withLock {
          state -> Result<_PublicationSuccess<Value>, _ObservationSourceFailure> in
          if let terminalFailure = state.terminalFailure {
            return .failure(terminalFailure)
          }
          guard state.current.revision < .max else {
            return .failure(.revisionExhausted)
          }

          let retiredEnvelope = state.current
          state.current = _ObservationEnvelope(
            sourceID: sourceID,
            epoch: epoch,
            revision: state.current.revision + 1,
            snapshot: snapshot,
          )

          return .success(
            _PublicationSuccess(
              resumptions: deliverLatestWherePossible(in: &state),
              retiredEnvelope: retiredEnvelope,
            )
          )
        }
      }
    }

    switch outcome {
    case .success(let success):
      withExtendedLifetime(success.retiredEnvelope) {
        resume(success.resumptions)
      }

    case .failure(.revisionExhausted):
      terminate(with: .revisionExhausted)

    case .failure(let failure):
      // Observation infrastructure must not infect a valid production
      // mutation. Existing sessions see the failure already latched below.
      terminate(with: failure)
    }
  }

  fileprivate func next(
    for id: UUID
  ) async throws -> _ObservationEnvelope<Value>? {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()

      return try await withCheckedThrowingContinuation { continuation in
        let resolution = lock.withLock { state -> _NextResolution<Value> in
          if let terminalFailure = state.terminalFailure {
            return .failure(terminalFailure)
          }
          guard var subscription = state.subscriptions[id] else {
            return .value(nil)
          }
          if Task.isCancelled {
            return .failure(CancellationError())
          }
          if
            let envelope = takeEligibleEnvelope(
              from: &subscription,
              current: state.current,
            )
          {
            state.subscriptions[id] = subscription
            return .value(envelope)
          }
          guard subscription.nextWaiter == nil else {
            return .failure(
              _ObservationSourceFailure.protocolViolation(
                "A subscription supports one iterator task"
              )
            )
          }

          subscription.nextWaiter = continuation
          state.subscriptions[id] = subscription
          return .suspended
        }

        switch resolution {
        case .suspended:
          break
        case .value(let envelope):
          continuation.resume(returning: envelope)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      // Synchronous cancellation closes the registration race without an
      // unstructured Task hopping to another isolation domain.
      cancel(id: id)
    }
  }

  fileprivate func acknowledge(
    _ envelope: _ObservationEnvelope<Value>,
    for id: UUID,
  ) throws {
    let resumptions = try lock.withLock {
      state -> [CheckedContinuation<Void, any Error>] in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard envelope.sourceID == sourceID, envelope.epoch == epoch else {
        throw _ObservationSourceFailure.protocolViolation(
          "An acknowledgement came from another source or epoch"
        )
      }
      guard envelope.revision <= subscription.lastIssuedRevision else {
        throw _ObservationSourceFailure.protocolViolation(
          "An acknowledgement preceded delivery"
        )
      }
      if
        let lastAcknowledgedRevision = subscription.lastAcknowledgedRevision,
        envelope.revision < lastAcknowledgedRevision
      {
        throw _ObservationSourceFailure.protocolViolation(
          "Acknowledgements must be monotonic"
        )
      }

      subscription.lastAcknowledgedRevision = envelope.revision
      let ready = subscription.acknowledgementWaiters.values.filter {
        $0.revision <= envelope.revision
      }
      subscription.acknowledgementWaiters =
        subscription.acknowledgementWaiters.filter {
          $0.value.revision > envelope.revision
        }
      state.subscriptions[id] = subscription
      return ready.map(\.continuation)
    }

    for continuation in resumptions {
      continuation.resume()
    }
  }

  fileprivate func checkpointAndPause(
    id: UUID
  ) throws -> _ObservationCheckpoint<Value> {
    let outcome = try group.withLock {
      try checkpointAndPauseAssumingGroupLocked(id: id)
    }

    if let resumption = outcome.resumption {
      resumption.continuation.resume(returning: resumption.envelope)
    }
    return outcome.checkpoint
  }

  fileprivate func checkpointAndPauseAssumingGroupLocked(
    id: UUID
  ) throws -> _CheckpointOutcome<Value> {
    try lock.withLock { state -> _CheckpointOutcome<Value> in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard subscription.pauseEnvelope == nil else {
        throw _ObservationSourceFailure.protocolViolation(
          "A subscription is already paused"
        )
      }

      let target = state.current
      subscription.pauseEnvelope = target
      let resumption = takeWaitingDelivery(
        from: &subscription,
        current: state.current,
      )
      state.subscriptions[id] = subscription
      return _CheckpointOutcome(
        checkpoint: _ObservationCheckpoint(
          subscriptionID: id,
          envelope: target,
        ),
        resumption: resumption,
      )
    }
  }

  fileprivate func validateCheckpointAssumingGroupLocked(
    id: UUID
  ) throws {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard let subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard subscription.pauseEnvelope == nil else {
        throw _ObservationSourceFailure.protocolViolation(
          "A subscription is already paused"
        )
      }
    }
  }

  fileprivate func waitUntilAcknowledged(
    _ checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID,
  ) async throws {
    let waiterID = UUID()

    try await withTaskCancellationHandler {
      try Task.checkCancellation()

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let resolution = lock.withLock { state -> _VoidResolution in
          if let terminalFailure = state.terminalFailure {
            return .failure(terminalFailure)
          }
          guard validate(checkpoint, for: id) else {
            return .failure(
              _ObservationSourceFailure.protocolViolation(
                "A checkpoint belongs to another subscription, source or epoch"
              )
            )
          }
          guard var subscription = state.subscriptions[id] else {
            return .failure(CancellationError())
          }
          if Task.isCancelled {
            return .failure(CancellationError())
          }
          if
            let revision = subscription.lastAcknowledgedRevision,
            revision >= checkpoint.envelope.revision
          {
            return .success
          }

          subscription.acknowledgementWaiters[waiterID] =
            _AcknowledgementWaiter(
              revision: checkpoint.envelope.revision,
              continuation: continuation,
            )
          state.subscriptions[id] = subscription
          return .suspended
        }

        switch resolution {
        case .suspended:
          break
        case .success:
          continuation.resume()
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      cancelAcknowledgementWaiter(waiterID: waiterID, for: id)
    }
  }

  fileprivate func claimForDirectReconciliation(
    _ checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID,
  ) throws -> _ObservationEnvelope<Value> {
    try lock.withLock { state in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard validate(checkpoint, for: id) else {
        throw _ObservationSourceFailure.protocolViolation(
          "A checkpoint belongs to another subscription, source or epoch"
        )
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard
        subscription.pauseEnvelope?.revision
        == checkpoint.envelope.revision
      else {
        throw _ObservationSourceFailure.protocolViolation(
          "Only the active pause target can be reconciled directly"
        )
      }
      guard subscription.nextWaiter == nil else {
        throw _ObservationSourceFailure.protocolViolation(
          "A direct reconciliation cannot race the iterator"
        )
      }
      guard checkpoint.envelope.revision >= subscription.lastIssuedRevision else {
        throw _ObservationSourceFailure.protocolViolation(
          "A direct reconciliation cannot move delivery backwards"
        )
      }

      subscription.lastIssuedRevision = checkpoint.envelope.revision
      state.subscriptions[id] = subscription
      return checkpoint.envelope
    }
  }

  fileprivate func resume(
    after checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID,
  ) throws {
    let outcome = try group.withLock {
      try resumeAssumingGroupLocked(after: checkpoint, for: id)
    }

    withExtendedLifetime(outcome.retiredPauseEnvelope) {
      if let resumption = outcome.resumption {
        resumption.continuation.resume(returning: resumption.envelope)
      }
    }
  }

  fileprivate func resumeAssumingGroupLocked(
    after checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID,
  ) throws -> _ResumeOutcome<Value> {
    try lock.withLock { state -> _ResumeOutcome<Value> in
      if let terminalFailure = state.terminalFailure {
        throw terminalFailure
      }
      guard validate(checkpoint, for: id) else {
        throw _ObservationSourceFailure.protocolViolation(
          "A checkpoint belongs to another subscription, source or epoch"
        )
      }
      guard var subscription = state.subscriptions[id] else {
        throw CancellationError()
      }
      guard
        let retiredPauseEnvelope = subscription.pauseEnvelope,
        retiredPauseEnvelope.revision == checkpoint.envelope.revision
      else {
        throw _ObservationSourceFailure.protocolViolation(
          "The checkpoint is not the subscription's active pause"
        )
      }
      guard
        let acknowledged = subscription.lastAcknowledgedRevision,
        acknowledged >= checkpoint.envelope.revision
      else {
        throw _ObservationSourceFailure.protocolViolation(
          "A subscription cannot resume before its target is acknowledged"
        )
      }

      subscription.pauseEnvelope = nil
      let resumption = takeWaitingDelivery(
        from: &subscription,
        current: state.current,
      )
      state.subscriptions[id] = subscription
      return _ResumeOutcome(
        resumption: resumption,
        retiredPauseEnvelope: retiredPauseEnvelope,
      )
    }
  }

  fileprivate func cancel(id: UUID) {
    let subscription = group.withLock {
      cancelAssumingGroupLocked(id: id)
    }
    resumeCancellation(of: subscription)
  }

  fileprivate func cancelAssumingGroupLocked(
    id: UUID
  ) -> _SubscriptionState<Value>? {
    lock.withLock { state in
      state.subscriptions.removeValue(forKey: id)
    }
  }

  fileprivate func resumeCancellation(
    of subscription: _SubscriptionState<Value>?
  ) {
    // Explicitly use the retired pause envelope after unlocking. This prevents
    // ARC lifetime shortening from releasing its snapshot in the inlined
    // `removeValue` critical section when no continuation retains it.
    withExtendedLifetime(subscription?.pauseEnvelope) {
      subscription?.nextWaiter?.resume(returning: nil)
      if let subscription {
        for waiter in subscription.acknowledgementWaiters.values {
          waiter.continuation.resume(throwing: CancellationError())
        }
      }
    }
  }

  fileprivate func terminate(with failure: _ObservationSourceFailure) {
    let resumptions = group.withLock {
      terminateAssumingGroupLocked(with: failure)
    }
    resumeTermination(resumptions, failure: failure)
  }

  fileprivate func terminateAssumingGroupLocked(
    with failure: _ObservationSourceFailure
  ) -> _TerminationResumptions<Value>? {
    lock.withLock { state -> _TerminationResumptions<Value>? in
      guard state.terminalFailure == nil else {
        return nil
      }
      state.terminalFailure = failure
      var resumptions = _TerminationResumptions<Value>()
      // Copy subscription state before clearing it so paused snapshots cannot
      // run arbitrary deinitialisation while either source lock is held.
      resumptions.retiredSubscriptions = Array(state.subscriptions.values)
      for subscription in state.subscriptions.values {
        if let nextWaiter = subscription.nextWaiter {
          resumptions.next.append(nextWaiter)
        }
        resumptions.acknowledgements.append(
          contentsOf: subscription.acknowledgementWaiters.values.map(\.continuation)
        )
      }
      state.subscriptions.removeAll(keepingCapacity: false)
      return resumptions
    }
  }

  fileprivate func resumeTermination(
    _ resumptions: _TerminationResumptions<Value>?,
    failure: _ObservationSourceFailure,
  ) {
    guard let resumptions else {
      return
    }
    withExtendedLifetime(resumptions.retiredSubscriptions) {
      for continuation in resumptions.next {
        continuation.resume(throwing: failure)
      }
      for continuation in resumptions.acknowledgements {
        continuation.resume(throwing: failure)
      }
    }
  }

  // MARK: Private

  private let epoch: _ObservationEpoch
  private let lock: OSAllocatedUnfairLock<_CoreState<Value>>

  private func cancelAcknowledgementWaiter(
    waiterID: UUID,
    for id: UUID,
  ) {
    let continuation = lock.withLock {
      state -> CheckedContinuation<Void, any Error>? in
      guard
        var subscription = state.subscriptions[id],
        let waiter = subscription.acknowledgementWaiters.removeValue(
          forKey: waiterID
        )
      else {
        return nil
      }
      state.subscriptions[id] = subscription
      return waiter.continuation
    }
    continuation?.resume(throwing: CancellationError())
  }

  private func validate(
    _ checkpoint: _ObservationCheckpoint<Value>,
    for id: UUID,
  ) -> Bool {
    checkpoint.subscriptionID == id
      && checkpoint.envelope.sourceID == sourceID
      && checkpoint.envelope.epoch == epoch
  }

  private func takeEligibleEnvelope(
    from subscription: inout _SubscriptionState<Value>,
    current: _ObservationEnvelope<Value>,
  ) -> _ObservationEnvelope<Value>? {
    let candidate = subscription.pauseEnvelope ?? current
    guard candidate.revision > subscription.lastIssuedRevision else {
      return nil
    }
    subscription.lastIssuedRevision = candidate.revision
    return candidate
  }

  private func takeWaitingDelivery(
    from subscription: inout _SubscriptionState<Value>,
    current: _ObservationEnvelope<Value>,
  ) -> _NextResumption<Value>? {
    guard
      let continuation = subscription.nextWaiter,
      let envelope = takeEligibleEnvelope(
        from: &subscription,
        current: current,
      )
    else {
      return nil
    }
    subscription.nextWaiter = nil
    return _NextResumption(
      continuation: continuation,
      envelope: envelope,
    )
  }

  private func deliverLatestWherePossible(
    in state: inout _CoreState<Value>
  ) -> [_NextResumption<Value>] {
    var resumptions = [_NextResumption<Value>]()
    for id in state.subscriptions.keys {
      guard var subscription = state.subscriptions[id] else {
        continue
      }
      if
        let resumption = takeWaitingDelivery(
          from: &subscription,
          current: state.current,
        )
      {
        resumptions.append(resumption)
      }
      state.subscriptions[id] = subscription
    }
    return resumptions
  }

  private func resume(_ resumptions: [_NextResumption<Value>]) {
    for resumption in resumptions {
      resumption.continuation.resume(returning: resumption.envelope)
    }
  }
}
