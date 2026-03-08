import Foundation
import Observation
import VISOR
import Testing

// MARK: - Test Types (must be non-private for weak refs to work across closures)

@Observable
@MainActor
final class LeakSource {
    var count = 0
    var label = ""
    var destination: String? = nil
}

// Manual VM (no macro) to isolate observation lifecycle
@Observable
@MainActor
final class ManualLeakVM: ViewModel {
    struct State: Equatable {
        var count = 0
    }
    var state = State()
    let source: LeakSource

    init(source: LeakSource) {
        self.source = source
    }

    func startObserving() async {
        for await value in valuesOf({ self.source.count }) {
            self.updateState(\.count, to: value)
        }
    }
}

// Macro-generated single @Bound
@Observable
@ViewModel
final class LeakSingleBoundVM {
    struct State: Equatable {
        @Bound(\LeakSingleBoundVM.source) var count = 0
    }
    var state = State()
    let source: LeakSource
}

// Macro-generated multiple @Bound (task group)
@Observable
@ViewModel
final class LeakMultiBoundVM {
    struct State: Equatable {
        @Bound(\LeakMultiBoundVM.source) var count = 0
        @Bound(\LeakMultiBoundVM.source) var label = ""
    }
    var state = State()
    let source: LeakSource
}

// Macro-generated @Reaction (sync)
@Observable
@ViewModel
final class LeakSyncReactionVM {
    struct State: Equatable {
        var lastNav: String? = nil
    }
    var state = State()
    let source: LeakSource

    @Reaction(\LeakSyncReactionVM.source.destination)
    func handleNav(destination: String?) {
        updateState(\.lastNav, to: destination)
    }
}

// Macro-generated @Reaction (async)
@Observable
@ViewModel
final class LeakAsyncReactionVM {
    struct State: Equatable {
        var processed: String? = nil
    }
    var state = State()
    let source: LeakSource

    @Reaction(\LeakAsyncReactionVM.source.destination)
    func handleNav(destination: String?) async {
        guard let destination else { return }
        guard !Task.isCancelled else { return }
        updateState(\.processed, to: destination)
    }
}

// Macro-generated @Bound + @Reaction combined
@Observable
@ViewModel
final class LeakCombinedVM {
    struct State: Equatable {
        @Bound(\LeakCombinedVM.source) var count = 0
        var lastNav: String? = nil
    }
    var state = State()
    let source: LeakSource

    @Reaction(\LeakCombinedVM.source.destination)
    func handleNav(destination: String?) {
        updateState(\.lastNav, to: destination)
    }
}

// VM with async action
@Observable
@ViewModel
final class LeakAsyncActionVM {
    struct State: Equatable {
        var items: Loadable<[String]> = .loading
    }

    enum Action {
        case load
    }

    var state = State()

    func handle(_ action: Action) async {
        updateState(\.items, to: .loading)
        try? await Task.sleep(for: .milliseconds(10))
        updateState(\.items, to: .loaded(["done"]))
    }
}

// MARK: - Memory Leak Tests


@Suite("Memory Leaks")
@MainActor
struct MemoryLeakTests {

    // MARK: - Manual observation VM

    @Test(.timeLimit(.minutes(1)))
    func `Manual VM is released after observation cancelled`() async throws {
        let source = LeakSource()
        var vm: ManualLeakVM? = ManualLeakVM(source: source)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }

