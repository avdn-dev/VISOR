import VISOR
import Observation
import Testing

// MARK: - Test Types

/// ViewModel depending on two fields from separate TestSource instances.
@Observable
@MainActor
private final class MultiSourceViewModel: ViewModel {
    struct State: Equatable {
        var count = 0
        var isEnabled = false
    }

    var state = State()

    private let counterSource: TestSource
    private let flagSource: TestSource

    init(counterSource: TestSource, flagSource: TestSource) {
        self.counterSource = counterSource
        self.flagSource = flagSource
    }

    func startObserving() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.observeCounter() }
            group.addTask { await self.observeFlag() }
        }
    }

    private func observeCounter() async {
        for await value in valuesOf({ self.counterSource.count }) {
            self.updateState(\.count, to: value)
        }
    }

    private func observeFlag() async {
        for await value in valuesOf({ self.flagSource.isEnabled }) {
            self.updateState(\.isEnabled, to: value)
        }
    }
}

/// ViewModel using direct state mutation via updateState.
@Observable
@MainActor
private final class CounterViewModel: ViewModel {
    struct State: Equatable {
        var isLoading = false
        var count = 0
        var errorMessage: String?
    }

    var state = State()

    private let source: TestSource

    init(source: TestSource) {
        self.source = source
    }

    func observeCount() async {
        for await value in valuesOf({ self.source.count }) {
            self.updateState(\.count, to: value)
        }
    }

    func startObserving() async {
        await observeCount()
    }

    func load() {
        updateState(\.isLoading, to: true)
    }

    func finishLoading() {
        updateState(\.isLoading, to: false)
    }

    func setError(_ message: String) {
        updateState(\.errorMessage, to: message)
    }

    func clearError() {
        updateState(\.errorMessage, to: nil)
    }
}

// MARK: - State Tests

@Suite("updateState / direct state mutation")
@MainActor
struct UpdateStateTests {

    // MARK: - Basic Observation

    @Test(.timeLimit(.minutes(1)))
    func `updateState propagates source changes via valuesOf`() async {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            source.count = 5
            await expect(\.state.count, equals: 5)
        }
    }

    // MARK: - Rapid Mutations

    @Test(.timeLimit(.minutes(1)))
    func `Rapid source mutations converge to final value`() async {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            // Rapidly change the source multiple times
            source.count = 1
            source.count = 2
            source.count = 3
            source.count = 100

            // Should settle to the final value
            await expect(\.state.count, equals: 100)
        }
    }

    // MARK: - Deduplication

    @Test(.timeLimit(.minutes(1)))
    func `updateState deduplicates equal values`() async throws {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        var stateEmissions = [CounterViewModel.State]()
        let trackingTask = Task {
            for await state in valuesOf({ vm.state }) {
                stateEmissions.append(state)
                if stateEmissions.count >= 4 { break }
            }
        }

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        source.count = 1
        try await yieldForTracking()

        // Toggle loading on/off
        vm.load()
        try await yieldForTracking()
        vm.finishLoading()
        try await yieldForTracking()

        trackingTask.cancel()
        observeTask.cancel()

        #expect(stateEmissions.count >= 2, "Expected at least 2 emissions but got \(stateEmissions.count)")
        for i in 1..<stateEmissions.count {
            #expect(stateEmissions[i] != stateEmissions[i - 1],
                    "Consecutive duplicate at index \(i): \(stateEmissions[i])")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `Deduplicates across dependency chain`() async throws {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        var countEmissions = [Int]()
        let trackingTask = Task {
            for await count in valuesOf({ vm.state.count }) {
                countEmissions.append(count)
                if countEmissions.count >= 4 { break }
            }
        }

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        source.count = 5
        try await yieldForTracking()

        // Same value — updateState deduplicates
        source.count = 5
        try await yieldForTracking()

        source.count = 10
        try await yieldForTracking()

        trackingTask.cancel()
        observeTask.cancel()

        #expect(countEmissions == [0, 5, 10])
    }

    // MARK: - Multiple Service Dependencies

    @Test(.timeLimit(.minutes(1)))
    func `Multiple service dependencies feeding state`() async {
        let counter = TestSource()
        let flag = TestSource()
        let vm = MultiSourceViewModel(counterSource: counter, flagSource: flag)

        await observing(vm) { expect in
            await expect(\.state.isEnabled, equals: false)

            flag.isEnabled = true
            await expect(\.state.isEnabled, equals: true)

            counter.count = 5
            await expect(\.state.count, equals: 5)
        }
    }

    // MARK: - Optional Field Round-Trip

    @Test(.timeLimit(.minutes(1)))
    func `Optional field round-trip through nil`() async {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state.errorMessage, equals: nil)

            vm.setError("something broke")
            await expect(\.state.errorMessage, equals: "something broke")

            vm.clearError()
            await expect(\.state.errorMessage, equals: nil)

            vm.setError("again")
            await expect(\.state.errorMessage, equals: "again")
        }
    }

    // MARK: - State Stable After Cancellation

    @Test(.timeLimit(.minutes(1)))
    func `State stable after observation task cancelled`() async throws {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        let task = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        source.count = 5
        try await yieldForTracking()

        task.cancel()
        try await Task.sleep(for: .milliseconds(100))

        let stateAfterCancel = vm.state
        source.count = 999
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.state == stateAfterCancel)
    }

    // MARK: - Restart Observation After Cancellation

    @Test(.timeLimit(.minutes(1)))
    func `Restart observation after cancellation`() async throws {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        // First observation
        let task1 = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        source.count = 3
        try await yieldForTracking()

        task1.cancel()
        try await Task.sleep(for: .milliseconds(100))

        // Second observation
        await observing(vm) { expect in
            await expect(\.state.count, equals: 3)

            source.count = 10
            await expect(\.state.count, equals: 10)
        }
    }

    // MARK: - High-Throughput Stress

    @Test(.timeLimit(.minutes(1)))
    func `High-throughput mutations converge to final value`() async {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            for i in 1...500 {
                source.count = i
            }

            await expect(\.state.count, equals: 500)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `Deduplication prevents spurious emissions under load`() async throws {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        var emissions = [Int]()
        let trackingTask = Task {
            for await count in valuesOf({ vm.state.count }) {
                emissions.append(count)
                if count == 100 { break }
            }
        }

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        // Alternate between 50 and 100, with repeated values that must be deduped
        for _ in 1...20 { source.count = 50 }
        try await yieldForTracking()
        for _ in 1...20 { source.count = 100 }

        await trackingTask.value
        observeTask.cancel()

        // Verify no consecutive duplicates in the emission log
        for i in 1..<emissions.count {
            #expect(emissions[i] != emissions[i - 1],
                    "Consecutive duplicate at index \(i): \(emissions[i])")
        }
    }

    // MARK: - Non-Equatable updateState

    @Test
    func `Non-Equatable field always writes via updateState`() {
        let vm = NonEquatableVM()

        vm.updateState(\.wrapper, to: NonEquatableWrapper(value: 1))
        #expect(vm.state.wrapper.value == 1)

        // Same logical value — non-Equatable overload writes unconditionally
        vm.updateState(\.wrapper, to: NonEquatableWrapper(value: 1))
        #expect(vm.state.wrapper.value == 1)

        // Equatable field deduplicates
        vm.updateState(\.label, to: "hello")
        vm.updateState(\.label, to: "hello") // no-op
        #expect(vm.state.label == "hello")
    }
}
