# VISOR

Macro-powered SwiftUI architecture with source-owned observation, structured view lifetime, deterministic state-history testing, and type-safe navigation.

## Why VISOR?

SwiftUI and Observation answer how a view notices a mutation. Product applications still need to decide where durable state lives, which async work owns that state, when a screen is ready, and how tests prove the complete result of an action.

VISOR gives those decisions one explicit shape:

- Producers publish stable, `Sendable` snapshots through `ObservationChannel`; consumers receive the read-only `ObservationSource` capability.
- `@ViewModel`, `@Bound`, and `@Reaction` generate MainActor State routing and cooperative observation recipes.
- `@StateBinding` routes control writes through synchronous actions; typed effect owners manage replacement, FIFO, or concurrent work with completion handles.
- `@LazyViewModel` owns the generated observation session, gates content on readiness, and applies scene-lifetime policy.
- `VISORTesting` fences one structured action at a time and checks its complete State mutation history.
- `VISORTestDoubles` generates stubs and spies without pulling the production or testing runtime into a service module.
- `Router` centralises typed navigation, modal presentation, top-level destinations, and deep links.

VISOR is aimed at applications with repeated feature modules, service-backed state, async side effects, cheap previews, and tests that should not depend on sleeps or observation races.

## Requirements

- Swift 6.2+
- iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+ / visionOS 2+

Consuming targets do not need `MainActorByDefault`. VISOR's library targets are
nonisolated by default, each `@ViewModel` declaration is explicitly
`@MainActor`, and services retain their natural isolation. Generated test
doubles preserve the declaring protocol and consumer target's isolation rather
than imposing a global actor.

## Products

VISOR has four deliberately separate products and no umbrella product:

| Product | Use |
|---|---|
| `VISORObservation` | Isolation-neutral `ObservationChannel` and `ObservationSource` producer contracts |
| `VISOR` | ViewModel, State, SwiftUI, navigation, and architecture macros/runtime |
| `VISORTesting` | Swift Testing integration: `observe`, `perform`, and `expect` |
| `VISORTestDoubles` | `@GenerateStub`, `@GenerateSpy`, and their configuration attributes |

Products do not re-export sibling VISOR products. `VISORTestDoubles` does
re-export Apple's `Observation` module because its peer macros generate
observable types in the importing source file.

## Installation

Add `https://github.com/avdn-dev/VISOR.git` with Swift Package Manager and select
the release you intend to adopt. Use the documentation at that release's tag;
this checkout may include unreleased APIs. To evaluate unreleased changes, add
your VISOR checkout as a local package dependency.

Declare only the products each target imports. A feature that owns a source-backed ViewModel normally needs both observation and architecture:

```swift
.target(
  name: "ProfileFeature",
  dependencies: [
    .product(name: "VISORObservation", package: "visor"),
    .product(name: "VISOR", package: "visor"),
  ]
),
.testTarget(
  name: "ProfileFeatureTests",
  dependencies: [
    "ProfileFeature",
    .product(name: "VISORTesting", package: "visor"),
    .product(name: "VISORTestDoubles", package: "visor"),
  ]
)
```

## Quick start

