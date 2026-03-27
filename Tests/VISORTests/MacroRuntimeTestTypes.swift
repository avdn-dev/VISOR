import Foundation
import VISOR

// MARK: - Shared Dependencies for Macro Runtime Tests


@Observable
@MainActor
final class RuntimeSource {
    var count = 0
    var label = "initial"
    var isEnabled = false
    var destination: String? = nil
}

@Observable
@MainActor
final class SecondSource {
    var name = ""
}

// MARK: - @ViewModel Macro Test VMs


// MARK: 1. Minimal VM — no deps, no actions, no @Bound

@Observable
@ViewModel
final class MinimalVM {
    @Observable
    final class State {
        var value = 0
    }
}

// MARK: 1b. Minimal VM with auto-generated state property

@Observable
@ViewModel
final class AutoStateVM {
    @Observable
    final class State {
        var value = 0
    }
}

// MARK: 1c. @Reaction observing the VM's own (non-@Bound) state property

@Observable
@ViewModel
final class ReactionOnStateVM {
    @Observable
    final class State {
        var counter = 0
        var doubled = 0
    }

    @Reaction(\Self.state.counter)
    func onCounterChanged(counter: Int) {
        updateState(\.doubled, to: counter * 2)
    }
}

// MARK: 2. Multiple dependencies (was MARK 2)

@Observable
@ViewModel
final class MultiDepVM {
    @Observable
    final class State {
        @Bound(\MultiDepVM.source.count) var count: Int
        @Bound(\MultiDepVM.second.name) var name: String
        nonisolated init(count: Int, name: String) { self._count = count; self._name = name }
    }
    let source: RuntimeSource
    let second: SecondSource
}

// MARK: 3. Single @Bound (auto-generated startObserving)

@Observable
@ViewModel
final class AutoObserveSingleVM {
    @Observable
    final class State {
        @Bound(\AutoObserveSingleVM.source.count) var count: Int
        nonisolated init(count: Int) { self._count = count }
    }
    let source: RuntimeSource
}

// MARK: 4. Multiple @Bound from same dep (task group startObserving)

@Observable
@ViewModel
final class AutoObserveMultiVM {
    @Observable
    final class State {
        @Bound(\AutoObserveMultiVM.source.count) var count: Int
        @Bound(\AutoObserveMultiVM.source.label) var label: String
        @Bound(\AutoObserveMultiVM.source.isEnabled) var isEnabled: Bool
        nonisolated init(count: Int, label: String, isEnabled: Bool) { self._count = count; self._label = label; self._isEnabled = isEnabled }
    }
    let source: RuntimeSource
}

// MARK: 6. @Bound + Action (sync handle)

@Observable
@ViewModel
final class BoundWithSyncActionVM {
    @Observable
    final class State {
        @Bound(\BoundWithSyncActionVM.source.count) var count: Int
        var selectedIndex = 0
        nonisolated init(count: Int) { self._count = count }
    }

    enum Action {
        case selectIndex(Int)
        case reset
    }

    func handle(_ action: Action) {
        switch action {
        case .selectIndex(let i):
            updateState(\.selectedIndex, to: i)
        case .reset:
            updateState(\.selectedIndex, to: 0)
        }
    }

    let source: RuntimeSource
}

// MARK: 7. @Bound + Action (async handle) with Loadable state

@Observable
@ViewModel
final class BoundWithAsyncActionVM {
    @Observable
    final class State {
        @Bound(\BoundWithAsyncActionVM.source.count) var count: Int
        var detail: Loadable<String> = .loading
        nonisolated init(count: Int) { self._count = count }
    }

    enum Action {
        case loadDetail
        case clearDetail
    }

    func handle(_ action: Action) async {
        switch action {
        case .loadDetail:
            updateState(\.detail, to: .loading)
            try? await Task.sleep(for: .milliseconds(10))
            updateState(\.detail, to: .loaded("fetched"))
        case .clearDetail:
            updateState(\.detail, to: .empty)
        }
    }

    let source: RuntimeSource
}

// MARK: 8. @Reaction (sync) — every value triggers handler

@Observable
@ViewModel
final class SyncReactionVM {
    @Observable
    final class State {
        var lastDestination: String? = nil
        var reactionCount = 0
    }
    let nav: RuntimeSource

    @Reaction(\SyncReactionVM.nav.destination)
    func handleDestination(destination: String?) {
        updateState(\.lastDestination, to: destination)
        updateState(\.reactionCount, to: state.reactionCount + 1)
    }
}

// MARK: 9. @Reaction (async) — sequential delivery

@Observable
@ViewModel
final class AsyncReactionVM {
    @Observable
    final class State {
        var processedValue: String? = nil
    }
    let nav: RuntimeSource

    @Reaction(\AsyncReactionVM.nav.destination)
    func processDestination(destination: String?) async {
        guard let destination else { return }
        try? await Task.sleep(for: .milliseconds(20))
        updateState(\.processedValue, to: destination)
    }
}

// MARK: 10. @Bound + @Reaction combined

@Observable
@ViewModel
final class BoundAndReactionVM {
    @Observable
    final class State {
        @Bound(\BoundAndReactionVM.source.count) var count: Int
        var lastNav: String? = nil
        nonisolated init(count: Int) { self._count = count }
    }
    let source: RuntimeSource
    let nav: RuntimeSource

    @Reaction(\BoundAndReactionVM.nav.destination)
    func handleNav(destination: String?) {
        updateState(\.lastNav, to: destination)
    }
}

// MARK: 11. VM with custom init (macro should not generate one)

