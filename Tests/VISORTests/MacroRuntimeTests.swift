import Foundation
import VISOR
import Testing

// MARK: - Tests


@Suite("Macro Runtime — @ViewModel")
@MainActor
struct ViewModelMacroRuntimeTests {

    // MARK: - Minimal VMs

    @Test
    func `MinimalVM writes and reads state via updateState`() {
        let vm = MinimalVM()
        #expect(vm.state.value == 0)
        vm.updateState(\.value, to: 42)
        #expect(vm.state.value == 42)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Macro-generated state var tracks observation changes`() async {
        let vm = AutoStateVM()
        #expect(vm.state.value == 0)

        await observing(vm) { expect in
            Task { @MainActor in vm.updateState(\.value, to: 1) }
            await expect(\.state.value, equals: 1)

            Task { @MainActor in vm.updateState(\.value, to: 2) }
            await expect(\.state.value, equals: 2)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `@Reaction on non-@Bound state property fires on mutation`() async {
        let vm = ReactionOnStateVM()
        #expect(vm.state.doubled == 0)

        await observing(vm) { expect in
            Task { @MainActor in
                vm.updateState(\.counter, to: 5)
            }
            await expect(\.state.doubled, equals: 10)
        }
    }

    @Test
    func `ViewModel dispatches sync action without dependencies`() {
        let vm = NoDepsVM()
        vm.handle(.setText("hello"))
        #expect(vm.state.text == "hello")
    }

    // MARK: - Memberwise init generation

    @Test
    func `@ViewModel generates init for all stored-let dependencies`() {
        let source = RuntimeSource()
        let second = SecondSource()
        let vm = MultiDepVM(source: source, second: second)
        #expect(vm.source === source)
        #expect(vm.second === second)
    }

    @Test
    func `@ViewModel skips init generation when user provides one`() {
        let source = RuntimeSource()
        let vm = CustomInitVM(customSource: source)
        #expect(vm.source === source)
    }

    // MARK: - Single @Bound auto-generated observation

    @Test(.timeLimit(.minutes(1)))
    func `Single @Bound generates working startObserving`() async {
        let source = RuntimeSource()
        let vm = AutoObserveSingleVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)
            source.count = 10
            await expect(\.state.count, equals: 10)
        }
    }

    // MARK: - Multiple @Bound with task group observation

    @Test(.timeLimit(.minutes(1)))
    func `Multiple @Bound generates task group startObserving`() async {
        let source = RuntimeSource()
        let vm = AutoObserveMultiVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)
            await expect(\.state.label, equals: "initial")
            await expect(\.state.isEnabled, equals: false)

            source.count = 5
            await expect(\.state.count, equals: 5)

            source.label = "changed"
            await expect(\.state.label, equals: "changed")