```swift
import Observation
import SwiftUI
import VISOR
import VISORObservation

struct ProfileSnapshot: Equatable, Sendable {
  var name: String
  var email: String
}

// The producer mutates ordinary State. Consumers receive read-only snapshots.
@MainActor
final class ProfileService {
  @ObservationState
  private(set) var profile: ProfileSnapshot

  init(snapshot: ProfileSnapshot) {
    profile = snapshot
  }

  func refresh() async {
    withMutableProfile { profile in
      profile.name = "Alice"
      profile.email = "alice@example.com"
    }
  }
}

@MainActor
@Observable
@ViewModel
final class ProfileViewModel {
  final class State {
    @Bound(
      source: \ProfileViewModel.profileService.profileSnapshots,
      selecting: \ProfileSnapshot.name)
    private(set) var name = ""

    @Bound(
      source: \ProfileViewModel.profileService.profileSnapshots,
      selecting: \ProfileSnapshot.email)
    private(set) var email = ""
  }

  enum Action { case refresh }

  let profileService: ProfileService

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    switch action {
    case .refresh:
      return refresh.run { [profileService] in
        await profileService.refresh()
      }.completion
    }
  }

  private let refresh = LatestEffect()
}

@LazyViewModel(ProfileViewModel.self)
struct ProfileScreen: View {
  func readyContent(state: ProfileViewModel.State) -> some View {
    ProfileContent(state: state) {
      send(.refresh)
    }
  }
}

struct ProfileContent: View {
  let state: ProfileViewModel.State
  let onRefresh: () -> Void

  var body: some View {
    VStack {
      Text(state.name)
      Text(state.email)
      Button("Refresh", action: onRefresh)
    }
  }
}

let service = ProfileService(
  snapshot: ProfileSnapshot(name: "Loading", email: ""))

ProfileScreen()
  .environment(ProfileViewModel.Factory {
    ProfileViewModel(profileService: service)
  })
```

