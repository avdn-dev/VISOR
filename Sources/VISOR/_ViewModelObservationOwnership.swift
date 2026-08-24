import Foundation
import os

/// Result of attempting to acquire a ViewModel's observation identity lease.
nonisolated package enum _ViewModelObservationOwnershipClaim {
  case claimed
  case duplicateOwner
  case cancelled
}

/// An inert identity token emitted by `@ViewModel`.
///
/// Generated downstream code can construct and carry this token, but only
/// VISOR can use it to claim production observation ownership. This type is
/// public solely because attached macro expansions are checked downstream.
public final class _ViewModelObservationOwnership: Sendable {
  private typealias Waiter = CheckedContinuation<Bool, Never>

  private struct State: Sendable {
    var ownerID: ObjectIdentifier?
    var isReleasing = false
    var waiters: [UUID: Waiter] = [:]
  }

  private enum ImmediateClaim {
    case claimed
    case duplicateOwner
    case wait
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

  /// Creates a fresh ownership identity for one ViewModel instance.
  public init() {}

  /// Claims immediately unless another active owner holds the lease. When the
  /// holder is already releasing, waits for that specific joined hand-off.
  @MainActor
  package func _visorClaim(
    _ candidate: AnyObject,
    _visorDidEnterWait: @MainActor @Sendable () -> Void = {}
  ) async -> _ViewModelObservationOwnershipClaim {
    let candidateID = ObjectIdentifier(candidate)
    while !Task.isCancelled {
      let immediate: ImmediateClaim = lock.withLock { state in
        // Cancellation may arrive after the loop condition but before this
        // critical section. Never create a lease for an already-cancelled root.
        guard !Task.isCancelled else { return .wait }
        guard let ownerID = state.ownerID else {
          state.ownerID = candidateID
          state.isReleasing = false
          return .claimed
        }
        if ownerID == candidateID {
          return state.isReleasing ? .wait : .claimed
        }
        return state.isReleasing ? .wait : .duplicateOwner
      }

      switch immediate {
      case .claimed:
        return .claimed
      case .duplicateOwner:
        return .duplicateOwner
      case .wait:
        guard !Task.isCancelled else { return .cancelled }
        guard await waitForRelease(
          _visorDidEnterWait: _visorDidEnterWait)
        else {
          return .cancelled
        }
      }
    }
    return .cancelled
  }

  /// Makes a cancelled root non-actionable to new claimants without releasing
  /// its lease before its complete observation generation has joined.
  nonisolated package func _visorBeginRelease(
    ownerID: ObjectIdentifier
  ) {
    lock.withLock { state in
      guard state.ownerID == ownerID else { return }
      state.isReleasing = true
    }
  }

  /// Whether this owner still holds an active, non-releasing lease.
  /// Readiness gates consult this so root cancellation becomes fail-closed in
  /// the cancellation handler, before MainActor teardown can resume.
  package func _visorIsActionable(ownerID: ObjectIdentifier) -> Bool {
    lock.withLock { state in
      state.ownerID == ownerID && !state.isReleasing
    }
  }

  package func _visorRelease(ownerID: ObjectIdentifier) {
    let waiters: [Waiter] = lock.withLock { state in
      guard state.ownerID == ownerID else { return [] }
      state.ownerID = nil
      state.isReleasing = false
      let waiters = Array(state.waiters.values)
      state.waiters.removeAll(keepingCapacity: false)
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: true)
    }
  }

  @MainActor
  private func waitForRelease(
    _visorDidEnterWait: @MainActor @Sendable () -> Void
  ) async -> Bool {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let immediate: Bool? = lock.withLock { state in
          guard !Task.isCancelled else { return false }
          guard state.ownerID != nil, state.isReleasing else {
            return true
          }
          state.waiters[id] = continuation
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        } else {
          _visorDidEnterWait()
        }
      }
    } onCancel: {
      let waiter = lock.withLock { state in
        state.waiters.removeValue(forKey: id)
      }
      waiter?.resume(returning: false)
    }
  }
}
