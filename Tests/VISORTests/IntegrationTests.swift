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
