import Foundation
import Observation
import VISOR
import Testing

// MARK: - Test Types

@Observable
@MainActor
private final class IntegrationVM: ViewModel {
    struct State: Equatable {
        var count = 0
    }

    var state = State()
    private let source: TestSource

    init(source: TestSource) {
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
        case failItems
    }

    var state = State()

    func handle(_ action: Action) async {
        switch action {
        case .increment:
            updateState(\.count, to: state.count + 1)
        case .loadItems:
            updateState(\.items, to: .loading)
            try? await Task.sleep(for: .milliseconds(10))
            updateState(\.items, to: .loaded(["a", "b"]))
        case .failItems:
            updateState(\.items, to: .error("network"))
        }
    }
}

// MARK: - Integration Tests

@Suite("Integration")
@MainActor
struct IntegrationTests {

    // MARK: - Factory -> VM -> observing

    @Test(.timeLimit(.minutes(1)))
    func `Factory creates VM that works with observing DSL`() async {
        let source = TestSource()
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
        let source = TestSource()
        let vm1 = IntegrationVM(source: source)
        let vm2 = IntegrationVM(source: source)

        let task2 = Task { await vm2.startObserving() }
        defer { task2.cancel() }

        await observing(vm1) { expect in
            source.count = 7
            await expect(\.state.count, equals: 7)

            // Wait for vm2 to also converge
            for await count in valuesOf({ vm2.state.count }) {
                if count == 7 { break }
            }
        }
    }

    // MARK: - Router navigation does not interfere with VM observation

    @Test(.timeLimit(.minutes(1)))
    func `Router navigation does not interfere with VM observation`() async {
        let source = TestSource()
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
        child.activate()

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
    func `Sync handle mutates state without await`() {
        let vm = SyncActionVM()

        vm.handle(.increment)
        #expect(vm.state.count == 1)

        vm.handle(.increment)
        #expect(vm.state.count == 2)

        vm.handle(.setLabel("hello"))
        #expect(vm.state.label == "hello")
    }

    // MARK: - Async handle

    @Test
    func `Async handle performs async work`() async {
        let vm = AsyncActionVM()

        await vm.handle(.loadItems)
        #expect(vm.state.items == .loaded(["a", "b"]))
    }

    @Test
    func `Async handle mixes sync and async cases`() async {
        let vm = AsyncActionVM()

        await vm.handle(.increment)
        #expect(vm.state.count == 1)

        await vm.handle(.loadItems)
        #expect(vm.state.items == .loaded(["a", "b"]))
        #expect(vm.state.count == 1)
    }

    // MARK: - Error path via Loadable

    @Test
    func `Async handle transitions to error state`() async {
        let vm = AsyncActionVM()

        await vm.handle(.failItems)
        #expect(vm.state.items.isError)
        #expect(vm.state.items.error == "network")
    }

    // MARK: - Post-cancel observation stops

    @Test(.timeLimit(.minutes(1)))
    func `Observation stops propagating after cancellation`() async throws {
        let source = TestSource()
        let vm = IntegrationVM(source: source)

        let task = Task { await vm.startObserving() }
        try await yieldForTracking()
        try await yieldForTracking()

        source.count = 5
        try await yieldForTracking()
        #expect(vm.state.count == 5)

        task.cancel()
        try await Task.sleep(for: .milliseconds(100))

        let countAfterCancel = vm.state.count
        source.count = 999
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.state.count == countAfterCancel, "Changes should not propagate after cancellation")
    }

}
