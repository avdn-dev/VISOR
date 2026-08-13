import ConsumerModelsNonisolated
import ConsumerServices
import Testing
import VISORTesting

private enum SourceFencedLifecycleError: Error {
  case action
  case body
}

private final class WeakReference<Value: AnyObject> {
  weak var value: Value?

  init(_ value: Value?) {
    self.value = value
  }
}

@MainActor
private final class SourceFencedActionGate {
  private var hasStarted = false
  private var hasOpened = false
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    hasStarted = true
    let started = startedWaiters
    startedWaiters.removeAll()
    for waiter in started {
      waiter.resume()
    }

    guard !hasOpened else { return }
    await withCheckedContinuation { continuation in
      openWaiters.append(continuation)
    }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { continuation in
      startedWaiters.append(continuation)
    }
  }

  func open() {
    hasOpened = true
    let waiters = openWaiters
    openWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }
}

@Suite("Source-fenced observation lifecycle")
struct SourceFencedLifecycleTests {
  @Test
  @MainActor
  func `Startup failure records once and never enters the body`() async throws {
    let service = SyncingService()
    service.terminateObservationForProof()
    let sut = SourceBackedViewModel(service: service)
    var enteredBody = false

    try await withKnownIssue(
      "startup failure is reported at observe",
      {
        try await observe(sut) { _ in
          enteredBody = true
        }
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue.hasPrefix(
            "VISOR failed while starting observation:")
        }
      })

    #expect(!enteredBody)
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Runtime source failure invalidates the window and suppresses later work`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    var laterOperationRan = false

    try await withKnownIssue(
      "runtime source failure is reported once",
      {
        try await observe(sut) { test in
          await test.perform {
            service.terminateObservationForProof()
          }

          test.expect(\.revision, hasExactChanges: [])
          await test.perform {
            laterOperationRan = true
          }
        }
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue.hasPrefix("VISOR failed while ")
        }
      })

    #expect(!laterOperationRan)
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Cancellation abandons the window and joins the source session`() async {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    let gate = SourceFencedActionGate()

    let task = Task { @MainActor in
      try await observe(sut) { test in
        await test.perform {
          await gate.suspend()
        }
        test.expect(\.revision, hasExactChanges: [])
      }
    }

    await gate.waitUntilStarted()
    task.cancel()
    gate.open()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    #expect(service.activeObservationCountForProof == 0)
  }

  @Test
  @MainActor
  func `Concurrent perform is rejected without corrupting the active window`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    let gate = SourceFencedActionGate()
    var rejectedOperationRan = false

    try await observe(sut) { test in
      let first = Task { @MainActor in
        await test.perform {
          await gate.suspend()
          await service.synchronise()
        }
      }

      await gate.waitUntilStarted()
      await withKnownIssue(
        "overlapping perform is diagnosed",
        {
          await test.perform {
            rejectedOperationRan = true
          }
        },
        matching: { issue in
          issue.comments.contains { comment in
            comment.rawValue == "A perform window is already active for this State"
          }
        })

      gate.open()
      await first.value
      test.expect(\.revision, hasExactChanges: [1])
    }

    #expect(!rejectedOperationRan)
  }

  @Test
  @MainActor
  func `Escaped handle releases its graph and diagnoses stale use`() async throws {
    let service = SyncingService()
    var sut: SourceBackedViewModel? = SourceBackedViewModel(service: service)
    let weakSUT = WeakReference(sut)
    var escaped: ObservationTest<SourceBackedViewModel>?

    try await observe(sut!) { test in
      escaped = test
    }

    sut = nil
    #expect(weakSUT.value == nil)
    #expect(service.activeObservationCountForProof == 0)

    await withKnownIssue(
      "stale handle is diagnosed without retained capture storage",
      {
        await escaped?.perform {}
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue == "This observation scope has ended"
        }
      })
  }

  @Test
  @MainActor
  func `Action error remains primary when its closing fence fails`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    var laterOperationRan = false

    try await withKnownIssue(
      "closing infrastructure failure is reported once beside the action error",
      {
        try await observe(sut) { test in
          await #expect(throws: SourceFencedLifecycleError.action) {
            try await test.perform {
              service.terminateObservationForProof()
              throw SourceFencedLifecycleError.action
            }
          }

          test.expect(\.revision, hasExactChanges: [])
          await test.perform { laterOperationRan = true }
        }
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue.hasPrefix(
            "VISOR failed while closing an action window:")
        }
      })

    #expect(!laterOperationRan)
  }

  @Test
  @MainActor
  func `Body error remains primary beside teardown infrastructure failure`() async {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)

    await withKnownIssue(
      "teardown infrastructure failure is reported beside the body error",
      {
        await #expect(throws: SourceFencedLifecycleError.body) {
          try await observe(sut) { test in
            service.terminateObservationForProof()
            try await test._waitForSessionFailureForProof()
            throw SourceFencedLifecycleError.body
          }
        }
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue.hasPrefix(
            "VISOR failed while running the observation session:")
        }
      })
  }

  @Test
  @MainActor
  func `Produced result survives when its closing fence fails`() async throws {
    let service = SyncingService()
    let sut = SourceBackedViewModel(service: service)
    var returnedResult = false

    try await withKnownIssue(
      "failed closing fence is reported once",
      {
        try await observe(sut) { test in
          do {
            _ = try await test.perform {
              service.terminateObservationForProof()
              return 42
            }
            returnedResult = true
          } catch {}
        }
      },
      matching: { issue in
        issue.comments.contains { comment in
          comment.rawValue.hasPrefix(
            "VISOR failed while closing an action window:")
        }
      })

    #expect(returnedResult)
  }
}
