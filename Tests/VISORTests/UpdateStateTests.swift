import VISOR
import Observation
import Testing

// MARK: - Test Types

/// Simulates a service dependency that the ViewModel observes.
@Observable
@MainActor
private final class CounterSource {
    var count = 0
}

/// Simulates a boolean flag dependency.
@Observable
@MainActor
private final class FlagSource {
    var isEnabled = false
}

/// ViewModel with no external dependencies — manages state directly.
@Observable
@MainActor
private final class InternalOnlyViewModel: ViewModel {
    struct State: Equatable {
        var text = ""
        var isReady = false
    }

    var state = State()

    func startObserving() async {}
}

/// ViewModel depending on both CounterSource and FlagSource.
@Observable
@MainActor
private final class MultiSourceViewModel: ViewModel {
    struct State: Equatable {
        var count = 0
        var isEnabled = false
    }

    var state = State()

    private let counterSource: CounterSource
    private let flagSource: FlagSource

    init(counterSource: CounterSource, flagSource: FlagSource) {
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

    private let source: CounterSource

    init(source: CounterSource) {
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

    // MARK: - Initial State

    @Test
    func `initial state has default values`() {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)
        #expect(vm.state.count == 0)
        #expect(vm.state.isLoading == false)
        #expect(vm.state.errorMessage == nil)
    }

    // MARK: - Basic Observation

    @Test(.timeLimit(.minutes(1)))
    func `observes state from service dependency`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            source.count = 5
            await expect(\.state.count, equals: 5)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `loading state via updateState`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            source.count = 3
            await expect(\.state.count, equals: 3)

            vm.load()
            await expect(\.state.isLoading, equals: true)

            vm.finishLoading()
            await expect(\.state.isLoading, equals: false)
            // count is still 3
            #expect(vm.state.count == 3)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `error state via updateState`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            source.count = 10
            await expect(\.state.count, equals: 10)

            vm.setError("fail")
            await expect(\.state.errorMessage, equals: "fail")

            vm.clearError()
            await expect(\.state.errorMessage, equals: nil)
            #expect(vm.state.count == 10)
        }
    }

    // MARK: - Rapid Mutations

    @Test(.timeLimit(.minutes(1)))
    func `rapid mutations settle to correct final state`() async {
        let source = CounterSource()
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
        let source = CounterSource()
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

        for i in 1..<stateEmissions.count {
            #expect(stateEmissions[i] != stateEmissions[i - 1],
                    "Consecutive duplicate at index \(i): \(stateEmissions[i])")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `deduplicates across dependency chain`() async throws {
        let source = CounterSource()
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

    // MARK: - Internal-Only VM

    @Test
    func `internal-only VM manages state without external dependencies`() {
        let vm = InternalOnlyViewModel()

        #expect(vm.state.isReady == false)

        vm.updateState(\.isReady, to: true)
        #expect(vm.state.isReady == true)

        vm.updateState(\.text, to: "hello")
        #expect(vm.state.text == "hello")
    }

    // MARK: - Multiple Service Dependencies

    @Test(.timeLimit(.minutes(1)))
    func `multiple service dependencies feeding state`() async {
        let counter = CounterSource()
        let flag = FlagSource()
        let vm = MultiSourceViewModel(counterSource: counter, flagSource: flag)

        await observing(vm) { expect in
            await expect(\.state.isEnabled, equals: false)

            flag.isEnabled = true
            await expect(\.state.isEnabled, equals: true)

            counter.count = 5
            await expect(\.state.count, equals: 5)
        }
    }

    // MARK: - State Stable After Cancellation

    @Test(.timeLimit(.minutes(1)))
    func `state stable after observation task cancelled`() async throws {
        let source = CounterSource()
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
    func `restart observation after cancellation`() async throws {
        let source = CounterSource()
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

    // MARK: - Empty to Loaded

    @Test(.timeLimit(.minutes(1)))
    func `count goes positive via observation`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            source.count = 1
            await expect(\.state.count, equals: 1)
        }
    }

    // MARK: - Back to Zero

    @Test(.timeLimit(.minutes(1)))
    func `count returns to zero via observation`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            source.count = 5
            await expect(\.state.count, equals: 5)

            source.count = 0
            await expect(\.state.count, equals: 0)
        }
    }
}
