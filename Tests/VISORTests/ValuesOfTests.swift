import VISOR
import Observation
import Testing

@Observable
@MainActor
private final class ObserveSource {
  var count = 0
}

@Observable
@MainActor
private final class BoundViewModel: ViewModel {
  var state: ViewModelState<String> {
    isActive ? .loaded(state: "active") : .loading
  }

  var isActive = false
  var count = 0

  private let source: ObserveSource

  init(source: ObserveSource) {
    self.source = source
  }

  func startObserving() async {
    await observeCount()
  }

  private func observeCount() async {
    for await value in valuesOf({ self.source.count }) {
      self.count = value
      self.isActive = value > 0
    }
  }
}

@Suite("valuesOf() free function")
@MainActor
struct ObserveTests {

  @Test(.timeLimit(.minutes(1)))
  func `emits initial value`() async {
    let source = ObserveSource()
    source.count = 5

    var iterator = valuesOf { source.count }.makeAsyncIterator()
    let first = await iterator.next()
    #expect(first == 5)
  }

  @Test(.timeLimit(.minutes(1)))
  func `re-emits on change`() async throws {
    let source = ObserveSource()

    var iterator = valuesOf { source.count }.makeAsyncIterator()
    let initial = await iterator.next()
    #expect(initial == 0)

    try await yieldForTracking()

    source.count = 10
    let updated = await iterator.next()
    #expect(updated == 10)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Equatable overload deduplicates consecutive equal values`() async throws {
    let source = ObserveSource()

    var received = [Int]()
    let task = Task {
      for await value in valuesOf({ source.count }) {
        received.append(value)
        if received.count >= 3 { break }
      }
    }

    try await yieldForTracking()

    // Set to 1 (different from 0 → emits)
    source.count = 1
    try await yieldForTracking()

    // Set to 1 again (same → should NOT emit)
    source.count = 1
    try await yieldForTracking()

    // Set to 2 (different → emits, third value, loop breaks)
    source.count = 2

    _ = await task.value
    // Should be [0, 1, 2] — the duplicate 1 was skipped
    #expect(received == [0, 1, 2])
  }

