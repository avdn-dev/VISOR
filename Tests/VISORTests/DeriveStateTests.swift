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

/// ViewModel using the computeState() pattern.
/// Manually implements what `@ViewModel` would generate (stored state, deriveState,
/// startObserving) so the runtime behavior can be tested independently of the macro.
@Observable
@MainActor
private final class CounterViewModel: ViewModel {
    private(set) var state: ViewModelState<Int> = .loading

    private var isLoading = false
    private var count = 0
    private var errorMessage: String?

    private let source: CounterSource

    init(source: CounterSource) {
        self.source = source
    }

    func computeState() -> ViewModelState<Int> {
        if isLoading { return .loading }
        if let errorMessage { return .error(errorMessage) }
        if count == 0 { return .empty }
        return .loaded(state: count)
    }

    func deriveState() async {
        for await newState in valuesOf({ self.computeState() }) {
            self.state = newState
        }
    }

    func observeCount() async {
        for await value in valuesOf({ self.source.count }) {
            self.count = value
        }
    }

    func startObserving() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.deriveState() }
            group.addTask { await self.observeCount() }
        }
    }

    func load() {
        isLoading = true
    }

    func finishLoading() {
        isLoading = false
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - State Derivation Tests

@Suite("deriveState()")
@MainActor
struct DeriveStateTests {

    // MARK: - Initial State

    @Test
    func `initial state is loading before observation starts`() {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)
        #expect(vm.state == .loading)
    }

    // MARK: - Basic Derivation

    @Test(.timeLimit(.minutes(1)))
    func `derives state from service dependency`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state, equals: .empty)

            source.count = 5
            await expect(\.state, equals: .loaded(state: 5))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `loading takes priority over loaded`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state, equals: .empty)

            source.count = 3
            await expect(\.state, equals: .loaded(state: 3))

            vm.load()
            await expect(\.state, equals: .loading)

            vm.finishLoading()
            await expect(\.state, equals: .loaded(state: 3))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `error takes priority over loaded`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            source.count = 10
            await expect(\.state, equals: .loaded(state: 10))

            vm.setError("fail")
            await expect(\.state, equals: .error("fail"))

            vm.clearError()
            await expect(\.state, equals: .loaded(state: 10))
        }
    }

    // MARK: - Full Lifecycle

    @Test(.timeLimit(.minutes(1)))
    func `transitions through all four states`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            // loading → empty (count starts at 0, not loading, no error)
            await expect(\.state, equals: .empty)

            // empty → loading
            vm.load()
            await expect(\.state, equals: .loading)

            // loading → loaded
            source.count = 42
            vm.finishLoading()
            await expect(\.state, equals: .loaded(state: 42))

            // loaded → error
            vm.setError("something broke")
            await expect(\.state, equals: .error("something broke"))

            // error → loaded (clear error, count still 42)
            vm.clearError()
            await expect(\.state, equals: .loaded(state: 42))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `rapid mutations settle to correct final state`() async {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        await observing(vm) { expect in
            await expect(\.state, equals: .empty)

            // Rapidly change the source multiple times
            source.count = 1
            source.count = 2
            source.count = 3
            source.count = 100

            // Should settle to the final value
            await expect(\.state, equals: .loaded(state: 100))
        }
    }

    // MARK: - Deduplication

    @Test(.timeLimit(.minutes(1)))
    func `no consecutive duplicate state emissions`() async throws {
        let source = CounterSource()
        let vm = CounterViewModel(source: source)

        var stateEmissions = [ViewModelState<Int>]()
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

        // Toggle loading on/off — intermediate .loading should appear,
        // then .loaded(1) again since it differs from .loading
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

        var stateEmissions = [ViewModelState<Int>]()
        let trackingTask = Task {
            for await state in valuesOf({ vm.state }) {
                stateEmissions.append(state)
                if stateEmissions.count >= 4 { break }
            }
        }

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        source.count = 5
        try await yieldForTracking()

        // Same value — observeCount's valuesOf deduplicates at the source level
        source.count = 5
        try await yieldForTracking()

        source.count = 10
        try await yieldForTracking()

        trackingTask.cancel()
        observeTask.cancel()

        #expect(stateEmissions == [.loading, .empty, .loaded(state: 5), .loaded(state: 10)])
    }
}
