import Foundation
import Observation
import VISOR
import Testing

// MARK: - Test Types

@Observable
@MainActor
private final class IntegrationSource {
    var count = 0
}

@Observable
@MainActor
private final class IntegrationVM: ViewModel {
    struct State: Equatable {
        var count = 0
    }

    var state = State()
    private let source: IntegrationSource

    init(source: IntegrationSource) {
        self.source = source
    }

    func startObserving() async {
        await observeCount()
    }

    private func observeCount() async {
        for await value in valuesOf({ self.source.count }) {
            self.updateState(\.count, to: value)
        }
    }
}

@Observable
@MainActor
private final class RoutedIntegrationVM: ViewModel {
    struct State: Equatable {}
    var state = State()
    let routerID: ObjectIdentifier

    init(routerID: ObjectIdentifier) {
        self.routerID = routerID
    }
}

// MARK: - Action VMs (sync and async handle)

@Observable
@MainActor
private final class SyncActionVM: ViewModel {
    struct State: Equatable {
        var count = 0
        var label = ""
    }

    enum Action {
        case increment
        case setLabel(String)
    }

    var state = State()

    func handle(_ action: Action) {
        switch action {
        case .increment:
            updateState(\.count, to: state.count + 1)
        case .setLabel(let text):
            updateState(\.label, to: text)
        }
    }
}

@Observable
@MainActor
private final class AsyncActionVM: ViewModel {
    struct State: Equatable {
        var items: Loadable<[String]> = .loading
        var count = 0
    }

    enum Action {
        case increment
        case loadItems
    }

    var state = State()

    private let source: IntegrationSource

    init(source: IntegrationSource) {
        self.source = source
    }

    func handle(_ action: Action) async {
        switch action {
        case .increment:
            updateState(\.count, to: state.count + 1)
        case .loadItems:
            updateState(\.items, to: .loading)
            // Simulate async work
            try? await Task.sleep(for: .milliseconds(10))
            updateState(\.items, to: .loaded(["a", "b"]))
        }
    }
}

// MARK: - @ViewModel macro with @Bound inside State

/// Source dependency for @Bound tests.
@Observable
@MainActor
final class BoundSource {
    var count = 0
    var label = "initial"
    var isEnabled = false
}

/// Single @Bound property — macro generates init, observe method, startObserving.
@Observable
@ViewModel
final class SingleBoundVM {
    struct State: Equatable {
        @Bound(\SingleBoundVM.source) var count = 0
    }

    var state = State()

    let source: BoundSource
}

/// Multiple @Bound properties from the same dependency.
@Observable
@ViewModel
final class MultiBoundVM {
    struct State: Equatable {
        @Bound(\MultiBoundVM.source) var count = 0
        @Bound(\MultiBoundVM.source) var label = "initial"
        @Bound(\MultiBoundVM.source) var isEnabled = false
    }

    var state = State()

    let source: BoundSource
}

/// @Bound properties mixed with non-bound state and an Action enum.
@Observable
@ViewModel
final class MixedBoundVM {
    struct State: Equatable {
        @Bound(\MixedBoundVM.source) var count = 0
        var localFlag = false
    }

    enum Action {
        case toggleFlag
    }

    var state = State()

    func handle(_ action: Action) {
        switch action {
        case .toggleFlag:
            updateState(\.localFlag, to: !state.localFlag)
        }
    }

    let source: BoundSource
}

// MARK: - Integration Tests

@Suite("Integration")
@MainActor
struct IntegrationTests {

    // MARK: - Factory -> VM -> observing

