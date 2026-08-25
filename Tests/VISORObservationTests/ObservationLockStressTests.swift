import Testing
import VISORObservation
import VISORTesting

private func isAllowedSequentialCut(
  first: Int,
  second: Int,
  previous: Int,
  current: Int,
) -> Bool {
  (first == previous && second == previous)
    || (first == current && second == previous)
    || (first == current && second == current)
}

private func snapshots(
  from observations: [_AnyPreparedObservation]
) throws -> (first: Int, second: Int) {
  defer {
    for observation in observations {
      observation._visorCancel()
    }
  }

  let first = try observations[0]._visorUnwrap(as: Int.self)
  let second = try observations[1]._visorUnwrap(as: Int.self)
  return (
    first: first.baseline.snapshot,
    second: second.baseline.snapshot,
  )
}

// MARK: - ObservationLockStressTests

@Suite("V11 observation lock contention")
struct ObservationLockStressTests {
  @Test(.timeLimit(.minutes(1)))
  func `Concurrent callers publish every revision without actor serialisation`() async throws {
    let channel = ObservationChannel(0)
    let workerCount = 8
    let publicationsPerWorker = 500
    let barrier = TestBarrier(participantCount: workerCount)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for worker in 0..<workerCount {
        group.addTask {
          try await barrier.arriveAndWait()
          for publication in 0..<publicationsPerWorker {
            channel.publish(
              worker * publicationsPerWorker + publication + 1
            )
          }
        }
      }
      try await group.waitForAll()
    }

