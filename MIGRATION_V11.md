# Migrating to VISOR 11

VISOR 11 is a semantic observation and testing cutover, not a collection of one-for-one renames. Existing v10 tags remain usable by pinned consumers, but v11 removes the old observation surface without compatibility shims.

Migrate one resolved SwiftPM graph together. Mixed package requirements cannot select both VISOR 10 and VISOR 11 in the same graph.

## 1. Update products and imports

Change the package requirement to `11.0.0` or later and declare products by responsibility:

```swift
.target(
  name: "Feature",
  dependencies: [
    .product(name: "VISORObservation", package: "visor"),
    .product(name: "VISOR", package: "visor"),
  ]
),
.testTarget(
  name: "FeatureTests",
  dependencies: [
    "Feature",
    .product(name: "VISORTesting", package: "visor"),
    .product(name: "VISORTestDoubles", package: "visor"),
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

When a class or actor can make one stored property its canonical snapshot, the
equivalent producer is considerably smaller with `@ObservationState`:

```swift
actor ProfileService {
  @ObservationState
  nonisolated private(set) var profile: ProfileSnapshot = .empty

  init(snapshot: ProfileSnapshot) {
    profile = snapshot
  }

  func apply(_ snapshot: ProfileSnapshot) {
    profile = snapshot
  }
}