    @Test(.timeLimit(.minutes(1)))
    func `Factory creates VM that works with observing DSL`() async {
        let source = IntegrationSource()
        let factory = ViewModelFactory { IntegrationVM(source: source) }
        let vm = factory.makeViewModel()

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            source.count = 42
            await expect(\.state.count, equals: 42)
        }
    }

    // MARK: - Two VMs sharing same service

    @Test(.timeLimit(.minutes(1)))
    func `Two VMs sharing same service both reflect changes`() async {
        let source = IntegrationSource()
        let vm1 = IntegrationVM(source: source)
        let vm2 = IntegrationVM(source: source)

        let task1 = Task { await vm1.startObserving() }
        let task2 = Task { await vm2.startObserving() }

        defer {
            task1.cancel()
            task2.cancel()
        }

        // Wait for observation to set up
        try? await yieldForTracking()
        try? await yieldForTracking()

        source.count = 7
        try? await yieldForTracking()
        try? await yieldForTracking()

        #expect(vm1.state.count == 7)
        #expect(vm2.state.count == 7)
    }

    // MARK: - Router navigation does not interfere with VM observation

    @Test(.timeLimit(.minutes(1)))
    func `Router navigation does not interfere with VM observation`() async {
        let source = IntegrationSource()
        let vm = IntegrationVM(source: source)
        let router = Router<TestScene>(level: 0)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            router.push(.detail(id: "1"))
            router.present(sheet: .preferences)

            source.count = 10
            await expect(\.state.count, equals: 10)

            #expect(router.navigationPath.count == 1)
            #expect(router.presentingSheet == .preferences)
        }
    }

    // MARK: - Deep link end-to-end with child router

    @Test
    func `Deep link end-to-end with child router`() {
        let root = Router<TestScene>(level: 0)
        root.configureDeepLinks(scheme: "test", parsers: [
            .equal(to: ["home"], destination: .tab(.home)),
            .equal(to: ["settings", "detail"], destination: .push(.detail(id: "deep"))),
        ])

        let child = root.childRouter(for: .home)
        child.setActive()

        if let destination = child.deepLinkHandler?(URL(string: "test://settings/detail")!) {
            child.deepLinkOpen(to: destination)
        }

        #expect(child.navigationPath == [.detail(id: "deep")])
    }

    // MARK: - Routed factory with real Router

    @Test
    func `Routed factory with real Router creates working VM`() {
        let router = Router<TestScene>(level: 0)
        let factory: ViewModelFactory<RoutedIntegrationVM> = .routed { (r: Router<TestScene>) in
            RoutedIntegrationVM(routerID: ObjectIdentifier(r))
        }

        let vm = factory.makeViewModel(router: router)
        #expect(vm.routerID == ObjectIdentifier(router))
    }

    // MARK: - Sync handle

    @Test
    func `sync handle mutates state without await`() {
        let vm = SyncActionVM()

        vm.handle(.increment)
        #expect(vm.state.count == 1)

        vm.handle(.increment)
        #expect(vm.state.count == 2)

        vm.handle(.setLabel("hello"))
        #expect(vm.state.label == "hello")
    }

    @Test
    func `sync handle called from async context`() async {
        let vm = SyncActionVM()

        await vm.handle(.increment)
        #expect(vm.state.count == 1)

        await vm.handle(.setLabel("async caller"))
        #expect(vm.state.label == "async caller")
    }

    // MARK: - Async handle

    @Test
    func `async handle performs async work`() async {
        let source = IntegrationSource()
        let vm = AsyncActionVM(source: source)

        await vm.handle(.loadItems)
        #expect(vm.state.items == .loaded(["a", "b"]))
    }

    @Test
    func `async handle with sync action case`() async {
        let source = IntegrationSource()
        let vm = AsyncActionVM(source: source)

        await vm.handle(.increment)
        #expect(vm.state.count == 1)

        await vm.handle(.increment)
        #expect(vm.state.count == 2)
    }

    @Test
    func `async handle mixes sync and async cases`() async {
        let source = IntegrationSource()
        let vm = AsyncActionVM(source: source)

        await vm.handle(.increment)
        #expect(vm.state.count == 1)

        await vm.handle(.loadItems)
        #expect(vm.state.items == .loaded(["a", "b"]))
        #expect(vm.state.count == 1)
    }

    // MARK: - @Bound inside State (macro-generated observation)

    @Test(.timeLimit(.minutes(1)))
    func `single @Bound propagates dependency changes to state`() async {
        let source = BoundSource()
        let vm = SingleBoundVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)

            source.count = 5
            await expect(\.state.count, equals: 5)

            source.count = 42
            await expect(\.state.count, equals: 42)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `multiple @Bound properties from same dependency`() async {
        let source = BoundSource()
        let vm = MultiBoundVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)
            await expect(\.state.label, equals: "initial")
            await expect(\.state.isEnabled, equals: false)

            source.count = 10
            await expect(\.state.count, equals: 10)

            source.label = "updated"
            await expect(\.state.label, equals: "updated")

            source.isEnabled = true
            await expect(\.state.isEnabled, equals: true)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `@Bound deduplicates equal values`() async throws {
        let source = BoundSource()
        let vm = SingleBoundVM(source: source)

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

    @Test(.timeLimit(.minutes(1)))
    func `@Bound coexists with local state and actions`() async {
        let source = BoundSource()
        let vm = MixedBoundVM(source: source)

        await observing(vm) { expect in
            await expect(\.state.count, equals: 0)
            #expect(vm.state.localFlag == false)

            // @Bound updates from dependency
            source.count = 7
            await expect(\.state.count, equals: 7)

            // Action updates local state
            vm.handle(.toggleFlag)
            #expect(vm.state.localFlag == true)

            // Both coexist
            source.count = 99
            await expect(\.state.count, equals: 99)
            #expect(vm.state.localFlag == true)
        }
    }

    // MARK: - Sequential observing blocks

    @Test(.timeLimit(.minutes(1)))
    func `Sequential observing blocks on same VM`() async {
        let source = IntegrationSource()
        let vm = IntegrationVM(source: source)

        // First observing block
        await observing(vm) { expect in
            source.count = 1
            await expect(\.state.count, equals: 1)
        }

        // Second observing block picks up current state
        await observing(vm) { expect in
            await expect(\.state.count, equals: 1)

            source.count = 2
            await expect(\.state.count, equals: 2)
        }
    }
}
