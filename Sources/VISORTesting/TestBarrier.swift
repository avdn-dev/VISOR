// MARK: - TestBarrier

/// A one-shot rendezvous that releases every participant after the expected arrivals.
public actor TestBarrier {

  // MARK: Lifecycle

  public init(participantCount: Int) {
    precondition(participantCount > 0)
    self.participantCount = participantCount
  }

  // MARK: Public

  public private(set) var arrivalCount = 0
  public private(set) var isOpen = false

  /// Records an arrival and waits for every expected participant.
  ///
  /// Cancellation before arrival leaves the barrier unchanged. Cancellation
  /// after arrival removes only that participant's wait; its arrival remains
  /// counted so the remaining participants can still open the barrier.
  ///
  /// - Throws: `CancellationError` when the waiting task is cancelled before
  ///   the barrier opens.
  public func arriveAndWait() async throws(CancellationError) {
    guard !Task.isCancelled else { throw CancellationError() }
    guard !isOpen else { return }

    arrivalCount += 1
    resumeArrivalWaiters()
    if arrivalCount == participantCount {
      isOpen = true
      let continuations = participantWaiters.map(\.continuation)
      participantWaiters.removeAll()
      for continuation in continuations {
        continuation.resume(returning: .success(()))
      }
      return
    }

    let waiterID = makeWaiterID()
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: WaitContinuation) in
        guard !Task.isCancelled else {
          continuation.resume(returning: .failure(CancellationError()))
          return
        }
        participantWaiters.append(ParticipantWaiter(
          id: waiterID,
          continuation: continuation,
        ))
      }
    } onCancel: {
      Task {
        await self.cancelParticipantWaiter(waiterID)
      }
    }
    return try result.get()
  }

  /// Waits until the requested number of participants has arrived.
  ///
  /// - Throws: `CancellationError` when the waiting task is cancelled before
  ///   the requested arrival count is reached.
  public func waitUntilArrived(
    _ expectedCount: Int
  ) async throws(CancellationError) {
    precondition(expectedCount > 0 && expectedCount <= participantCount)
    guard !Task.isCancelled else { throw CancellationError() }
    guard arrivalCount < expectedCount else { return }

    let waiterID = makeWaiterID()
    let result = await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: WaitContinuation) in
        guard !Task.isCancelled else {
          continuation.resume(returning: .failure(CancellationError()))
          return
        }
        arrivalWaiters.append(ArrivalWaiter(
          id: waiterID,
          expectedCount: expectedCount,
          continuation: continuation,
        ))
      }
    } onCancel: {
      Task {
        await self.cancelArrivalWaiter(waiterID)
      }
    }
    return try result.get()
  }

  // MARK: Private

  private typealias WaitContinuation = CheckedContinuation<WaitResult, Never>
  private typealias WaitResult = Result<Void, CancellationError>

  private struct ParticipantWaiter {
    let id: Int
    let continuation: WaitContinuation
  }

  private struct ArrivalWaiter {
    let id: Int
    let expectedCount: Int
    let continuation: WaitContinuation
  }

  private let participantCount: Int
  private var nextWaiterID = 1
  private var participantWaiters = [ParticipantWaiter]()
  private var arrivalWaiters = [ArrivalWaiter]()

  private func makeWaiterID() -> Int {
    defer { nextWaiterID += 1 }
    return nextWaiterID
  }

  private func cancelParticipantWaiter(_ waiterID: Int) {
    guard let index = participantWaiters.firstIndex(where: { $0.id == waiterID }) else {
      return
    }
    participantWaiters.remove(at: index).continuation.resume(
      returning: .failure(CancellationError())
    )
  }

  private func cancelArrivalWaiter(_ waiterID: Int) {
    guard let index = arrivalWaiters.firstIndex(where: { $0.id == waiterID }) else {
      return
    }
    arrivalWaiters.remove(at: index).continuation.resume(
      returning: .failure(CancellationError())
    )
  }

  private func resumeArrivalWaiters() {
    let readyWaiters = arrivalWaiters.filter { arrivalCount >= $0.expectedCount }
    arrivalWaiters.removeAll { arrivalCount >= $0.expectedCount }
    for waiter in readyWaiters {
      waiter.continuation.resume(returning: .success(()))
    }
  }
}
