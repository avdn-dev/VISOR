# Migrating to VISOR 11

VISOR 11 is a semantic observation and testing cutover, not a collection of one-for-one renames. Existing v10 tags remain usable by pinned consumers, but v11 removes the old observation surface without compatibility shims.

Migrate one resolved SwiftPM graph together. Mixed package requirements cannot select both VISOR 10 and VISOR 11 in the same graph.

## 1. Update products and imports

Change the package requirement to `11.0.0` or later and declare products by responsibility:

```swift
.target(
  name: "Feature",
  dependencies: [
    .product(name: "VISORObservation", package: "VISOR"),
    .product(name: "VISOR", package: "VISOR"),
  ]
),
.testTarget(
  name: "FeatureTests",
  dependencies: [
    "Feature",
    .product(name: "VISORTesting", package: "VISOR"),
    .product(name: "VISORTestDoubles", package: "VISOR"),
  ]
)
```

Use the imports that match those dependencies:

```swift
import VISORObservation // channel/source producers
import VISOR            // ViewModel, SwiftUI, and navigation
import VISORTesting     // observe/perform/expect in Swift Testing targets
import VISORTestDoubles // generated stub/spy declarations
```

There is no umbrella product. `VISORTesting` re-exports `VISOR` and Swift Testing; it does not re-export `VISORTestDoubles`.

## 2. Give each producer an explicit source

V10 observed arbitrary `@Observable` properties from the consumer. V11 makes the producer responsible for publishing stable latest-State snapshots.

Before:

```swift
@Observable
final class ProfileService {
  var name = "Alice"
  var status = Status.idle
}
```

After:

```swift
import VISORObservation

struct ProfileSnapshot: Equatable, Sendable {
  var name: String
  var status: Status
}

actor ProfileService {
  private var snapshot: ProfileSnapshot
  private let channel: ObservationChannel<ProfileSnapshot>
  nonisolated let source: ObservationSource<ProfileSnapshot>

  init(snapshot: ProfileSnapshot) {
    self.snapshot = snapshot
    let channel = ObservationChannel(snapshot)
    self.channel = channel
    source = channel.source
  }

  func apply(_ snapshot: ProfileSnapshot) {
    self.snapshot = snapshot
    channel.publish(snapshot)
  }
}
```

Keep the channel private and expose the read-only source. Publish the full stable snapshot synchronously in the same isolation turn as the matching domain mutation. `Sendable` does not prove transitive value semantics; do not publish a snapshot whose contents can mutate later through an alias.

Prefer one source per coherent producer snapshot. If separate performance lanes are necessary, construct them with `ObservationChannel(_:groupedWith:)`. Grouping coordinates session opening and checkpoints but does not batch sequential publications.

## 3. Convert the ViewModel and State shape

Before:

```swift
@Observable
@ViewModel
final class ProfileViewModel {
  @Observable
  final class State {
    @Bound(\ProfileViewModel.service.name)
    var name: String

    nonisolated init(name: String) {
      self._name = name
    }
  }

  private let service: ProfileService
}
```

After:

```swift
@MainActor
@Observable
@ViewModel
final class ProfileViewModel {
  final class State {
    @Bound(
      source: \ProfileViewModel.service.source,
      selecting: \ProfileSnapshot.name)
    private(set) var name = ""
  }

  let state = State()
  let service: ProfileService

  init(service: ProfileService) {
    self.service = service
  }
}
```

The required changes are:

- explicitly add `@MainActor` to the ViewModel;
- keep `@Observable` on the ViewModel;
- remove `@Observable` from nested State;
- make State a plain `final class` held by a stored `let state`;
- use declaration defaults or a normal custom State initialiser; and
- replace positional observation markers with source-backed declarations.

Consumer targets no longer need MainActor-by-default. Public ViewModels require public nested State and a public stored `let state` so the generated conformance remains visible.

VISOR synthesises inert `deinit {}` declarations where needed to avoid the Swift 6.2.4 release-optimiser crash affecting explicitly MainActor macro-expanded classes. Existing unconditional deinitialisers are preserved. Move conditional compilation inside one unconditional deinitialiser body; a conditionally declared `deinit` is rejected because it cannot guarantee the workaround.

## 4. Use only the four source declarations

The accepted v11.0 forms are:

```swift
@Bound(source: \FeatureViewModel.service.valueSource)
private(set) var value = Value.empty

@Bound(
  source: \FeatureViewModel.service.snapshotSource,
  selecting: \FeatureSnapshot.value)
private(set) var value = Value.empty

@Reaction(source: \FeatureViewModel.service.valueSource)
func valueChanged(_ value: Value) { ... }

@Reaction(
  source: \FeatureViewModel.service.snapshotSource,
  selecting: \FeatureSnapshot.value)
func valueChanged(_ value: Value) async { ... }
```

All bindings selecting the same source share a subscription and baseline revision. At startup, every binding projection completes before any initial reaction. Reactions run during initial reconciliation as well as later delivery, and an async reaction is awaited before its snapshot is acknowledged.