    let opened = try channel.source._visorOpen()
    defer { opened.subscription._visorCancel() }
    #expect(
      opened.baseline.revision
        == UInt64(workerCount * publicationsPerWorker)
    )
    #expect(opened.baseline.snapshot != 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func `A chained three-channel group remains live under shared contention`() async throws {
    let first = ObservationChannel(0)
    let second = ObservationChannel(0, coordinatedWith: first)
    let third = ObservationChannel(0, coordinatedWith: second)
    let channels = [first, second, third]
    let workersPerChannel = 4
    let publicationsPerWorker = 250
    let barrier = TestBarrier(
      participantCount: channels.count * workersPerChannel
    )

    #expect(first.source._visorGroupIdentity == second.source._visorGroupIdentity)
    #expect(second.source._visorGroupIdentity == third.source._visorGroupIdentity)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for (channelIndex, channel) in channels.enumerated() {
        for worker in 0..<workersPerChannel {
          group.addTask {
            try await barrier.arriveAndWait()
            for publication in 0..<publicationsPerWorker {
              channel.publish(
                channelIndex * 1_000_000
                  + worker * publicationsPerWorker
                  + publication
                  + 1
              )
            }
          }
        }
      }
      try await group.waitForAll()
    }

    let observations = try _ObservationRuntime._visorPrepareAll(
      channels.map { $0.source._visorErase() }
    )
    defer {
      for observation in observations {
        observation._visorCancel()
      }
    }

    for observation in observations {
      let typed = try observation._visorUnwrap(as: Int.self)
      #expect(
        typed.baseline.revision
          == UInt64(workersPerChannel * publicationsPerWorker)
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func `Racing cancellation with acknowledgement registration leaves the subscription reusable`() async throws {
    let channel = ObservationChannel(0)
    let opened = try channel.source._visorOpen()
    defer { opened.subscription._visorCancel() }
    try opened.subscription._visorAcknowledge(opened.baseline)

    for value in 1...250 {
      channel.publish(value)
      let checkpoint = try opened.subscription._visorCheckpointAndPause()
      let registrationRace = TestBarrier(participantCount: 2)
      let waiter = Task {
        try await registrationRace.arriveAndWait()
        try await opened.subscription
          ._visorWaitUntilAcknowledged(checkpoint)
      }

      try await registrationRace.arriveAndWait()
      waiter.cancel()
      await #expect(throws: CancellationError.self) {
        try await waiter.value
      }

      let envelope = try opened.subscription
        ._visorClaimForDirectReconciliation(checkpoint)
      #expect(envelope.snapshot == value)
      try opened.subscription._visorAcknowledge(envelope)
      try await opened.subscription
        ._visorWaitUntilAcknowledged(checkpoint)
      try opened.subscription._visorResume(after: checkpoint)
    }

    #expect(channel.source._visorActiveSubscriptionCount == 1)
    opened.subscription._visorCancel()
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Grouped preparation linearises with sequential publications`() async throws {
    let first = ObservationChannel(0)
    let second = ObservationChannel(0, coordinatedWith: first)

    for current in 1...250 {
      let barrier = TestBarrier(participantCount: 2)
      let publication = Task {
        try await barrier.arriveAndWait()
        first.publish(current)
        second.publish(current)
      }
      let preparation = Task {
        try await barrier.arriveAndWait()
        return try _ObservationRuntime._visorPrepareAll([
          first.source._visorErase(),
          second.source._visorErase(),
        ])
      }

      let observations = try await preparation.value
      try await publication.value
      let captured = try snapshots(from: observations)
      #expect(
        isAllowedSequentialCut(
          first: captured.first,
          second: captured.second,
          previous: current - 1,
          current: current,
        )
      )
    }

    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(second.source._visorActiveSubscriptionCount == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Grouped checkpoints linearise with sequential publications`() async throws {
    let first = ObservationChannel(0)
    let second = ObservationChannel(0, coordinatedWith: first)
    let prepared = try _ObservationRuntime._visorPrepareAll([
      first.source._visorErase(),
      second.source._visorErase(),
    ])
    let firstOpened = try prepared[0]
      ._visorUnwrap(as: Int.self)
      ._visorActivate()
    let secondOpened = try prepared[1]
      ._visorUnwrap(as: Int.self)
      ._visorActivate()
    defer {
      firstOpened.subscription._visorCancel()
      secondOpened.subscription._visorCancel()
    }
    try firstOpened.subscription._visorAcknowledge(firstOpened.baseline)
    try secondOpened.subscription._visorAcknowledge(secondOpened.baseline)

    let subscriptions = [
      firstOpened.subscription._visorErase(),
      secondOpened.subscription._visorErase(),
    ]
    for current in 1...250 {
      let barrier = TestBarrier(participantCount: 2)
      let publication = Task {
        try await barrier.arriveAndWait()
        first.publish(current)
        second.publish(current)
      }
      let capture = Task {
        try await barrier.arriveAndWait()
        return try _ObservationRuntime
          ._visorCheckpointAndPauseAll(subscriptions)
      }

      let checkpoints = try await capture.value
      try await publication.value
      let firstCheckpoint = try checkpoints[0]._visorUnwrap(as: Int.self)
      let secondCheckpoint = try checkpoints[1]._visorUnwrap(as: Int.self)
      #expect(
        isAllowedSequentialCut(
          first: firstCheckpoint.envelope.snapshot,
          second: secondCheckpoint.envelope.snapshot,
          previous: current - 1,
          current: current,
        )
      )

      let firstEnvelope = try firstOpened.subscription
        ._visorClaimForDirectReconciliation(firstCheckpoint)
      let secondEnvelope = try secondOpened.subscription
        ._visorClaimForDirectReconciliation(secondCheckpoint)
      try firstOpened.subscription._visorAcknowledge(firstEnvelope)
      try secondOpened.subscription._visorAcknowledge(secondEnvelope)
      try await _ObservationRuntime
        ._visorWaitUntilAcknowledgedAll(checkpoints)
      try _ObservationRuntime._visorResumeAll(after: checkpoints)
    }

    #expect(first.source._visorActiveSubscriptionCount == 1)
    #expect(second.source._visorActiveSubscriptionCount == 1)
    firstOpened.subscription._visorCancel()
    secondOpened.subscription._visorCancel()
    #expect(first.source._visorActiveSubscriptionCount == 0)
    #expect(second.source._visorActiveSubscriptionCount == 0)
  }
}