            source.isEnabled = true
            await expect(\.state.isEnabled, equals: true)
        }
    }

    // MARK: - @Bound from multiple different dependencies

    @Test(.timeLimit(.minutes(1)))
    func `@Bound from different dependencies observes both`() async {
        let source = RuntimeSource()
        let second = SecondSource()
        let vm = MultiDepVM(source: source, second: second)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)
            await expect(\.state.name, equals: "")

            source.count = 7
            await expect(\.state.count, equals: 7)

            second.name = "hello"
            await expect(\.state.name, equals: "hello")
        }
    }

    // MARK: - @Bound deduplication

    @Test(.timeLimit(.minutes(1)))
    func `@Bound deduplicates via updateState`() async throws {
        let source = RuntimeSource()
        let vm = AutoObserveSingleVM(source: source)

        var emissions = [Int]()
        let trackingTask = Task {
            for await count in valuesOf({ vm.state.count }) {
                emissions.append(count)
                if emissions.count >= 4 { break }
            }
        }

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        source.count = 5
        try await yieldForTracking()

        // Same value — should be deduplicated
        source.count = 5
        try await yieldForTracking()

        source.count = 10
        try await yieldForTracking()

        trackingTask.cancel()
        observeTask.cancel()

        #expect(emissions == [0, 5, 10])
    }

    // MARK: - @Bound + sync Action

    @Test(.timeLimit(.minutes(1)))
    func `@Bound coexists with sync action`() async {
        let source = RuntimeSource()
        let vm = BoundWithSyncActionVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)
            #expect(vm.state.selectedIndex == 0)

            // Action mutation
            vm.handle(.selectIndex(3))
            #expect(vm.state.selectedIndex == 3)

            // @Bound still works
            source.count = 42
            await expect(\.state.count, equals: 42)

            // Both states coexist
            #expect(vm.state.selectedIndex == 3)

            // Reset action
            vm.handle(.reset)
            #expect(vm.state.selectedIndex == 0)
        }
    }

    // MARK: - @Bound + async Action

    @Test(.timeLimit(.minutes(1)))
    func `@Bound coexists with async action and Loadable`() async {
        let source = RuntimeSource()
        let vm = BoundWithAsyncActionVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)
            #expect(vm.state.detail == .loading)

            // Async action
            await vm.handle(.loadDetail)
            #expect(vm.state.detail == .loaded("fetched"))

            // @Bound still works after async action
            source.count = 99
            await expect(\.state.count, equals: 99)

            // Clear
            await vm.handle(.clearDetail)
            #expect(vm.state.detail == .empty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `@Bound updates during async action`() async {
        let source = RuntimeSource()
        let vm = BoundWithAsyncActionVM(source: source)

        await observing(vm) { expect in
            // Start async action
            let actionTask = Task { await vm.handle(.loadDetail) }

            // @Bound update while action is in-flight
            source.count = 50
            await expect(\.state.count, equals: 50)

            await actionTask.value
            #expect(vm.state.detail == .loaded("fetched"))
        }
    }

    // MARK: - @Reaction (sync)

    @Test(.timeLimit(.minutes(1)))
    func `Sync @Reaction fires on every value change`() async {
        let nav = RuntimeSource()
        let vm = SyncReactionVM(nav: nav)

        await observing(vm) { expect in
            // Initial emission fires with nil, so reactionCount starts at 1
            await expect(\.state.reactionCount, satisfies: { $0 >= 1 })
            let baseline = vm.state.reactionCount

            nav.destination = "home"
            await expect(\.state.lastDestination, equals: "home")
            #expect(vm.state.reactionCount == baseline + 1)

            nav.destination = "settings"
            await expect(\.state.lastDestination, equals: "settings")
            #expect(vm.state.reactionCount == baseline + 2)

            nav.destination = nil
            await expect(\.state.lastDestination, equals: nil)
            #expect(vm.state.reactionCount == baseline + 3)
        }
    }

    // MARK: - @Reaction (async)

    @Test(.timeLimit(.minutes(1)))
    func `Async @Reaction processes values sequentially`() async throws {
        let nav = RuntimeSource()
        let vm = AsyncReactionVM(nav: nav)

        await observing(vm) { expect in
            nav.destination = "first"
            await expect(\.state.processedValue, equals: "first")

            nav.destination = "second"
            await expect(\.state.processedValue, equals: "second")

            nav.destination = "final"
            await expect(\.state.processedValue, equals: "final")
        }
    }

    // MARK: - @Bound + @Reaction combined

    @Test(.timeLimit(.minutes(1)))
    func `@Bound and @Reaction both active concurrently`() async {
        let source = RuntimeSource()
        let nav = RuntimeSource()
        let vm = BoundAndReactionVM(source: source, nav: nav)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            // @Bound update
            source.count = 10
            await expect(\.state.count, equals: 10)

            // @Reaction update
            nav.destination = "detail"
            await expect(\.state.lastNav, equals: "detail")

            // Both continue to work
            source.count = 20
            await expect(\.state.count, equals: 20)

            nav.destination = nil
            await expect(\.state.lastNav, equals: nil)
        }
    }

    // MARK: - Action == Never

    @Test(.timeLimit(.minutes(1)))
    func `VM with no Action enum still observes via @Bound`() async {
        let source = RuntimeSource()
        let vm = NoActionVM(source: source)

        await observing(vm) { expect in
            source.count = 77
            await expect(\.state.count, equals: 77)
        }
    }

    // MARK: - @Polled

    @Test(.timeLimit(.minutes(1)))
    func `Single @Polled seeds initial value at init`() {
        let monitor = BatteryMonitor()
        monitor.level = 0.5
        let vm = PolledSingleVM(monitor: monitor)
        #expect(vm.state.level == 0.5)
    }

    @Test(.timeLimit(.minutes(1)))
    func `@Polled updates state after poll interval`() async {
        let monitor = BatteryMonitor()
        monitor.level = 0.5
        let vm = PolledSingleVM(monitor: monitor)

        await observing(vm) { expect in
            monitor.level = 0.8
            await expect(\.state.level, equals: 0.8)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `@Polled catches value changed between init and startObserving`() async throws {
        let monitor = BatteryMonitor()
        monitor.level = 0.5
        let vm = PolledSingleVM(monitor: monitor)
        #expect(vm.state.level == 0.5)

        // Value changes AFTER init but BEFORE startObserving
        monitor.level = 0.9

        await observing(vm) { expect in
            // The initial updateState in the generated observe method should catch this
            await expect(\.state.level, equals: 0.9)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `@Polled stops updating after cancellation`() async throws {
        let monitor = BatteryMonitor()
        monitor.level = 0.5
        let vm = PolledSingleVM(monitor: monitor)

        let task = Task { await vm.startObserving() }
        // Wait for initial updateState + at least one poll cycle
        monitor.level = 0.8
        // Use valuesOf on the state to wait for the update
        for await level in valuesOf({ vm.state.level }) {
            if level == 0.8 { break }
        }

        task.cancel()
        try await yieldForTracking()

        // After cancellation, further changes should NOT propagate
        monitor.level = 1.0
        // Wait longer than the poll interval (50ms)
        try await Task.sleep(for: .milliseconds(150))
        #expect(vm.state.level == 0.8)
    }

    @Test(.timeLimit(.minutes(1)))
    func `@Polled deduplicates equal values via updateState`() async throws {
        let monitor = BatteryMonitor()
        monitor.level = 0.5
        let vm = PolledSingleVM(monitor: monitor)

        var emissions: [Float] = []
        let trackingTask = Task {
            for await level in valuesOf({ vm.state.level }) {
                emissions.append(level)
                if emissions.count >= 3 { break }
            }
        }

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()

        // Value stays 0.5 across multiple polls — no duplicate emissions
        try await Task.sleep(for: .milliseconds(120))
        let countBeforeChange = emissions.count
        #expect(countBeforeChange == 1, "Only initial emission, no duplicates")

        // Two distinct changes to collect remaining 2 emissions
        monitor.level = 0.9
        try await Task.sleep(for: .milliseconds(120))
        monitor.level = 1.0

        _ = await trackingTask.value
        observeTask.cancel()

        #expect(emissions == [0.5, 0.9, 1.0])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Push-based @Bound and pull-based @Polled update independently`() async {
        let source = RuntimeSource()
        let monitor = BatteryMonitor()
        monitor.level = 0.3
        let vm = BoundAndPolledVM(source: source, monitor: monitor)

        // Init seeds both @Bound and @Polled values
        #expect(vm.state.count == 0)
        #expect(vm.state.level == 0.3)
        #expect(vm.state.label == "initial")

        await observing(vm) { expect in
            // @Bound update (push-based — immediate)
            source.count = 10
            await expect(\.state.count, equals: 10)

            // @Polled update (pull-based — next poll cycle)
            monitor.level = 0.9
            await expect(\.state.level, equals: 0.9)

            // @Bound still works after @Polled update
            source.label = "changed"
            await expect(\.state.label, equals: "changed")
        }
    }

    // MARK: - ThrottledBy @Bound

    @Test(.timeLimit(.minutes(1)))
    func `ThrottledBy @Bound drops intermediate rapid-fire values`() async throws {
        let source = RuntimeSource()
        let vm = ThrottledByBoundVM(source: source)

        var emissions: [Int] = []
        let trackingTask = Task {
            for await count in valuesOf({ vm.state.count }) {
                emissions.append(count)
                if emissions.count >= 3 { break }
            }
        }

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()

        // Rapid-fire 5 changes within buffer window (100ms)
        for i in 1...5 {
            source.count = i
        }

        // Wait for buffer to expire + next iteration to process
        try await Task.sleep(for: .milliseconds(200))

        // One more distinct change for the third emission
        source.count = 99

        _ = await trackingTask.value
        observeTask.cancel()

        // First = initial (0), second = latest from burst (5), third = 99
        #expect(emissions.count == 3)
        #expect(emissions[0] == 0)
        #expect(emissions[1] == 5, "Should pick up only the latest from rapid-fire burst")
        #expect(emissions[2] == 99)
    }

    @Test(.timeLimit(.minutes(1)))
    func `ThrottledBy @Bound eventually delivers single change`() async {
        let source = RuntimeSource()
        let vm = ThrottledByBoundVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            source.count = 42
            await expect(\.state.count, equals: 42)
        }
    }

    // MARK: - ThrottledBy @Reaction (sync)

    @Test(.timeLimit(.minutes(1)))
    func `ThrottledBy sync @Reaction throttles rapid-fire changes`() async throws {
        let source = RuntimeSource()
        let vm = ThrottledBySyncReactionVM(source: source)

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()

        let baseline = vm.state.reactionCount

        // Rapid-fire 10 changes within buffer window
        for i in 1...10 {
            source.count = i
        }

        // Wait for buffer(100ms) + processing margin
        try await Task.sleep(for: .milliseconds(400))

        let totalReactions = vm.state.reactionCount - baseline
        #expect(totalReactions >= 1,
                "At least one throttled reaction must fire")
        #expect(totalReactions < 10,
                "ThrottledBy reaction should throttle: fired \(totalReactions) times for 10 changes")
        #expect(vm.state.latestCount == 10, "Should have the latest value")

        observeTask.cancel()
    }

    // MARK: - ThrottledBy @Reaction (async)

    @Test(.timeLimit(.minutes(1)))
    func `ThrottledBy async @Reaction throttles and completes handlers`() async throws {
        let source = RuntimeSource()
        let vm = ThrottledByAsyncReactionVM(source: source)

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()

        // Rapid-fire 10 changes
        for i in 1...10 {
            source.count = i
        }

        // Wait for processing: buffer(100ms) + work(10ms) + extra margin
        try await Task.sleep(for: .milliseconds(400))

        #expect(vm.state.processedCount == 10, "Should have the latest value")
        #expect(vm.state.completedHandlers < 10,
                "ThrottledBy async reaction should throttle: completed \(vm.state.completedHandlers) for 10 changes")
        #expect(vm.state.completedHandlers >= 1, "At least one handler should complete")

        observeTask.cancel()
    }

    // MARK: - Mixed throttledBy + unthrottledBy @Bound

    @Test(.timeLimit(.minutes(1)))
    func `Mixed throttled and unthrottled @Bound in same State`() async {
        let source = RuntimeSource()
        let vm = MixedThrottledByVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.label, equals: "initial")
            await expect(\.state.count, equals: 0)

            // UnthrottledBy @Bound updates promptly
            source.label = "changed"
            await expect(\.state.label, equals: "changed")

            // ThrottledBy @Bound also delivers (after buffer)
            source.count = 42
            await expect(\.state.count, equals: 42)
        }
    }

    // MARK: - Loadable state transitions

    @Test(.timeLimit(.minutes(1)))
    func `Loadable state transitions through all cases`() async {
        let vm = LoadableStatesVM()

        // Initial states
        #expect(vm.state.items.isLoading)
        #expect(vm.state.profile.isEmpty)

        // Load items
        await vm.handle(.loadItems)
        #expect(vm.state.items == .loaded(["a", "b", "c"]))
        #expect(vm.state.items.value == ["a", "b", "c"])

        // Fail items
        await vm.handle(.failItems)
        #expect(vm.state.items.isError)
        #expect(vm.state.items.error == "network")

        // Load profile
        await vm.handle(.loadProfile)
        #expect(vm.state.profile == .loaded("Alice"))

        // Clear profile
        await vm.handle(.clearProfile)
        #expect(vm.state.profile.isEmpty)
    }

    // MARK: - @Reaction deduplication behaviour

    @Test(.timeLimit(.minutes(1)))
    func `Sync @Reaction deduplicates consecutive equal values`() async throws {
        let nav = RuntimeSource()
        let vm = SyncReactionVM(nav: nav)

        try await observing(vm) { expect in
            await expect(\.state.reactionCount, satisfies: { $0 >= 1 })

            nav.destination = "same"
            await expect(\.state.lastDestination, equals: "same")
            let countAfterFirst = vm.state.reactionCount

            // Set to the same value again — valuesOf deduplicates Equatable types
            nav.destination = "same"
            try await yieldForTracking()

            // Reaction should NOT fire again (deduplication via valuesOf)
            #expect(vm.state.reactionCount == countAfterFirst,
                    "Reaction should not fire for duplicate consecutive value")

            // A different value DOES fire
            nav.destination = "other"
            await expect(\.state.lastDestination, equals: "other")
            #expect(vm.state.reactionCount == countAfterFirst + 1)
        }
    }

    // MARK: - @Reaction with non-optional observed property

    @Test(.timeLimit(.minutes(1)))
    func `Sync @Reaction fires for non-optional property changes`() async {
        let source = RuntimeSource()
        let vm = ThrottledBySyncReactionVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.reactionCount, satisfies: { $0 >= 1 })

            source.count = 42
            await expect(\.state.latestCount, equals: 42)
        }
    }

    // MARK: - @Bound + throttled @Bound + @Reaction combined

    @Test(.timeLimit(.minutes(1)))
    func `Unthrottled @Bound delivers before throttled @Bound during burst`() async throws {
        let source = RuntimeSource()
        let vm = MixedThrottledByVM(source: source)

        let observeTask = Task { await vm.startObserving() }
        try await yieldForTracking()

        // Label is unthrottled, count is throttled (100ms)
        source.label = "fast"
        source.count = 99

        // Unthrottled should arrive within one yield
        try await yieldForTracking()
        #expect(vm.state.label == "fast")

        // Throttled should arrive after buffer expires
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.state.count == 99)

        observeTask.cancel()
    }
}

