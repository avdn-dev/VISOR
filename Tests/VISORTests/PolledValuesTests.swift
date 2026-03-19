//
//  PolledValuesTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/3/2026.
//

import Foundation
import Testing
import VISOR

@Suite("polledValuesOf")
@MainActor
struct PolledValuesTests {

  @Test(.timeLimit(.minutes(1)))
  func `Emits immediately on start`() async {
    let value = 42
    var emissions: [Int] = []

    let task = Task {
      for await v in polledValuesOf({ value }, every: .seconds(60)) {
        emissions.append(v)
        if emissions.count >= 1 { break }
      }
    }

    _ = await task.value
    #expect(emissions == [42])
  }

  @Test(.timeLimit(.minutes(1)))
  func `Emits periodically`() async throws {
    var counter = 0
    var emissions: [Int] = []

    let task = Task {
      for await v in polledValuesOf({ counter }, every: .milliseconds(50)) {
        emissions.append(v)
        if emissions.count >= 3 { break }
      }
    }

    // Bump counter between polls
    try await Task.sleep(for: .milliseconds(30))
    counter = 1
    try await Task.sleep(for: .milliseconds(50))
    counter = 2

    _ = await task.value
    // First emission is immediate (0), subsequent are from polling
    #expect(emissions.count == 3)
    #expect(emissions[0] == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Cancellation stops polling`() async throws {
    var emissions: [Int] = []

    let task = Task {
      for await v in polledValuesOf({ 1 }, every: .milliseconds(20)) {
        emissions.append(v)
      }
    }

    try await Task.sleep(for: .milliseconds(80))
    task.cancel()
    try await Task.sleep(for: .milliseconds(50))

    let countAtCancel = emissions.count
    try await Task.sleep(for: .milliseconds(80))
    // No more emissions after cancel
    #expect(emissions.count == countAtCancel)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Non-Equatable overload emits on every poll`() async throws {
    struct Wrapper: Sendable { let value: Int }
    var counter = 10
    var emissions: [Int] = []

    let task = Task {
      for await w in polledValuesOf({ Wrapper(value: counter) }, every: .milliseconds(30)) {
        emissions.append(w.value)
        if emissions.count >= 3 { break }
      }
    }

    // Value stays the same but non-Equatable, so every poll should emit
    _ = await task.value
    #expect(emissions.count == 3)
    #expect(emissions[0] == 10)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Deduplicates consecutive equal values`() async throws {
    var value = 10
    var emissions: [Int] = []

    let task = Task {
      for await v in polledValuesOf({ value }, every: .milliseconds(30)) {
        emissions.append(v)
        if emissions.count >= 3 { break }
      }
    }

    // Keep same value for a couple polls — should NOT emit duplicates
    try await Task.sleep(for: .milliseconds(80))
    // Change value — should emit
    value = 20
    try await Task.sleep(for: .milliseconds(50))
    value = 30

    _ = await task.value
    #expect(emissions == [10, 20, 30])
  }
}
