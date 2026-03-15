import Foundation
import Observation
import VISOR

// MARK: - Shared Dependencies for Macro Runtime Tests


@Observable
@MainActor
final class RuntimeSource {
    var count = 0
    var label = "initial"
    var isEnabled = false
}

@Observable
@MainActor
final class SecondSource {
    var name = ""
}

@Observable
@MainActor
final class ReactionSource {
    var destination: String? = nil
}

// MARK: - @ViewModel Macro Test VMs


// MARK: 1. Minimal VM — no deps, no actions, no @Bound

@Observable
@ViewModel
final class MinimalVM {
    struct State: Equatable {
        var value = 0
    }
    var state = State()
}

// MARK: 1b. Minimal VM with auto-generated state property

@Observable
@ViewModel
final class AutoStateVM {
    struct State: Equatable {
        var value = 0
    }
}

// MARK: 2. Multiple dependencies (was MARK 2)

@Observable
@ViewModel
final class MultiDepVM {
    struct State: Equatable {
        @Bound(\MultiDepVM.source) var count = 0
        @Bound(\MultiDepVM.second) var name = ""
    }
    var state = State()
    let source: RuntimeSource
    let second: SecondSource
}

// MARK: 3. Single @Bound (auto-generated startObserving)

@Observable
@ViewModel
final class AutoObserveSingleVM {
    struct State: Equatable {
        @Bound(\AutoObserveSingleVM.source) var count = 0
    }
    var state = State()
    let source: RuntimeSource
}

// MARK: 4. Multiple @Bound from same dep (task group startObserving)

@Observable
@ViewModel
final class AutoObserveMultiVM {
    struct State: Equatable {
        @Bound(\AutoObserveMultiVM.source) var count = 0
        @Bound(\AutoObserveMultiVM.source) var label = "initial"
        @Bound(\AutoObserveMultiVM.source) var isEnabled = false
    }
    var state = State()
    let source: RuntimeSource
}

// MARK: 6. @Bound + Action (sync handle)

@Observable
@ViewModel
final class BoundWithSyncActionVM {
    struct State: Equatable {
        @Bound(\BoundWithSyncActionVM.source) var count = 0
        var selectedIndex = 0
    }

    enum Action {
        case selectIndex(Int)
        case reset
    }

    var state = State()

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
    struct State: Equatable {
        @Bound(\BoundWithAsyncActionVM.source) var count = 0
        var detail: Loadable<String> = .loading
    }

    enum Action {
        case loadDetail
        case clearDetail
    }

    var state = State()

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
    struct State: Equatable {
        var lastDestination: String? = nil
        var reactionCount = 0
    }
    var state = State()
    let nav: ReactionSource

    @Reaction(\SyncReactionVM.nav.destination)
    func handleDestination(destination: String?) {
        updateState(\.lastDestination, to: destination)
        updateState(\.reactionCount, to: state.reactionCount + 1)
    }
}

// MARK: 9. @Reaction (async) — only latest value matters

@Observable
@ViewModel
final class AsyncReactionVM {
    struct State: Equatable {
        var processedValue: String? = nil
    }
    var state = State()
    let nav: ReactionSource

    @Reaction(\AsyncReactionVM.nav.destination)
    func processDestination(destination: String?) async {
        guard let destination else { return }
        try? await Task.sleep(for: .milliseconds(20))
        guard !Task.isCancelled else { return }
        updateState(\.processedValue, to: destination)
    }
}

// MARK: 10. @Bound + @Reaction combined

@Observable
@ViewModel
final class BoundAndReactionVM {
    struct State: Equatable {
        @Bound(\BoundAndReactionVM.source) var count = 0
        var lastNav: String? = nil
    }
    var state = State()
    let source: RuntimeSource
    let nav: ReactionSource

    @Reaction(\BoundAndReactionVM.nav.destination)
    func handleNav(destination: String?) {
        updateState(\.lastNav, to: destination)
    }
}

// MARK: 11. VM with custom init (macro should not generate one)

@Observable
@ViewModel
final class CustomInitVM {
    struct State: Equatable {
        @Bound(\CustomInitVM.source) var count = 0
    }
    var state = State()
    let source: RuntimeSource

    init(customSource: RuntimeSource) {
        self.source = customSource
    }
}

// MARK: 12. VM with no dependencies (only Factory typealias generated)

@Observable
@ViewModel
final class NoDepsVM {
    struct State: Equatable {
        var text = ""
    }

    enum Action {
        case setText(String)
    }

    var state = State()

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
    struct State: Equatable {
        @Bound(\NoActionVM.source) var count = 0
    }
    var state = State()
    let source: RuntimeSource
}

// MARK: 14. VM with Loadable fields exercising all states

@Observable
@ViewModel
final class LoadableStatesVM {
    struct State: Equatable {
        var items: Loadable<[String]> = .loading
        var profile: Loadable<String> = .empty
    }

    enum Action {
        case loadItems
        case loadProfile
        case failItems
        case clearProfile
    }

    var state = State()

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

// MARK: - Non-Equatable State VM


struct NonEquatableWrapper { let value: Int }

/// Tests updateState overload resolution directly, independent of macro generation.
@Observable
@MainActor
final class NonEquatableVM: ViewModel {
    struct State: Equatable {
        // wrapper is non-Equatable, but State itself conforms via manual implementation
        var wrapper = NonEquatableWrapper(value: 0)
        var label = ""

        // Intentionally compares only `label` to test the non-Equatable updateState overload on `wrapper`
        static func == (lhs: State, rhs: State) -> Bool {
            lhs.label == rhs.label
        }
    }
    var state = State()
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
