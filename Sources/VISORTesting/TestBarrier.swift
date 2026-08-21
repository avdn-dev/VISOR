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

  public func arriveAndWait() async {
    guard !isOpen else { return }

    arrivalCount += 1
    resumeArrivalWaiters()
    await withCheckedContinuation { continuation in
      participantWaiters.append(continuation)
      guard arrivalCount == participantCount else { return }

      isOpen = true
      let participantWaiters = participantWaiters
      self.participantWaiters.removeAll()
      for participantWaiter in participantWaiters {
        participantWaiter.resume()
      }
    }
  }

  public func waitUntilArrived(_ expectedCount: Int) async {
    precondition(expectedCount > 0 && expectedCount <= participantCount)
    guard arrivalCount < expectedCount else { return }
    await withCheckedContinuation {
      arrivalWaiters.append(ArrivalWaiter(
        expectedCount: expectedCount,
        continuation: $0))
    }
  }

  // MARK: Private

  private struct ArrivalWaiter {
    let expectedCount: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private let participantCount: Int
  private var participantWaiters = [CheckedContinuation<Void, Never>]()
  private var arrivalWaiters = [ArrivalWaiter]()

  private func resumeArrivalWaiters() {
    let readyWaiters = arrivalWaiters.filter { arrivalCount >= $0.expectedCount }
    arrivalWaiters.removeAll { arrivalCount >= $0.expectedCount }
    for waiter in readyWaiters {
      waiter.continuation.resume()
    }
  }
}