  @Test(.timeLimit(.minutes(1)))
  func `stream finishes on task cancellation`() async throws {
    let source = ObserveSource()

    let task = Task {
      var count = 0
      for await _ in valuesOf({ source.count }) {
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
  func `non-Equatable type emits every change`() async throws {
    struct Wrapper: Sendable { let value: Int }
    let source = ObserveSource()

    var received = [Int]()
    let task = Task {
      for await wrapper in valuesOf({ Wrapper(value: source.count) }) {
        received.append(wrapper.value)
        if received.count >= 3 { break }
      }
    }

    try await yieldForTracking()
    source.count = 1
    try await yieldForTracking()
    // Same value — non-Equatable overload does NOT deduplicate
    source.count = 1
    try await yieldForTracking()
    source.count = 2

    _ = await task.value
    #expect(received.count == 3)
  }

  // MARK: - Multiple properties tracked simultaneously

  @Test(.timeLimit(.minutes(1)))
  func `multiple properties tracked simultaneously`() async throws {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    var received = [String]()
    let task = Task {
      for await value in valuesOf({ "\(vm.count)-\(vm.isActive)" }) {
        received.append(value)
        if received.count >= 3 { break }
      }
    }

    let observeTask = Task { await vm.startObserving() }
    try await yieldForTracking()

    source.count = 1
    try await yieldForTracking()

    source.count = 5
    _ = await task.value
    observeTask.cancel()

    #expect(received.count >= 2)
  }

  // MARK: - Mutation before first consumption

  @Test(.timeLimit(.minutes(1)))
  func `mutation before first consumption captures current value`() async {
    let source = ObserveSource()
    source.count = 42

    var iterator = valuesOf { source.count }.makeAsyncIterator()
    let first = await iterator.next()
    #expect(first == 42)
  }

  // MARK: - Computed property depending on two observables

  @Test(.timeLimit(.minutes(1)))
  func `computed property depending on two observables`() async throws {
    let source1 = ObserveSource()
    let source2 = ObserveSource()

    var received = [Int]()
    let task = Task {
      for await value in valuesOf({ source1.count + source2.count }) {
        received.append(value)
        if received.count >= 3 { break }
      }
    }

    try await yieldForTracking()
    source1.count = 10
    try await yieldForTracking()
    source2.count = 5

    _ = await task.value
    #expect(received.contains(0))
    #expect(received.last == 15)
  }

  // MARK: - Two independent streams from same source

  @Test(.timeLimit(.minutes(1)))
  func `two independent streams from same source`() async throws {
    let source = ObserveSource()

    var iter1 = valuesOf { source.count }.makeAsyncIterator()
    var iter2 = valuesOf { source.count }.makeAsyncIterator()

    let v1 = await iter1.next()
    let v2 = await iter2.next()
    #expect(v1 == 0)
    #expect(v2 == 0)

    try await yieldForTracking()

    source.count = 77

    let u1 = await iter1.next()
    let u2 = await iter2.next()
    #expect(u1 == 77)
    #expect(u2 == 77)
  }
}

// MARK: - latestValuesOf Tests

@Suite("latestValuesOf()")
@MainActor
struct ObserveLatestTests {

  @Test(.timeLimit(.minutes(1)))
  func `calls handler with initial value`() async throws {
    let source = ObserveSource()
    source.count = 7

    let task = Task {
      var received = [Int]()
      await latestValuesOf({ source.count }) { value in
        received.append(value)
      }
      return received
    }

    try await yieldForTracking()
    task.cancel()
    let values = await task.value
    #expect(values.first == 7)
  }

  @Test(.timeLimit(.minutes(1)))
  func `cancels previous handler when new value arrives`() async throws {
    let source = ObserveSource()

    // Track which handlers completed vs were cancelled
    var completed = [Int]()
    let task = Task {
      await latestValuesOf({ source.count }) { value in
        // Simulate long-running work — only the latest should complete
        try? await Task.sleep(for: .milliseconds(200))
        if !Task.isCancelled {
          completed.append(value)
        }
      }
    }

    // Wait for initial (0) handler to start
    try await yieldForTracking()

    // Rapidly set 1, 2, 3 — only the last should complete its handler
    source.count = 1
    try await Task.sleep(for: .milliseconds(10))
    source.count = 2
    try await Task.sleep(for: .milliseconds(10))
    source.count = 3

    // Wait long enough for the final handler to complete
    try await Task.sleep(for: .milliseconds(400))
    task.cancel()

    // The last completed value should be 3 (intermediate ones were cancelled)
    #expect(completed.last == 3)
  }

  // MARK: - Handler receives latest during concurrent mutations

  @Test(.timeLimit(.minutes(1)))
  func `handler receives latest value during concurrent mutations`() async throws {
    let source = ObserveSource()

    var handlerValues = [Int]()
    let task = Task {
      await latestValuesOf({ source.count }) { value in
        try? await Task.sleep(for: .milliseconds(50))
        if !Task.isCancelled {
          handlerValues.append(value)
        }
      }
    }

    try await yieldForTracking()

    source.count = 1
    try await Task.sleep(for: .milliseconds(10))
    source.count = 2
    try await Task.sleep(for: .milliseconds(10))
    source.count = 3

    try await Task.sleep(for: .milliseconds(300))
    task.cancel()

    #expect(handlerValues.last == 3)
  }

  // MARK: - Finishes when outer task is cancelled

  @Test(.timeLimit(.minutes(1)))
  func `finishes when outer task is cancelled`() async throws {
    let source = ObserveSource()

    var handlerCallCount = 0
    let task = Task {
      await latestValuesOf({ source.count }) { _ in
        handlerCallCount += 1
      }
    }

    try await yieldForTracking()
    task.cancel()
    _ = await task.value

    let countAfterCancel = handlerCallCount
    try await Task.sleep(for: .milliseconds(100))
    #expect(handlerCallCount == countAfterCancel)
  }

  // MARK: - Synchronous handler receives all values in order

  @Test(.timeLimit(.minutes(1)))
  func `synchronous handler receives all values in order`() async throws {
    let source = ObserveSource()

    var received = [Int]()
    let task = Task {
      await latestValuesOf({ source.count }) { value in
        received.append(value)
      }
    }

    try await yieldForTracking()

    source.count = 1
    try await yieldForTracking()

    source.count = 2
    try await yieldForTracking()

    source.count = 3
    try await yieldForTracking()

    task.cancel()
    _ = await task.value

    #expect(received.first == 0)
    #expect(received.contains(3))
  }
}

// MARK: - Expectation DSL Tests

@Suite("observing() + Expectation DSL")
@MainActor
struct ExpectationDSLTests {

  @Test(.timeLimit(.minutes(1)))
  func `equals waits for matching value`() async {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    await observing(vm) { expect in
      source.count = 42
      await expect(\.count, equals: 42)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func `isNot waits until value differs`() async {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    await observing(vm) { expect in
      await expect(\.isActive, equals: false)

      source.count = 1
      await expect(\.isActive, isNot: false)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func `satisfies waits for predicate`() async {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    await observing(vm) { expect in
      source.count = 5
      await expect(\.state, satisfies: {
        if case .loaded = $0 { true } else { false }
      })
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func `observation is cancelled when body returns`() async throws {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    await observing(vm) { expect in
      source.count = 1
      await expect(\.count, equals: 1)
    }

    // After observing returns, further changes should NOT propagate
    let countBefore = vm.count
    source.count = 999
    try await Task.sleep(for: .milliseconds(100))
    #expect(vm.count == countBefore)
  }

  // MARK: - equals returns immediately when already correct

  @Test(.timeLimit(.minutes(1)))
  func `equals returns immediately when value already correct`() async {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)
    // count starts at 0

    await observing(vm) { expect in
      await expect(\.count, equals: 0)
    }
  }

  // MARK: - satisfies with multi-condition predicate

  @Test(.timeLimit(.minutes(1)))
  func `satisfies with multi-condition predicate`() async {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    await observing(vm) { expect in
      source.count = 5
      await expect(\.state, satisfies: {
        if case .loaded(let s) = $0 { return s == "active" }
        return false
      })
    }
  }

  // MARK: - isNot returns immediately when already different

  @Test(.timeLimit(.minutes(1)))
  func `isNot returns immediately when initial value already differs`() async {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)
    // isActive starts as false

    await observing(vm) { expect in
      await expect(\.isActive, isNot: true)
    }
  }

  // MARK: - Multiple expect calls in sequence

  @Test(.timeLimit(.minutes(1)))
  func `multiple expect calls in sequence`() async {
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    await observing(vm) { expect in
      await expect(\.count, equals: 0)

      source.count = 1
      await expect(\.count, equals: 1)

      source.count = 10
      await expect(\.count, equals: 10)
    }
  }

  // MARK: - Observation cancelled even if body throws

  @Test(.timeLimit(.minutes(1)))
  func `observation cancelled even if body throws`() async throws {
    struct TestError: Error {}
    let source = ObserveSource()
    let vm = BoundViewModel(source: source)

    do {
      try await observing(vm) { expect in
        source.count = 1
        await expect(\.count, equals: 1)
        throw TestError()
      }
    } catch {
      // Expected
    }

    // After throwing, further changes should NOT propagate
    let countBefore = vm.count
    source.count = 999
    try await Task.sleep(for: .milliseconds(100))
    #expect(vm.count == countBefore)
  }
}
