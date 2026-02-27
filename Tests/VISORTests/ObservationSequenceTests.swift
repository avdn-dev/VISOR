//
//  ObservationSequenceTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import VISOR
import Observation
import Testing

@Observable
@MainActor
final class TestService {
  var count = 0
  var name = "initial"
}

// MARK: - ObservationSequence tests (directly exercises the pre-iOS 26 path)
// Uses .stream property for iteration (the actual production path) to avoid
// sending diagnostics from ObservationSequence.makeAsyncIterator() crossing
// actor isolation boundaries.

@Suite("ObserveChanges – ObservationSequence (pre-iOS 26 path)")
@MainActor
struct ObservationSequenceTests {

  @Test(.timeLimit(.minutes(1)))
  func `emits initial value`() async {
    let service = TestService()
    service.count = 99

    var iterator = ObservationSequence { service.count }.stream.makeAsyncIterator()
    let first = await iterator.next()
    #expect(first == 99)
  }

  @Test(.timeLimit(.minutes(1)))
  func `detects property change`() async throws {
    let service = TestService()

    var iterator = ObservationSequence { service.count }.stream.makeAsyncIterator()

    let initial = await iterator.next()
    #expect(initial == 0)

    try await yieldForTracking()

    service.count = 42
    let updated = await iterator.next()
    #expect(updated == 42)
  }

  @Test(.timeLimit(.minutes(1)))
  func `stops on task cancellation`() async throws {
    let service = TestService()
    let stream = ObservationSequence { service.count }.stream

    let task = Task {
      var count = 0
      for await _ in stream {
        count += 1
      }
      return count
    }

    try await yieldForTracking()
    task.cancel()
    let emitted = await task.value
    #expect(emitted >= 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func `observable not retained after task cancellation`() async throws {
    var service: TestService? = TestService()
    weak let weakService = service

    // Create the stream eagerly, then release our reference.
    // Only the stream's inner task should hold the service.
    let stream = ObservationSequence { [service] in service!.count }.stream
    service = nil

    // Consume in a task, then cancel it — the production pattern (SwiftUI .task).
    // Cancellation triggers onTermination → inner task cancelled → captures released.
    let task = Task {
      for await _ in stream {}
    }

    try await yieldForTracking()
    task.cancel()
    _ = await task.value

    // Give the inner task time to terminate and release captures
    try await Task.sleep(for: .milliseconds(300))

    #expect(weakService == nil, "Observable should be released after task cancellation")
  }

  @Test(.timeLimit(.minutes(1)))
  func `multiple rapid mutations yield latest values`() async throws {
    let service = TestService()
    var iterator = ObservationSequence { service.count }.stream.makeAsyncIterator()

    _ = await iterator.next() // initial 0

    try await yieldForTracking()

    service.count = 10
    service.count = 20
    service.count = 30

    let next = await iterator.next()
    // withObservationTracking fires on will-set, re-read after resume gets latest
    #expect(next == 10 || next == 20 || next == 30)
  }

  @Test(.timeLimit(.minutes(1)))
  func `consumer breaking out of loop allows cleanup`() async throws {
    let service = TestService()
    let stream = ObservationSequence { service.count }.stream

    let task = Task {
      var values = [Int]()
      for await value in stream {
        values.append(value)
        if values.count >= 2 { break }
      }
      return values
    }

    try await yieldForTracking()
    service.count = 7

    let values = await task.value
    #expect(values.count >= 1)
    #expect(values.count <= 2)
  }

  @Test(.timeLimit(.minutes(1)))
  func `deduplicating init skips consecutive equal values`() async throws {
    let service = TestService()

    var received = [Int]()
    let task = Task {
      for await value in ObservationSequence(deduplicating: { service.count }).stream {
        received.append(value)
        if received.count >= 3 { break }
      }
    }

    try await yieldForTracking()

    // Set to 1 (different from 0 → emits)
    service.count = 1
    try await yieldForTracking()

    // Set to 1 again (same → should NOT emit)
    service.count = 1
    try await yieldForTracking()

    // Set to 2 (different → emits, third value, loop breaks)
    service.count = 2

    _ = await task.value
    #expect(received == [0, 1, 2])
  }

  @Test(.timeLimit(.minutes(1)))
  func `multiple concurrent sequences on same observable`() async throws {
    let service = TestService()

    var iter1 = ObservationSequence { service.count }.stream.makeAsyncIterator()
    var iter2 = ObservationSequence { service.count }.stream.makeAsyncIterator()

    let v1 = await iter1.next()
    let v2 = await iter2.next()
    #expect(v1 == 0)
    #expect(v2 == 0)

    try await yieldForTracking()

    service.count = 55

    let u1 = await iter1.next()
    let u2 = await iter2.next()
    #expect(u1 == 55)
    #expect(u2 == 55)
  }
}