// MARK: - @Stubbable Runtime Tests


@Suite("Macro Runtime — @Stubbable")
@MainActor
struct StubbableMacroRuntimeTests {

    @Test
    func `@Stubbable generates class conforming to protocol`() {
        let stub: any ItemService = StubItemService()
        #expect(stub.items.isEmpty)
        #expect(stub.count == 0)
    }

    @Test
    func `Stub properties are mutable`() {
        let stub = StubItemService()
        stub.items = ["a", "b"]
        stub.count = 5
        #expect(stub.items == ["a", "b"])
        #expect(stub.count == 5)
    }

    @Test
    func `Stub method returns configured return value`() async throws {
        let stub = StubItemService()
        stub.fetchItemsResult = .success(["x", "y"])
        let result = try await stub.fetchItems()
        #expect(result == ["x", "y"])
    }

    @Test
    func `Stub void method does nothing`() async throws {
        let stub = StubItemService()
        // Should not throw
        try await stub.save("item")
    }

    @Test
    func `Stub used as protocol-typed dependency`() async throws {
        let stub = StubItemService()
        stub.fetchItemsResult = .success(["stubbed"])

        let service: any ItemService = stub
        let result = try await service.fetchItems()
        #expect(result == ["stubbed"])
    }
}

// MARK: - @Spyable Runtime Tests