@Observable
@ViewModel
final class CustomInitVM {
    @Observable
    final class State {
        @Bound(\CustomInitVM.source.count) var count: Int
        nonisolated init(count: Int) { self._count = count }
    }
    let source: RuntimeSource

    init(customSource: RuntimeSource) {
        self.source = customSource
        self._state = State(count: customSource.count)
    }
}

// MARK: 12. VM with no dependencies (only Factory typealias generated)

@Observable
@ViewModel
final class NoDepsVM {
    @Observable
    final class State {
        var text = ""
    }

    enum Action {
        case setText(String)
    }

    func handle(_ action: Action) {
        switch action {
        case .setText(let t):
            updateState(\.text, to: t)
        }
    }
}

// MARK: 13. VM using Action == Never (no Action enum)

@Observable
@ViewModel
final class NoActionVM {
    @Observable
    final class State {
        @Bound(\NoActionVM.source.count) var count: Int
        nonisolated init(count: Int) { self._count = count }
    }
    let source: RuntimeSource
}

// MARK: 14. VM with Loadable fields exercising all states

@Observable
@ViewModel
final class LoadableStatesVM {
    @Observable
    final class State {
        var items: Loadable<[String]> = .loading
        var profile: Loadable<String> = .empty
    }

    enum Action {
        case loadItems
        case loadProfile
        case failItems
        case clearProfile
    }

    func handle(_ action: Action) async {
        switch action {
        case .loadItems:
            updateState(\.items, to: .loading)
            try? await Task.sleep(for: .milliseconds(10))
            updateState(\.items, to: .loaded(["a", "b", "c"]))
        case .loadProfile:
            updateState(\.profile, to: .loading)
            try? await Task.sleep(for: .milliseconds(10))
            updateState(\.profile, to: .loaded("Alice"))
        case .failItems:
            updateState(\.items, to: .error("network"))
        case .clearProfile:
            updateState(\.profile, to: .empty)
        }
    }
}

// MARK: - Non-observable polling source

@MainActor
final class BatteryMonitor {
    var level: Float = 0.75
    var isCharging: Bool = false
}

// MARK: 15. Single @Polled

@Observable
@ViewModel
final class PolledSingleVM {
    @Observable
    final class State {
        @Polled(\PolledSingleVM.monitor.level, every: .milliseconds(50)) var level: Float
        nonisolated init(level: Float) { self._level = level }
    }
    let monitor: BatteryMonitor
}

// MARK: 16. Mixed @Bound + @Polled (interleaved declaration order)

@Observable
@ViewModel
final class BoundAndPolledVM {
    @Observable
    final class State {
        @Bound(\BoundAndPolledVM.source.count) var count: Int
        @Polled(\BoundAndPolledVM.monitor.level, every: .milliseconds(50)) var level: Float
        @Bound(\BoundAndPolledVM.source.label) var label: String
        nonisolated init(count: Int, level: Float, label: String) { self._count = count; self._level = level; self._label = label }
    }
    let source: RuntimeSource
    let monitor: BatteryMonitor
}

// MARK: 17. ThrottledBy @Bound

@Observable
@ViewModel
final class ThrottledByBoundVM {
    @Observable
    final class State {
        @Bound(\ThrottledByBoundVM.source.count, throttledBy: .milliseconds(100)) var count: Int
        nonisolated init(count: Int) { self._count = count }
    }
    let source: RuntimeSource
}

// MARK: 18. ThrottledBy sync @Reaction

@Observable
@ViewModel
final class ThrottledBySyncReactionVM {
    @Observable
    final class State {
        var latestCount = 0
        var reactionCount = 0
    }
    let source: RuntimeSource

    @Reaction(\ThrottledBySyncReactionVM.source.count, throttledBy: .milliseconds(100))
    func handleCount(count: Int) {
        updateState(\.latestCount, to: count)
        updateState(\.reactionCount, to: state.reactionCount + 1)
    }
}

// MARK: 19. ThrottledBy async @Reaction

@Observable
@ViewModel
final class ThrottledByAsyncReactionVM {
    @Observable
    final class State {
        var processedCount = 0
        var completedHandlers = 0
    }
    let source: RuntimeSource

    @Reaction(\ThrottledByAsyncReactionVM.source.count, throttledBy: .milliseconds(100))
    func handleCount(count: Int) async {
        try? await Task.sleep(for: .milliseconds(10))
        guard !Task.isCancelled else { return }
        updateState(\.processedCount, to: count)
        updateState(\.completedHandlers, to: state.completedHandlers + 1)
    }
}

// MARK: 20. Mixed throttledBy + non-throttled @Bound

@Observable
@ViewModel
final class MixedThrottledByVM {
    @Observable
    final class State {
        @Bound(\MixedThrottledByVM.source.label) var label: String
        @Bound(\MixedThrottledByVM.source.count, throttledBy: .milliseconds(100)) var count: Int
        nonisolated init(label: String, count: Int) { self._label = label; self._count = count }
    }
    let source: RuntimeSource
}

// MARK: - Non-Equatable State VM


struct NonEquatableWrapper { let value: Int }

/// Tests updateState overload resolution directly, independent of macro generation.
@Observable
@MainActor
final class NonEquatableVM: ViewModel {
    @Observable
    final class State {
        var wrapper = NonEquatableWrapper(value: 0)
        var label = ""
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
}

// MARK: - @Stubbable / @Spyable Macro Test Protocols


@Stubbable
protocol ItemService {
    var items: [String] { get }
    var count: Int { get }
    func fetchItems() async throws -> [String]
    func save(_ item: String) async throws
}

@Spyable
protocol AnalyticsService {
    func trackEvent(_ name: String)
    func trackScreen(name: String, category: String)
    func fetchReport() async throws -> String
}