        try await yieldForTracking()
        source.count = 1
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "ManualLeakVM should be deallocated after observation cancelled")
    }

    // MARK: - observing() DSL scoped lifetime

    @Test(.timeLimit(.minutes(1)))
    func `VM is released after observing scope exits`() async throws {
        let source = LeakSource()
        var vm: ManualLeakVM? = ManualLeakVM(source: source)
        weak let weakVM = vm

        await observing(vm!) { expect in
            source.count = 1
            await expect(\.state.count, equals: 1)
        }

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "VM should be deallocated after observing scope exits")
    }

    // MARK: - Single @Bound (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Single @Bound VM is released after observation cancelled`() async throws {
        let source = LeakSource()
        var vm: LeakSingleBoundVM? = LeakSingleBoundVM(source: source)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        source.count = 5
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "Single @Bound VM should be deallocated after observation cancelled")
    }

    // MARK: - Multiple @Bound with task group (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Multi @Bound VM is released after observation cancelled`() async throws {
        let source = LeakSource()
        var vm: LeakMultiBoundVM? = LeakMultiBoundVM(source: source)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        source.count = 1
        source.label = "hello"
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "Multi @Bound VM should be deallocated after observation cancelled")
    }

    // MARK: - @Reaction sync (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Sync @Reaction VM is released after observation cancelled`() async throws {
        let source = LeakSource()
        var vm: LeakSyncReactionVM? = LeakSyncReactionVM(source: source)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        source.destination = "test"
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "Sync @Reaction VM should be deallocated after observation cancelled")
    }

    // MARK: - @Reaction async (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Async @Reaction VM is released after observation cancelled`() async throws {
        let source = LeakSource()
        var vm: LeakAsyncReactionVM? = LeakAsyncReactionVM(source: source)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        source.destination = "test"
        try await yieldForTracking()
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "Async @Reaction VM should be deallocated after observation cancelled")
    }

    // MARK: - @Bound + @Reaction combined (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Combined @Bound + @Reaction VM is released after observation cancelled`() async throws {
        let source = LeakSource()
        var vm: LeakCombinedVM? = LeakCombinedVM(source: source)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        source.count = 1
        source.destination = "nav"
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "Combined VM should be deallocated after observation cancelled")
    }

    // MARK: - Source not retained after VM and observation released

    @Test(.timeLimit(.minutes(1)))
    func `Source is released when VM and observation are released`() async throws {
        var source: LeakSource? = LeakSource()
        weak let weakSource = source
        var vm: LeakSingleBoundVM? = LeakSingleBoundVM(source: source!)

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        source!.count = 1
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        // Release both the VM and the source — observation should not add extra retains
        vm = nil
        source = nil
        try await yieldForTracking()

        #expect(weakSource == nil, "Source should be deallocated when VM and observation are released")
    }

    // MARK: - valuesOf stream releases captures after cancellation

    @Test(.timeLimit(.minutes(1)))
    func `valuesOf stream releases captured observable after cancellation`() async throws {
        var source: LeakSource? = LeakSource()
        weak let weakSource = source

        let task = Task { @MainActor [source] in
            for await _ in valuesOf({ source!.count }) {
                break // consume one value then exit
            }
        }

        try await yieldForTracking()
        await task.value

        source = nil
        try await yieldForTracking()

        #expect(weakSource == nil, "Source should be released after valuesOf stream finishes")
    }

    // MARK: - latestValuesOf releases handler after cancellation

    @Test(.timeLimit(.minutes(1)))
    func `latestValuesOf stops processing after cancellation`() async throws {
        let source = LeakSource()
        var processedCount = 0

        let task = Task { @MainActor in
            await latestValuesOf({ source.count }) { _ in
                processedCount += 1
            }
        }

        try await yieldForTracking()
        source.count = 1
        try await yieldForTracking()

        let countBeforeCancel = processedCount
        task.cancel()
        try await yieldForTracking()

        source.count = 2
        source.count = 3
        try await yieldForTracking()
        try await yieldForTracking()

        // No further processing should happen after cancellation
        #expect(processedCount == countBeforeCancel, "Handler should stop processing after cancellation")
    }

    // MARK: - Async action VM does not leak

    @Test(.timeLimit(.minutes(1)))
    func `Async action VM is released after action completes`() async throws {
        var vm: LeakAsyncActionVM? = LeakAsyncActionVM()
        weak let weakVM = vm

        await vm!.handle(.load)
        #expect(vm!.state.items == .loaded(["done"]))

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "Async action VM should be deallocated after action completes")
    }

    // MARK: - Multiple sequential observing blocks don't accumulate

    @Test(.timeLimit(.minutes(1)))
    func `Sequential observing blocks do not accumulate retained references`() async throws {
        let source = LeakSource()
        var vm: ManualLeakVM? = ManualLeakVM(source: source)
        weak let weakVM = vm

        // Run observing multiple times
        for i in 1...3 {
            await observing(vm!) { expect in
                source.count = i
                await expect(\.state.count, equals: i)
            }
        }

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "VM should be deallocated after multiple observing scopes")
    }

    // MARK: - Two VMs sharing source, both released independently

    @Test(.timeLimit(.minutes(1)))
    func `Two VMs sharing source are released independently`() async throws {
        let source = LeakSource()
        var vm1: LeakSingleBoundVM? = LeakSingleBoundVM(source: source)
        var vm2: LeakSingleBoundVM? = LeakSingleBoundVM(source: source)
        weak let weakVM1 = vm1
        weak let weakVM2 = vm2

        let task1 = Task { await vm1!.startObserving() }
        let task2 = Task { await vm2!.startObserving() }
        try await yieldForTracking()

        source.count = 1
        try await yieldForTracking()

        // Cancel and release first VM
        task1.cancel()
        try await yieldForTracking()
        vm1 = nil
        try await yieldForTracking()

        #expect(weakVM1 == nil, "First VM should be deallocated independently")
        #expect(weakVM2 != nil, "Second VM should still be alive")

        // Cancel and release second VM
        task2.cancel()
        try await yieldForTracking()
        vm2 = nil
        try await yieldForTracking()

        #expect(weakVM2 == nil, "Second VM should be deallocated independently")
    }

    // MARK: - Router parent-child does not leak

    @Test(.timeLimit(.minutes(1)))
    func `Router child does not retain parent`() async throws {
        var root: Router<TestScene>? = Router<TestScene>(level: 0)
        weak let weakRoot = root
        let child = root!.childRouter(for: .home)

        child.push(.detail(id: "1"))

        root = nil
        try await yieldForTracking()

        #expect(weakRoot == nil, "Root router should be deallocated — child holds weak ref")
        #expect(child.navigationPath == [.detail(id: "1")])
    }

}