@Suite("Macro Runtime — @Spyable")
@MainActor
struct SpyableMacroRuntimeTests {

    @Test
    func `@Spyable generates class conforming to protocol`() {
        let spy: any AnalyticsService = SpyAnalyticsService()
        spy.trackEvent("test")
    }

    @Test
    func `Spy tracks call count`() {
        let spy = SpyAnalyticsService()
        #expect(spy.trackEventCallCount == 0)

        spy.trackEvent("a")
        #expect(spy.trackEventCallCount == 1)

        spy.trackEvent("b")
        #expect(spy.trackEventCallCount == 2)
    }

    @Test
    func `Spy tracks single-param received value`() {
        let spy = SpyAnalyticsService()
        spy.trackEvent("login")
        #expect(spy.trackEventReceivedName == "login")
    }

    @Test
    func `Spy tracks single-param invocations array`() {
        let spy = SpyAnalyticsService()
        spy.trackEvent("a")
        spy.trackEvent("b")
        spy.trackEvent("c")
        #expect(spy.trackEventReceivedInvocations == ["a", "b", "c"])
    }

    @Test
    func `Spy tracks multi-param received arguments`() {
        let spy = SpyAnalyticsService()
        spy.trackScreen(name: "Home", category: "main")

        #expect(spy.trackScreenReceivedArguments?.name == "Home")
        #expect(spy.trackScreenReceivedArguments?.category == "main")
    }

