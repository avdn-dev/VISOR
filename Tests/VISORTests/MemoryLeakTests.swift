import Foundation
import Observation
import VISOR
import Testing

// MARK: - Test Types (must be non-private for weak refs to work across closures)

// Manual VM (no macro) to isolate observation lifecycle
@Observable
@MainActor
final class ManualLeakVM: ViewModel {
    struct State: Equatable {
        var count = 0
    }
    var state = State()
    let source: RuntimeSource

    init(source: RuntimeSource) {
        self.source = source
    }

    func startObserving() async {
        for await value in valuesOf({ self.source.count }) {
            self.updateState(\.count, to: value)
        }
    }
}

// VM with async action (no equivalent in MacroRuntimeTestTypes)
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

    // MARK: - Helper

    /// Starts observation, exercises the VM, cancels, nils out, and asserts deallocation.
    private func assertNoLeak<VM: ViewModel>(
        _ make: () -> VM,
        exercise: (VM) async throws -> Void = { _ in },
        file: String = #file,
        line: Int = #line
    ) async throws {
        var vm: VM? = make()
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        try await exercise(vm!)
        try await yieldForTracking()

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "\(VM.self) should be deallocated after observation cancelled",
                sourceLocation: SourceLocation(fileID: file, filePath: file, line: line, column: 1))
    }

    // MARK: - Manual observation VM

    @Test(.timeLimit(.minutes(1)))
    func `Manual VM is released after observation cancelled`() async throws {
        let source = RuntimeSource()
        try await assertNoLeak({ ManualLeakVM(source: source) }) { _ in
            source.count = 1
        }
    }

    // MARK: - observing() DSL scoped lifetime

    @Test(.timeLimit(.minutes(1)))
    func `VM is released after observing scope exits`() async throws {
        let source = RuntimeSource()
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
        let source = RuntimeSource()
        try await assertNoLeak({ AutoObserveSingleVM(source: source) }) { _ in
            source.count = 5
        }
    }

    // MARK: - Multiple @Bound with task group (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Multi @Bound VM is released after observation cancelled`() async throws {
        let source = RuntimeSource()
        try await assertNoLeak({ AutoObserveMultiVM(source: source) }) { _ in
            source.count = 1
            source.label = "hello"
        }
    }

    // MARK: - @Reaction sync (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Sync @Reaction VM is released after observation cancelled`() async throws {
        let nav = RuntimeSource()
        try await assertNoLeak({ SyncReactionVM(nav: nav) }) { _ in
            nav.destination = "test"
        }
    }

    // MARK: - @Reaction async (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Async @Reaction VM is released after observation cancelled`() async throws {
        let nav = RuntimeSource()
        try await assertNoLeak({ AsyncReactionVM(nav: nav) }) { _ in
            nav.destination = "test"
            // Extra yield for async handler to complete
            try await yieldForTracking()
        }
    }

    // MARK: - @Bound + @Reaction combined (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Combined @Bound + @Reaction VM is released after observation cancelled`() async throws {
        let source = RuntimeSource()
        let nav = RuntimeSource()
        try await assertNoLeak({ BoundAndReactionVM(source: source, nav: nav) }) { _ in
            source.count = 1
            nav.destination = "nav"
        }
    }

    // MARK: - @Polled (macro-generated)

    @Test(.timeLimit(.minutes(1)))
    func `Polled VM is released after observation cancelled`() async throws {
        let monitor = BatteryMonitor()
        monitor.level = 0.5

        var vm: PolledSingleVM? = PolledSingleVM(monitor: monitor)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        try await yieldForTracking()

        monitor.level = 0.8
        try await Task.sleep(for: .milliseconds(120))

        task.cancel()
        try await yieldForTracking()

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "Polled VM should be deallocated after observation cancelled")
    }

    // MARK: - Source not retained after VM and observation released

    @Test(.timeLimit(.minutes(1)))
    func `Source is released when VM and observation are released`() async throws {
        var source: RuntimeSource? = RuntimeSource()
        weak let weakSource = source
        var vm: AutoObserveSingleVM? = AutoObserveSingleVM(source: source!)

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
        var source: RuntimeSource? = RuntimeSource()
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
        let source = RuntimeSource()
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
        let source = RuntimeSource()
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
        let source = RuntimeSource()
        var vm1: AutoObserveSingleVM? = AutoObserveSingleVM(source: source)
        var vm2: AutoObserveSingleVM? = AutoObserveSingleVM(source: source)
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

    // MARK: - Immediate cancellation before first yield

    @Test(.timeLimit(.minutes(1)))
    func `VM is released when observation cancelled before first yield`() async throws {
        let source = RuntimeSource()
        var vm: ManualLeakVM? = ManualLeakVM(source: source)
        weak let weakVM = vm

        let task = Task { await vm!.startObserving() }
        // Cancel immediately — no yieldForTracking() first
        task.cancel()
        _ = await task.value

        vm = nil
        try await yieldForTracking()

        #expect(weakVM == nil, "VM should be deallocated even when cancelled before first observation fires")
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
