//
//  ObservationSequenceTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import VISOR
import Testing

// MARK: - ObservationSequence tests
// Only tests behavior unique to ObservationSequence that is NOT exercised through valuesOf().

@Suite("ObserveChanges – ObservationSequence (pre-iOS 26 path)")
@MainActor
struct ObservationSequenceTests {

  @Test(.timeLimit(.minutes(1)))
  func `Observable not retained after task cancellation`() async throws {
    var service: TestSource? = TestSource()
    weak let weakService = service

    let stream = ObservationSequence { [service] in service!.count }.stream
    service = nil

    let task = Task {
      for await _ in stream {}
    }

    try await yieldForTracking()
    task.cancel()
    _ = await task.value

    try await Task.sleep(for: .milliseconds(300))

    #expect(weakService == nil, "Observable should be released after task cancellation")
  }

  @Test(.timeLimit(.minutes(1)))
  func `Multiple rapid mutations yield latest values`() async throws {
    let service = TestSource()
    var iterator = ObservationSequence { service.count }.stream.makeAsyncIterator()

    _ = await iterator.next() // initial 0

    try await yieldForTracking()

    service.count = 10
    service.count = 20
    service.count = 30

    let next = await iterator.next()
    #expect(next != nil, "Should emit after rapid mutations")
    #expect(next == 30, "Should yield the latest value after rapid mutations")
  }

  @Test(.timeLimit(.minutes(1)))
  func `Consumer breaking out of loop allows cleanup`() async throws {
    let service = TestSource()
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
    #expect(values.count == 2, "Expected initial value + one mutation, got \(values)")
  }

  @Test(.timeLimit(.minutes(1)))
  func `Untracked property change does not trigger emission`() async throws {
    let service = TestSource()

    var countEmissions = 0
    let task = Task {
      for await _ in ObservationSequence({ service.count }).stream {
        countEmissions += 1
        if countEmissions >= 2 { break }
      }
    }

    try await yieldForTracking()

    // Change a different property — should NOT trigger count stream
    service.name = "changed"
    try await Task.sleep(for: .milliseconds(100))

    // Now change count to trigger the second emission and break
    service.count = 1

    _ = await task.value
    #expect(countEmissions == 2)
  }

  // MARK: - Deduplicating init

  @Test(.timeLimit(.minutes(1)))
  func `Deduplicating init skips re-emission of same initial value`() async throws {
    let service = TestSource()
    var received = [Int]()
    let task = Task {
      for await value in ObservationSequence(deduplicating: { service.count }).stream {
        received.append(value)
        if received.count >= 2 { break }
      }
    }
    try await yieldForTracking()
    // Same as initial (0) — should be skipped
    service.count = 0
    try await yieldForTracking()
    // Different — should be second emission
    service.count = 1
    _ = await task.value
    #expect(received == [0, 1])
  }

  @Test(.timeLimit(.minutes(1)))
  func `Deduplicating init with string type`() async throws {
    let service = TestSource()

    var received = [String]()
    let task = Task {
      for await value in ObservationSequence(deduplicating: { service.name }).stream {
        received.append(value)
        if received.count >= 3 { break }
      }
    }

    try await yieldForTracking()

    service.name = "hello"
    try await yieldForTracking()

    // Same value — should be skipped
    service.name = "hello"
    try await yieldForTracking()

    service.name = "world"
    _ = await task.value
    #expect(received == ["initial", "hello", "world"])
  }
}