let source = service.profileSource
```

The macro generates the private channel and stable `profileSource`, and every
assignment or in-place value mutation publishes synchronously. The property
requires an explicit `Sendable` type and initial value. Source-first producers
do not need `@Observable`; if a transitional type retains it for other fields,
place `@ObservationIgnored` immediately below `@ObservationState` on this
property.

For immutable stub defaults, retain one
`ObservationSource<Snapshot>.constant(.empty)` rather than repeating
`ObservationChannel(.empty).source` in computed properties. Each new constant
source has a distinct identity.

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

Existing hand-written `ViewModel` conformances must migrate as well. The v11
protocol is MainActor-isolated and requires routed State conformance, stable
State identity, structured observation ownership, and a generated recipe hook.
The supported migration is to add `@Observable` and `@ViewModel`, then adopt the
State shape above. Do not copy the public underscored requirements into
application code; they are public so macro expansions in downstream modules can
name VISOR's generated-code ABI.

### Supported State declarations

Every field that participates in Observation, selector routing, or test history
must be one ordinary stored `var` with a single identifier. The declaration may
have `@Bound`, but it cannot have another property wrapper or attribute,
`willSet`/`didSet`, a writable computed accessor, `nonisolated`, `lazy`, `weak`,
or `unowned`. Names beginning with `_visor` are reserved. A public field must
use `public private(set)`.

The following declarations remain outside the routed field set:

- stored `let` constants;
- `static` and `class` properties;
- get-only computed properties; and
- declarations explicitly marked `@ObservationIgnored`.

They receive no generated selector and do not appear in `VISORTesting` history.
Declare routed fields separately rather than combining several bindings in one
`var` declaration. `@ObservationIgnored` cannot be combined with
`nonisolated` or `nonisolated(unsafe)` on a mutable State field.

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
| `valuesOf` | source-backed binding/reaction for ViewModel State; direct source iteration for an explicitly owned service task; an explicit buffered sequence for lossless events |
| `latestValuesOf` | an explicitly owned cancel-previous task where that policy is part of the feature |
| `debouncedValuesOf` / `debouncedBy:` | an explicitly owned injected-Clock debounce task |
| `throttledBy:` | an explicitly owned rate policy at the producer or presentation boundary |
| `startObserving` | generated structured `@LazyViewModel` or `VISORTesting.observe` ownership |

Do not translate an event stream into `ObservationSource` merely to satisfy the API. A source represents stable latest State and may coalesce obsolete snapshots. Lossless events require buffering and event-specific ownership.

For service-to-service observation of durable latest State, consume the
producer's source from an explicitly owned task:

```swift
observationTask = Task { @MainActor [weak self, dependency] in
  for await value in dependency.valueSource {
    guard !Task.isCancelled else { return }
    await self?.apply(value)
  }
}
```

It emits the atomic baseline and then the newest pending snapshot, and ends
cooperatively with the consuming task. It is not part of generated ViewModel
readiness, revision acknowledgement, or `VISORTesting.perform` fencing. A
lossless occurrence still requires an explicit event sequence with a buffering
policy selected by its owner.

Elapsed-time work does not receive an inferred `VISORTesting.perform` fence. Test it with an injected clock and await the domain operation that defines completion.

### Own scheduling explicitly

When the feature genuinely needs debounce semantics, own one serial worker and
inject its clock. The newest pending submission wins, an operation that has
already started is allowed to finish, and cancellation is followed by a join at
the feature's lifetime boundary:

```swift
actor SearchDebouncer<C: Clock> where C.Duration == Duration {
  private let clock: C
  private let delay: Duration
  private var pending: (
    deadline: C.Instant,
    query: String,
    load: @Sendable (String) async -> Void
  )?
  private var worker: Task<Void, Never>?
  private var isStopped = false

  init(clock: C, delay: Duration) {
    self.clock = clock
    self.delay = delay
  }

  func submit(
    _ query: String,
    load: @escaping @Sendable (String) async -> Void
  ) {
    guard !isStopped else { return }
    pending = (clock.now.advanced(by: delay), query, load)
    guard worker == nil else { return }

    worker = Task { [weak self] in
      await self?.run()
    }
  }

  func stop() async {
    isStopped = true
    pending = nil
    let worker = worker
    worker?.cancel()
    await worker?.value
    self.worker = nil
  }

  private func run() async {
    while !Task.isCancelled {
      guard let submission = pending else {
        worker = nil
        return
      }
      pending = nil

      do {
        try await clock.sleep(
          until: submission.deadline,
          tolerance: nil)
      } catch is CancellationError {
        break
      } catch {
        assertionFailure("Clock sleep failed: \(error)")
        break
      }

      guard pending == nil else { continue }
      await submission.load(submission.query)
    }
    worker = nil
  }
}
```

Inject `ContinuousClock` in production and a controllable test clock in tests.
Call `stop()` from the owning lifetime after preventing new submissions; do not
invoke it recursively from `load`. A true cancel-previous policy may instead
cancel the active operation, but its implementation must state that contract
and require cooperative cancellation. Polling uses the same ownership rule: the
producer owns the loop and clock, publishes durable snapshots through its
channel, and cancels and joins the loop when its lifetime ends.

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

All test-double declarations moved out of `VISOR`:

- `GenerateStub` and `GenerateSpy`;
- `DefaultValue` and `DefaultReturn`;
- `TestDoubleTrait`; and
- `StubSequence`.

Add `import VISORTestDoubles` to every declaration and use site that names one
of these symbols. Do not import both modules expecting the old VISOR-qualified
declarations; v11 contains only the dedicated product's declarations.

Do not enable MainActor-by-default solely for generated doubles. The macro does
not impose a global actor: explicitly mark UI-bound protocols `@MainActor`, and
use `@concurrent` only for requirements that deliberately leave the caller's
actor. Swift 6.2 targets using approachable concurrency can enable
`NonisolatedNonsendingByDefault` so ordinary async requirements remain on the
caller's actor.

## 10. Type Loadable failures

V10 stored display copy directly in `Loadable` and required only the loaded
value generic:

```swift
private(set) var items: Loadable<[Item]> = .loading

state[\.items] = .error("Unable to load items")
```

V11 makes the failure a feature-specific `Error`:

```swift
enum ItemLoadFailure: Error, Equatable, Sendable {
  case offline
  case unavailable
}

private(set) var items: Loadable<[Item], ItemLoadFailure> = .loading