`@ViewModel` synthesises `let state: State` and `init(profileService:)` here.
The nested `State` type remains authored; the macro supplies its Observation
accessors and routed selectors. For construction rules, see
[State initialisation](Sources/VISOR/VISOR.docc/Architecture.md#state-initialisation).

`ProfileScreen` receives nonoptional State in `readyContent(state:)` only after the source baseline has been reconciled. An authored `body` can decorate generated `content` with titles and toolbar items that render immediately; its optional `state` provides coherent values when ready. `send` rejects dispatch while unavailable. See [View and Content](Sources/VISOR/VISOR.docc/Architecture.md#view-and-content) for the presentation contract. Both projections select from one producer snapshot, so they share one source subscription and revision lane.

Each view implements exactly one `readyContent` method, accepting `state`,
`viewModel`, or both, with optional `bindings`. A view that needs model access
can use `readyContent(viewModel:)` and read `viewModel.state` directly; it does
not need a redundant State parameter. Every form receives prepared values at
the same readiness boundary.

Observation follows the screen's SwiftUI structural identity, not each appearance.
Removing the screen cancels observation and joins teardown before its ViewModel
identity can be claimed again. Explicit scene-pause policies still withdraw
content and reconcile fresh snapshots before restoring it.

## Observation declarations

VISOR accepts exactly four source-backed declaration forms:

```swift
@Bound(source: \FeatureViewModel.service.valueSnapshots)
private(set) var value = Value.empty

@Bound(
  source: \FeatureViewModel.service.featureSnapshots,
  selecting: \FeatureSnapshot.value)
private(set) var value = Value.empty

@Reaction(source: \FeatureViewModel.service.valueSnapshots)
func valueChanged(_ value: Value) { ... }

@Reaction(
  source: \FeatureViewModel.service.featureSnapshots,
  selecting: \FeatureSnapshot.value)
func valueChanged(_ value: Value) async { ... }
```

Source-backed `@Polled`, debounce, and throttle declarations are deliberately absent. Durable latest state belongs in a producer-owned source. Elapsed-time work belongs in an explicitly structured task with an injected `Clock`. Lossless events need an event-specific buffered contract rather than a latest-state source.

## Model-owned bindings and effects

Annotate a single-payload action to keep direct binding syntax while moving
validation and side effects into the ViewModel:

```swift
enum Action {
  @StateBinding(\State.isFocusEnabled)
  case focusChanged(Bool)
}

@discardableResult
func handle(_ action: Action) -> ActionCompletion {
  switch action {
  case .focusChanged(let enabled):
    updateState(\.isFocusEnabled, to: enabled)
  }
  return .completed
}

// Inside readyContent(state:bindings:), using the supplied bindings:
Toggle("Focus Mode", isOn: bindings.isFocusEnabled)
```

Only properties selected by `@StateBinding` actions expose generated bindings;
unannotated fields have no binding selector. Binding writes call the handler
synchronously. `updateState` and source
projections commit without dispatching an action again. Every action handler
returns `ActionCompletion`: `.completed` for synchronous work, or an effect
handle's `.completion` for asynchronous work. Call `await model.handle(.action).wait()`
when completion matters; binding setters discard the value. Each model lazily
retains one stable binding root, including models with authored initialisers.
Raw State writes never dispatch actions.

The same annotation also supports get-only computed State properties:

```swift
// Inside State:
var isPickerPresented: Bool { activeSheet == .picker }

// Inside Action:
@StateBinding(\State.isPickerPresented)
case pickerPresentationChanged(Bool)

// Inside readyContent(state:bindings:), using the supplied bindings:
Toggle("Picker", isOn: bindings.isPickerPresented)
```

The handler updates the underlying stored state. No inverse setter or duplicate
Boolean is needed. Computed selectors cannot be passed to `updateState` or
strict mutation-history expectations. See [Action bindings and managed effects](Sources/VISOR/VISOR.docc/BindingsAndEffects.md).

Retain a `LatestEffect` for replaceable preparation, `SerialEffectQueue` for
ordered events, or `ConcurrentEffects` for independent work. Each submission
returns a handle with `value()`, `result`, and `cancel()`. The receiver API
captures its target weakly and suppresses cancelled or superseded results:

```swift
search.run(for: self) { [service] in
  try await service.search(query)
} receive: { model, result in
  model.applySearchResult(result)
}
```

See [Action bindings and managed effects](Sources/VISOR/VISOR.docc/BindingsAndEffects.md)
for toggling, queue admission, authored initialisers, lifetime, and complete
effect testing.

## One-shot coordination

`OneShotLatch<Value>` shares one winning `Sendable` value with every current and
future waiter. `resolve(_:)` is synchronous, thread-safe, and returns whether
that call won; `wait()` suspends without blocking, and `resolvedValue` provides
a synchronous snapshot. The latch owns no tasks, deadlines, or cancellation
policy. Its owner must resolve it on every terminal path, using `Result` or a
domain-specific outcome when failures or cancellation are possible.

## Testing

Import `VISORTesting` in Swift Testing targets:

```swift
import Testing
import VISORTesting

@Test
@MainActor
func refreshPublishesACompleteStateHistory() async throws {
  let service = ProfileService(
    snapshot: ProfileSnapshot(name: "Before", email: "before@example.com"))
  let sut = ProfileViewModel(profileService: service)

  try await observe(sut) { test in
    await test.perform(.refresh)

    test.expect(\.name, hasExactChanges: ["Alice"])
    test.expect(\.email, alwaysSatisfies: { !$0.isEmpty })
  }
}
```

`observe` starts and reconciles the generated session before entering the body. Each `perform` captures an action baseline, joins the handler's returned completion (or awaits the supplied operation), and fences every participating source before closing the replayable window. `hasExactChanges` matches the complete distinct post-baseline trace; `alwaysSatisfies` checks the baseline and every completed commit.

Generated doubles live in their own product:

```swift
import VISORTestDoubles

@GenerateStub(.sendable)
@GenerateSpy(.sendable)
nonisolated protocol AnalyticsService: Sendable {
  func record(_ event: AnalyticsEvent)
}
```

### Actor-isolated test doubles

For a protocol explicitly isolated to `@MainActor`, `.sendable` generated doubles
retain MainActor ownership instead of introducing nonisolated async witnesses.
Measurement closures and results can remain non-Sendable when they stay on that
actor. Nonisolated Sendable protocols continue to use lock-protected storage.

## Documentation

The DocC catalogue covers architecture, observation, testing, navigation, and
deep linking.

For upgrades, consult the [observation migration guide](MIGRATION_V11.md),
[binding migration guide](MIGRATION_V12.md), and
[action completion and lazy view migration guide](MIGRATION_V13.md).

## Licence

MIT — see [LICENSE](LICENSE).