    @Test
    func `Spy tracks multi-param invocations array`() {
        let spy = SpyAnalyticsService()
        spy.trackScreen(name: "Home", category: "main")
        spy.trackScreen(name: "Settings", category: "prefs")

        #expect(spy.trackScreenReceivedInvocations.count == 2)
        #expect(spy.trackScreenReceivedInvocations[0].name == "Home")
        #expect(spy.trackScreenReceivedInvocations[1].name == "Settings")
    }

    @Test
    func `Spy returns configured return value`() async throws {
        let spy = SpyAnalyticsService()
        spy.fetchReportResult = .success("report data")

        let result = try await spy.fetchReport()
        #expect(result == "report data")
        #expect(spy.fetchReportCallCount == 1)
    }

    @Test
    func `Spy Call enum records all calls in order with correct values`() {
        let spy = SpyAnalyticsService()

        spy.trackEvent("launch")
        spy.trackScreen(name: "Home", category: "main")
        spy.trackEvent("tap")

        #expect(spy.calls.count == 3)
        // Verify order and content via call counts and received values
        #expect(spy.trackEventReceivedInvocations == ["launch", "tap"])
        #expect(spy.trackScreenReceivedInvocations.count == 1)
        #expect(spy.trackScreenReceivedInvocations[0].name == "Home")
    }

}