state[\.items] = .failure(.offline)
```

Swift 6.2 does not support default generic arguments on nominal types, so every
`Loadable` use must supply its failure type. Rename `error` to `failure` and
`isError` to `isFailure`. Use `mapFailure(_:)` when translating a service or
domain error into the feature's failure vocabulary.

Render all four cases explicitly in Content views. Map typed failures to
localised copy and recovery actions at that UI boundary instead of storing
display strings in ViewModel State.

## 11. Audit navigation ownership

V11 makes the mounted navigation hierarchy authoritative. A root `Router`
starts inactive. Calls made on the root to `push`, present, dismiss, or
`popToRoot` target the currently mounted active Router; if no
`NavigationContainer` is active, the action is rejected. Calls made directly on
a child Router remain local to that child.

For an application with one navigation stack, omit the `Tab` associated type
and bind the root Router directly:

```swift
nonisolated enum AppScene: NavigationScene {
  typealias Push = AppPush
  typealias Sheet = AppSheet
  typealias FullScreen = AppFullScreen
  // Tab defaults to NoTabDestination.
}

@State private var router = Router<AppScene>()

NavigationContainer(
  router: router,
  pushContent: { destination in pushView(for: destination) },
  sheetContent: { destination in sheetView(for: destination) },
  fullScreenContent: { destination in fullScreenView(for: destination) }
) {
  RootView()
}
```

Declare `NavigationScene` conformances `nonisolated`. The protocol requires a
`SendableMetatype` so typed destinations and deep-link parsers remain usable
outside MainActor isolation.

Tab-based applications keep using `NavigationContainer(parentRouter:tab:...)`.
Audit code and tests that issue root navigation actions before a container is
mounted; those actions no longer mutate an inactive root Router. Root actions
issued while a tab or modal is active now route to that visible child rather
than always mutating root state.

Deep-link configuration is shared by the whole Router tree. Configure it once
with `configureDeepLinks(scheme:parsers:)`; existing and future child Routers
read the same latest configuration. Code that expected a copied per-child
handler should remove that assumption.

The public parse-only `deepLinkHandler` is removed. Pass a
`DeepLinkRequest` to custom parsers and return `.noMatch`, `.invalid`, or
`.destination(...)`. Open URLs through `openDeepLink(_:)`, whose
`DeepLinkOutcome` distinguishes handled, unconfigured, scheme-mismatched,
unmatched, invalid, and inactive requests. Validate component counts, decode
dynamic values exactly once, and reject malformed identifiers. For HTTPS links,
compare the complete expected host; services must independently enforce
authentication and authorisation for referenced resources.

## 12. Verify the cutover

Before changing the resolved package version, migrate every target in the same
SwiftPM graph. Then verify all of the following:

- production targets import only the products they directly use;
- every ViewModel has explicit `@MainActor`, `@Observable`, `@ViewModel`, plain
  final State, and stable stored `let state` declarations;
- every producer publishes a stable latest-State snapshot and keeps its channel
  private;
- every `Loadable` supplies a typed failure and its Content view renders each
  state deliberately;
- no removed positional marker, observation helper, `startObserving`, or old
  `VISOR` test-double import remains;
- root navigation actions are exercised only with the intended container
  mounted; and
- debug and release builds and tests pass. Release validation is required for
  the Swift 6.2.4 macro-expansion workaround.

## Removed without shims

VISOR 11 removes these public v10 observation symbols outright:

- `observing` and `Expectation`;
- `valuesOf`, `latestValuesOf`, `debouncedValuesOf`, and `polledValuesOf`;
- `startObserving`;
- positional `@Bound` and `@Reaction` forms;
- `@Polled`; and
- marker-level debounce and throttle overloads.

Because this is a major-version boundary, unavailable tombstones and callable compatibility wrappers are intentionally absent. A consumer that is not ready to migrate should remain pinned to its existing v10 tag until its whole resolved graph can move atomically.
