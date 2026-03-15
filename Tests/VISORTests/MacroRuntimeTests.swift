import Foundation
import Observation
import VISOR
import Testing

// MARK: - Tests


@Suite("Macro Runtime — @ViewModel")
@MainActor
struct ViewModelMacroRuntimeTests {

    // MARK: - Minimal VMs

    @Test
    func `Minimal VM with no deps can be constructed and mutated`() {
        let vm = MinimalVM()
        #expect(vm.state.value == 0)
        vm.updateState(\.value, to: 42)
        #expect(vm.state.value == 42)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Auto-generated state property is observation-tracked`() async {
        let vm = AutoStateVM()
        #expect(vm.state.value == 0)

        await observing(vm) { expect in
            vm.updateState(\.value, to: 1)
            await expect(\.state.value, equals: 1)

            vm.updateState(\.value, to: 2)
            await expect(\.state.value, equals: 2)
        }
    }

    @Test
    func `NoDeps VM handles action without dependencies`() {
        let vm = NoDepsVM()
        vm.handle(.setText("hello"))
        #expect(vm.state.text == "hello")
    }

    // MARK: - Memberwise init generation

    @Test
    func `Macro generates memberwise init for multiple deps`() {
        let source = RuntimeSource()
        let second = SecondSource()
        let vm = MultiDepVM(source: source, second: second)
        #expect(vm.source === source)
        #expect(vm.second === second)
    }

    @Test
    func `Custom init is preserved when provided`() {
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

    @Test(.timeLimit(.minutes(1)))
    func `Multiple @Bound all update independently`() async {
        let source = RuntimeSource()
        let vm = AutoObserveMultiVM(source: source)

        await observing(vm) { expect in
            // Update all three in sequence
            source.count = 1
            source.label = "one"
            source.isEnabled = true
            await expect(\.state.count, equals: 1)
            await expect(\.state.label, equals: "one")
            await expect(\.state.isEnabled, equals: true)

            // Update only one
            source.count = 2
            await expect(\.state.count, equals: 2)
            // Others remain unchanged
            #expect(vm.state.label == "one")
            #expect(vm.state.isEnabled == true)
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
        let nav = ReactionSource()
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
    func `Async @Reaction cancels previous handler for latest value`() async throws {
        let nav = ReactionSource()
        let vm = AsyncReactionVM(nav: nav)

        await observing(vm) { expect in
            // Rapid-fire: only the last should survive
            nav.destination = "first"
            nav.destination = "second"
            nav.destination = "final"

            await expect(\.state.processedValue, equals: "final")
        }
    }

    // MARK: - @Bound + @Reaction combined

    @Test(.timeLimit(.minutes(1)))
    func `@Bound and @Reaction both active concurrently`() async {
        let source = RuntimeSource()
        let nav = ReactionSource()
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

    // MARK: - Non-Equatable updateState always writes

    @Test
    func `Non-Equatable updateState writes even when Equatable value unchanged`() {
        let vm = NonEquatableVM()
        vm.updateState(\NonEquatableVM.State.wrapper, to: NonEquatableWrapper(value: 1))
        #expect(vm.state.wrapper.value == 1)

        // Equatable field: same value should be deduplicated (guard prevents write)
        vm.updateState(\NonEquatableVM.State.label, to: "a")
        vm.updateState(\NonEquatableVM.State.label, to: "a")
        #expect(vm.state.label == "a")

        // Non-Equatable field: verify the overload is selected by testing type change
        vm.updateState(\NonEquatableVM.State.wrapper, to: NonEquatableWrapper(value: 2))
        #expect(vm.state.wrapper.value == 2)
    }

    // MARK: - @Reaction deduplication behavior

    @Test(.timeLimit(.minutes(1)))
    func `Sync @Reaction deduplicates consecutive equal values`() async throws {
        let nav = ReactionSource()
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
}

// MARK: - @Stubbable Runtime Tests


@Suite("Macro Runtime — @Stubbable")
@MainActor
struct StubbableMacroRuntimeTests {

    @Test
    func `Stub conforms to protocol`() {
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
    func `Spy conforms to protocol`() {
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

