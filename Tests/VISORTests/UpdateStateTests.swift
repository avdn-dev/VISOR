import VISOR
import Testing

// MARK: - Test Types

/// ViewModel depending on two fields from separate TestSource instances.
@Observable
@MainActor
private final class MultiSourceViewModel: ViewModel {
    @Observable
    final class State: @preconcurrency Equatable {
        var count = 0
        var isEnabled = false

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.count == rhs.count && lhs.isEnabled == rhs.isEnabled
        }
    }

    @ObservationIgnored private var _state = State()
    var state: State {
        get { access(keyPath: \.state); return _state }
        set { withMutation(keyPath: \.state) { _state = newValue } }
    }

    func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
        guard _state[keyPath: keyPath] != value else { return }
        _state[keyPath: keyPath] = value
    }

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
    @Observable
    final class State: @preconcurrency Equatable {
        var isLoading = false
        var count = 0
        var errorMessage: String?

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.isLoading == rhs.isLoading && lhs.count == rhs.count && lhs.errorMessage == rhs.errorMessage
        }
    }

    @ObservationIgnored private var _state = State()
    var state: State {
        get { access(keyPath: \.state); return _state }
        set { withMutation(keyPath: \.state) { _state = newValue } }
    }

    func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
        guard _state[keyPath: keyPath] != value else { return }
        _state[keyPath: keyPath] = value
    }

    func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
        _state[keyPath: keyPath] = value
    }

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

        source.count = 1
        try await yieldForTracking()

        // Toggle loading on/off
        vm.updateState(\.isLoading, to: true)
        try await yieldForTracking()
        vm.updateState(\.isLoading, to: false)
        try await yieldForTracking()

        trackingTask.cancel()
        observeTask.cancel()

        // count field should only emit when count changes (0 → 1), not when isLoading changes
        #expect(countEmissions.count >= 2, "Expected at least 2 emissions but got \(countEmissions.count)")
        for i in 1..<countEmissions.count {
            #expect(countEmissions[i] != countEmissions[i - 1],
                    "Consecutive duplicate at index \(i): \(countEmissions[i])")
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

    @Test
    func `Optional field round-trip through nil`() {
        let source = TestSource()
        let vm = CounterViewModel(source: source)

        #expect(vm.state.errorMessage == nil)

        vm.updateState(\.errorMessage, to: "something broke")
        #expect(vm.state.errorMessage == "something broke")

        vm.updateState(\.errorMessage, to: nil)
        #expect(vm.state.errorMessage == nil)

        vm.updateState(\.errorMessage, to: "again")
        #expect(vm.state.errorMessage == "again")
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

        let countAfterCancel = vm.state.count
        source.count = 999
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.state.count == countAfterCancel)
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

    @Test(.timeLimit(.minutes(1)))
    func `Non-Equatable field always writes via updateState`() async throws {
        let vm = NonEquatableVM()

        // Track wrapper field emissions (not .value, since wrapper is non-Observable struct)
        var wrapperValues = [Int]()
        let trackingTask = Task {
            for await wrapper in valuesOf({ vm.state.wrapper }) {
                wrapperValues.append(wrapper.value)
                if wrapperValues.count >= 4 { break }
            }
        }
        try await yieldForTracking()

        // Non-Equatable: both writes should trigger emissions even with same value
        vm.updateState(\.wrapper, to: NonEquatableWrapper(value: 1))
        try await yieldForTracking()
        vm.updateState(\.wrapper, to: NonEquatableWrapper(value: 1))
        try await yieldForTracking()

        trackingTask.cancel()
        _ = await trackingTask.value

        // Initial(0) + two writes(1, 1) = at least 3 emissions
        // (valuesOf can't deduplicate because NonEquatableWrapper is not Equatable)
        #expect(wrapperValues.count >= 3,
                "Expected at least 3 wrapper emissions, got \(wrapperValues.count)")
    }
}