## 5. Route State writes

`@ViewModel` generates one mutation route for production Observation and test-history capture.

ViewModel code keeps the familiar form:

```swift
updateState(\.phase, to: .loading)
```

Direct and SwiftUI writes use the selector subscript:

```swift
state[\.query] = "Swift"

@Bindable var state = viewModel.state
TextField("Search", text: $state[\.query])
```

Inside `@LazyViewModel`, use `bindableState[\.query]`.

Selectors cover supported top-level stored fields; they do not create nested or computed history. Keep semantic actions for validation, persistence, analytics, async work, and coupled mutations.

## 6. Replace observation code by intent

The following APIs are removed:

| Removed v10 surface | V11 migration |
|---|---|
| positional `@Bound` | producer `ObservationSource`, then `@Bound(source:)` or `@Bound(source:selecting:)` |
| positional `@Reaction` | `@Reaction(source:)` or `@Reaction(source:selecting:)` |
| `@Polled` / `polledValuesOf` | explicit structured injected-Clock activity; publish durable latest State through a producer-owned channel when needed |
| `valuesOf` | source-backed binding/reaction for durable latest State; an explicit buffered sequence for lossless events |
| `latestValuesOf` | an explicitly owned cancel-previous task where that policy is part of the feature |
| `debouncedValuesOf` / `debouncedBy:` | an explicitly owned injected-Clock debounce task |
| `throttledBy:` | an explicitly owned rate policy at the producer or presentation boundary |
| `startObserving` | generated structured `@LazyViewModel` or `VISORTesting.observe` ownership |

Do not translate an event stream into `ObservationSource` merely to satisfy the API. A source represents stable latest State and may coalesce obsolete snapshots. Lossless events require buffering and event-specific ownership.

Elapsed-time work does not receive an inferred `VISORTesting.perform` fence. Test it with an injected clock and await the domain operation that defines completion.

## 7. Keep @LazyViewModel spelling, adopt its lifetime

The call-site spelling is unchanged:

```swift
@LazyViewModel(
  ProfileViewModel.self,
  observationPolicy: .alwaysObserving)
```

Its semantics are now fully structured. The generated owner reconciles every source before exposing content and cancels and joins the source session when ownership ends. Hoist the annotated view to the stable root of any UI flow whose descendants retain that ViewModel.

Scene policies retain their names:

- `.alwaysObserving` remains ready through every scene phase;
- `.pauseInBackground` pauses in background; and
- `.pauseWhenInactive` runs only while active.

A pause withdraws gated content and cancels the generated session. Reactivation reconciles the latest snapshots before content returns. Keep producer-owned domain activity under its own service lifetime.

## 8. Migrate observation tests

Before:

```swift
try await observing(viewModel) { expect in
  service.count = 42
  try await expect(\.state.count, becomes: 42)
}
```

After:

```swift
import VISORTesting

try await observe(viewModel) { test in
  await test.perform {
    await service.setCount(42)
  }

  test.expect(\.count, hasExactChanges: [42])
}
```

The testing vocabulary is now:

- `observe` starts and reconciles a scoped generated session;
- `perform` captures a baseline, awaits one structured action, fences participating sources, and closes the window;
- `expect(_:hasExactChanges:)` compares the complete distinct post-baseline trace; and
- `expect(_:alwaysSatisfies:)` checks the baseline and every completed commit.

The selector is `\.count`, not `\.state.count`. `hasExactChanges: []` explicitly asserts no distinct change. A closed window is replayable by several expectations; the next `perform` starts a new one.

There is no direct replacement for v10's `eventually:` assertion. Await the operation that owns completion, then assert its complete State history or final invariant. Fire-and-forget work after an action returns is deliberately outside the action window.

Direct and dynamically erased outer reference values cannot participate in strict history matching. Migrate historical assertions to stable value snapshots; production composition may still keep a reference field where its own nested Observation boundary is sufficient.

## 9. Move generated doubles to VISORTestDoubles

V10 exposed test-double macros through `VISOR`. In v11, add the independent `VISORTestDoubles` product and change the declaration-site import:

```swift
import VISORTestDoubles

@GenerateStub(.sendable)
@GenerateSpy(.sendable)
nonisolated protocol AnalyticsService: Sendable {
  func record(_ event: AnalyticsEvent)
}
```

Import `VISORTesting` as well only when that target also uses the observation test DSL. The products intentionally do not re-export each other.

## Removed without shims

VISOR 11 removes these public v10 observation symbols outright:

- `observing` and `Expectation`;
- `valuesOf`, `latestValuesOf`, `debouncedValuesOf`, and `polledValuesOf`;
- `startObserving`;
- positional `@Bound` and `@Reaction` forms;
- `@Polled`; and
- marker-level debounce and throttle overloads.

Because this is a major-version boundary, unavailable tombstones and callable compatibility wrappers are intentionally absent. A consumer that is not ready to migrate should remain pinned to its existing v10 tag until its whole resolved graph can move atomically.
