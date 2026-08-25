import os
import Testing
import VISORObservation

// MARK: - ReentrantSnapshot

private final class ReentrantSnapshot: Sendable {

  // MARK: Lifecycle

  init(onDeinitialise: @escaping @Sendable () -> Void = { }) {
    self.onDeinitialise = onDeinitialise
  }

  deinit {
    onDeinitialise()
  }

  // MARK: Private

  private let onDeinitialise: @Sendable () -> Void

}

// MARK: - ReentrantSnapshotTarget

private final class ReentrantSnapshotTarget: Sendable {

  // MARK: Internal

  var reentryCount: Int {
    lock.withLock { $0.reentryCount }
  }

  func install(_ channel: ObservationChannel<ReentrantSnapshot>) {
    lock.withLock { state in
      state.channel = channel
    }
  }

  func publishFromDeinitialiser() {
    let channel = lock.withLock { state in
      state.reentryCount += 1
      return state.channel
    }
    channel?.publish(ReentrantSnapshot())
  }

  // MARK: Private

  private struct State {
    weak var channel: ObservationChannel<ReentrantSnapshot>?
    var reentryCount = 0
  }

  private let lock = OSAllocatedUnfairLock(initialState: State())

}

// MARK: - ObservationRetirementTests

@Suite
struct ObservationRetirementTests {
  @Test
  func `Publishing retires the replaced snapshot after unlocking`() {
    let target = ReentrantSnapshotTarget()
    let channel = ObservationChannel(ReentrantSnapshot())
    target.install(channel)

    channel.publish(
      ReentrantSnapshot {
        target.publishFromDeinitialiser()
      }
    )
    channel.publish(ReentrantSnapshot())

    #expect(target.reentryCount == 1)
  }

  @Test
  func `Rejected publication retires the incoming snapshot after unlocking`() {
    let target = ReentrantSnapshotTarget()
    let channel = ObservationChannel(ReentrantSnapshot())
    target.install(channel)
    channel._visorTerminate()

    channel.publish(
      ReentrantSnapshot {
        target.publishFromDeinitialiser()
      }
    )

    #expect(target.reentryCount == 1)
  }

  @Test
  func `Termination retires paused snapshots after unlocking`() throws {
    let target = ReentrantSnapshotTarget()
    let channel = ObservationChannel(ReentrantSnapshot())
    target.install(channel)
    let opened = try channel.source._visorOpen()
    try opened.subscription._visorAcknowledge(opened.baseline)

    channel.publish(
      ReentrantSnapshot {
        target.publishFromDeinitialiser()
      }
    )
    var checkpoint: _ObservationCheckpoint<ReentrantSnapshot>? =
      try opened.subscription._visorCheckpointAndPause()
    channel.publish(ReentrantSnapshot())

    #expect(checkpoint != nil)
    #expect(target.reentryCount == 0)
    checkpoint = nil
    #expect(target.reentryCount == 0)

    channel._visorTerminate()

    #expect(target.reentryCount == 1)
  }

  @Test
  func `Cancellation retires removed subscription snapshots after unlocking`() throws {
    let target = ReentrantSnapshotTarget()
    let channel = ObservationChannel(ReentrantSnapshot())
    target.install(channel)
    let opened = try channel.source._visorOpen()
    try opened.subscription._visorAcknowledge(opened.baseline)

    channel.publish(
      ReentrantSnapshot {
        target.publishFromDeinitialiser()
      }
    )
    var checkpoint: _ObservationCheckpoint<ReentrantSnapshot>? =
      try opened.subscription._visorCheckpointAndPause()
    channel.publish(ReentrantSnapshot())

    #expect(checkpoint != nil)
    checkpoint = nil
    #expect(target.reentryCount == 0)

    opened.subscription._visorCancel()

    #expect(target.reentryCount == 1)
    #expect(channel.source._visorActiveSubscriptionCount == 0)
  }
}
