# Observation

Publish stable producer snapshots and project them into readiness-gated ViewModel State.

## Overview

VISOR observation is source-owned. A producer owns an `ObservationChannel<Value>` and exposes its read-only `ObservationSource<Value>`. A `@ViewModel` consumes that source through `@Bound` State fields or `@Reaction` methods.

This explicit capability gives generated production and testing sessions a gap-free baseline, revision ordering, acknowledgements, and finite source fences. A raw `AsyncSequence`, an arbitrary Observation closure, or a hidden task cannot provide that contract by itself.

## Why VISOR has an observation control plane

Swift Observation is excellent for invalidating UI reads, and Combine is useful
for transforming publisher pipelines. Neither API defines the lifecycle contract
VISOR needs when a ViewModel becomes ready:

1. Register every dependency and read its matching baseline without a race.
2. Apply all initial bindings and await all initial reactions before exposing
   content.
3. Process later revisions in order and acknowledge completion.
4. Let tests establish a finite checkpoint and wait until every affected
   reaction has crossed it.

VISOR therefore uses a small observation control plane rather than treating
UI invalidation or publisher delivery as readiness. This is valuable only at
that boundary; ordinary event pipelines and local UI observation should keep
using the simpler native tools that fit them.

`ObservationChannel` and `ObservationSource` are two capabilities over the
same state. The producer retains the channel because it can publish. Consumers
receive a source because they may read or subscribe but cannot impersonate the
producer. A source may be opened by several independent owners. Within one
generated session lane, however, the same source appears only once: all
`@Bound` projections and `@Reaction` handlers for it share a single baseline,
revision order, acknowledgement, and checkpoint.

The model deliberately distinguishes state from events:

```text
durable current value -> ObservationSource -> initial value + latest revisions
occurrence             -> explicit event sequence -> buffering chosen by owner
```

Represent a value as observation State only when a new consumer can start from
the current snapshot and older unprocessed revisions can become obsolete. Do
not model taps, transactions, audit records, or other lossless occurrences as
State.

Import the architecture and observation products where a module declares both producers and ViewModels:

```swift
import VISOR
import VISORObservation
```

## Producer-owned channels

`ObservationChannel` is the writable producer capability. Its `source` property is the stable, copyable consumer capability:

```swift
import VISORObservation

struct SyncSnapshot: Equatable, Sendable {
  var revision: Int
  var status: Status
}

actor SyncService {
  private let channel: ObservationChannel<SyncSnapshot>
  nonisolated let snapshots: ObservationSource<SyncSnapshot>

  init(initialSnapshot: SyncSnapshot) {
    let channel = ObservationChannel(initialSnapshot)
    self.channel = channel
    snapshots = channel.source
  }

  func apply(_ snapshot: SyncSnapshot) {
    // Update the producer's matching domain state in this same actor turn.
    channel.publish(snapshot)
  }
}
```

Publication is synchronous, so an actor can change its domain state and publish the matching snapshot without an intervening suspension. `currentSnapshot()` reads the channel's latest snapshot without opening a consumer session.

Published values must be `Sendable` and must retain stable contents after publication. VISOR does not deep-copy a snapshot or detect mutable aliases hidden inside an otherwise `Sendable` value.

Prefer one snapshot per coherent domain revision rather than one source per `@Bound` field. This avoids torn baselines and lets all projections share one subscription.

### Producer observation State

For a service that owns mutable State, annotate the ordinary domain property.
`@ObservationState` makes assignment the single publishing operation and
generates a stable, read-only observation sequence:

```swift
actor SyncService {
  @ObservationState
  private(set) var sync: SyncSnapshot = .initial

  func apply(_ snapshot: SyncSnapshot) {
    sync = snapshot
  }
}

let service = SyncService()
let current = await service.sync
let snapshots = service.syncSnapshots
```

The authored scalar is the canonical producer State: direct assignment and
in-place value mutation both publish the resulting complete value
synchronously. The macro synthesises one private channel and a nonisolated
`ObservationSource` peer. It creates no task or additional subscription.
Classes and actors are supported; value-type producers are rejected because a
copied producer must not accidentally share one channel.

The default peer uses `Snapshots` because each element is a complete durable
State replacement. Use `Values` for genuinely scalar State, or a custom domain
plural when that is clearer at call sites:

| Declaration | Generated consumer sequence |
| --- | --- |
| `@ObservationState var playback = ...` | `playbackSnapshots` |
| `@ObservationState(observedAs: .values) var revision = ...` | `revisionValues` |
| `@ObservationState(observedAs: .named("permissionStatuses")) var permissions = ...` | `permissionStatuses` |

Custom names must be static Swift identifiers and must not collide with another
member. Prefer the default unless a domain plural is materially clearer; the
argument is an API naming decision, not a description of the macro's storage.

A declaration may initialise State normally or leave it for the enclosing
initialiser:

```swift
@ObservationState
private(set) var sync: SyncSnapshot

init(initial: SyncSnapshot) {
  sync = initial
}
```

A producer does not need `@Observable` merely to expose an observation source.
When its enclosing type does use `@Observable` for other properties, place
`@ObservationIgnored` immediately below `@ObservationState`; Swift otherwise
expands both accessor macros from the same authored declaration. The generated
accessors still register reads and mutations with Apple Observation, so the
canonical scalar remains observable by SwiftUI as well as VISOR:

```swift
@Observable
final class TransitionalService {
  @ObservationState
  @ObservationIgnored
  private(set) var sync: SyncSnapshot = .initial
}
```

Use `ObservationSource.constant(_:)` for one retained immutable fallback,
such as generated test-double state. Do not recreate a constant source from a
computed property because each call would create another source identity.

Keep the explicit channel form as an escape hatch when a producer cannot use
the storage macro. In particular, the current Swift compiler can miscompile
partial cleanup when a class with macro-owned storage throws before
initialisation completes:

```swift
final class ThrowingProducer {
  private let statusChannel = ObservationChannel(Status.idle)

  private(set) var currentStatus: Status = .idle {
    didSet { statusChannel.publish(currentStatus) }
  }

  nonisolated var statusSnapshots: ObservationSource<Status> {
    statusChannel.source
  }

  init(configuration: Configuration) throws {
    try configuration.validate()
  }
}
```

Protocols declare the same domain State property. `initial:` optionally
supplies baseline metadata for generated spies and stubs, where a protocol
requirement cannot contain a stored initial value. Known standard types infer a
baseline; custom types can instead use `@DefaultValue`.
`@ObservationStateRequirements` synthesises the matching nonisolated
requirements from those properties:

```swift
@GenerateSpy
@ObservationStateRequirements
protocol SyncServicing {
  @ObservationState(initial: SyncSnapshot.initial)
  var sync: SyncSnapshot { get }
}

let spy = SpySyncServicing()
spy.sync = .connected
// spy.syncSnapshots publishes .connected automatically.
```

The protocol expands conceptually to `sync` plus a get-only `syncSnapshots`.
`@ObservationStateRequirements` runs once at the type level so Swift
incorporates the generated sequence requirements into its existential witness
layout. The property annotation still owns the domain declaration and naming;
concrete classes and actors do not need the protocol annotation.
The baseline does not constrain how production conformers acquire their initial
domain State. Generated doubles make the scalar mutable for test control, and
their setter uses the same automatic publication contract as production code.
If a requested double cannot infer a custom State baseline, generation fails
with a diagnostic instead of changing the production protocol's semantics.

### Related performance lanes

When one producer needs separate channels for performance, construct later lanes with `groupedWith:`:

```swift
let lifecycle = ObservationChannel(LifecycleSnapshot.initial)
let metering = ObservationChannel(
  MeteringSnapshot.silent,
  groupedWith: lifecycle)
```

Grouping makes session opening and checkpoints atomic relative to each individual channel operation. It does not turn sequential `publish` calls into one batch transaction. Use one snapshot when fields must share one publication revision.

### Service-to-service observation

An explicitly owned service task can consume another producer's durable State
through the producer's source. `ObservationSource` is itself an
`AsyncSequence`, so no intermediate sequence property is required:

```swift
observationTask = Task { @MainActor [weak self, dependency] in
  do {
    for try await status in dependency.statusSnapshots {
      guard !Task.isCancelled else { return }
      await self?.apply(status)
    }
  } catch {
    await self?.handleObservationFailure(error)
  }
}
```

The sequence emits the atomic baseline and then the newest pending snapshot.
Cancellation ends it normally; source termination and runtime failures throw
`ObservationSourceError`. Each iterator is deliberately single-consumer and
does not conform to `Sendable`. A source error is terminal for that channel;
stop the consuming task and replace the owning producer/channel if the feature
can recover. Opening a new iterator on the same source throws the same error.
It is intentionally outside generated ViewModel readiness, acknowledgements,
and `VISORTesting.perform` fences. Use `@Bound` or `@Reaction` inside a
ViewModel. Keep lossless events on an explicitly buffered event contract.

### Testing producer snapshots

For durable producer State, trigger the operation and use `VISORTesting`'s
`waitUntil` helper to wait for the required snapshot:

```swift
@Test(.timeLimit(.minutes(1)))
func `Refresh publishes ready status`() async throws {
  service.refresh()

  try await service.statusSnapshots.waitUntil {
    $0.phase == .ready
  }
}
```

Each iterator opens with the source's atomic current baseline, so starting the
wait after the operation does not introduce a registration race. The helper
uses the source's standard `AsyncSequence` iteration and needs no polling,
sleeps, `Task.yield()`, or Apple Observation. It has no private deadline: apply
a Swift Testing time limit so cancellation bounds a missing publication. Use
`VISORTesting.observe` instead for a ViewModel's routed State history.

## Source-backed ViewModels

A VISOR ViewModel has this shape:

```swift
@MainActor
@Observable
@ViewModel
final class SyncViewModel {
  final class State {
    @Bound(
      source: \SyncViewModel.service.syncSnapshots,
      selecting: \SyncSnapshot.revision)
    private(set) var revision = 0

    @Bound(
      source: \SyncViewModel.service.syncSnapshots,
      selecting: \SyncSnapshot.status)
    private(set) var status = Status.idle
  }

  let state = State()
  let service: SyncService

  init(service: SyncService) {
    self.service = service
  }
}
```

The outer class must explicitly spell `@MainActor`, `@Observable`, and `@ViewModel`. Its nested `State` is a plain `final class`, not an `@Observable` class, and is held by a stable stored `let state`. `@ViewModel` supplies State's MainActor Observation accessors, routed selectors, recipe, and factory.

State fields may have declaration defaults or be assigned by a custom State initialiser. Source projections replace those placeholders during startup before a generated SwiftUI owner exposes content or `VISORTesting.observe` enters its body.

## Accepted declaration forms

VISOR accepts exactly four source-backed forms.

### Bind a complete source value

```swift
@Bound(source: \PlayerViewModel.player.currentItemSnapshots)
private(set) var currentItem = PlayerItem.empty
```

The State field type matches the source snapshot type.

### Select a field from a source snapshot

```swift
@Bound(
  source: \PlayerViewModel.player.playerSnapshots,
  selecting: \PlayerSnapshot.currentItem)
private(set) var currentItem = PlayerItem.empty
```

Several selections from the same source share its baseline, revision lane, and subscription. All baseline projections run before any initial reaction.

### React to a complete source value

```swift
@Reaction(source: \PlayerViewModel.player.currentItemSnapshots)
private func currentItemChanged(_ item: PlayerItem) {
  updateState(\.title, to: item.title)
}
```

### React to a selected snapshot field

```swift
@Reaction(
  source: \PlayerViewModel.player.playerSnapshots,
  selecting: \PlayerSnapshot.currentItem)
private func currentItemChanged(_ item: PlayerItem) async {
  await prepareArtwork(for: item)
}
```

A reaction takes exactly one parameter matching the complete or selected value. Sync and async reactions are supported. Handlers within one coherent source lane run serially in deterministic declaration order; an async handler is awaited before that snapshot is acknowledged. A newer latest-state snapshot does not implicitly cancel an active handler.

`@Reaction` runs during initial reconciliation as well as later publications. Use it for work required to make the ViewModel ready, not as a lossless event listener.

## State mutation and bindings

`@ViewModel` routes supported top-level State mutations through one generated gateway. Use `updateState` from the ViewModel:

```swift
updateState(\.status, to: .loading)
```

Direct State and SwiftUI writes use the generated selector subscript:

```swift
state[\.query] = "Swift"

@Bindable var state = viewModel.state
TextField("Search", text: $state[\.query])
```

Inside a `@LazyViewModel` view, the generated convenience has the same shape:

```swift
TextField("Search", text: bindableState[\.query])
```

This keeps production Observation invalidation and test-history capture on the same synchronous route. Selectors are generated only for supported top-level stored fields whose getter is at least `fileprivate`; they do not recursively expose nested members.

## Structured SwiftUI ownership

`@LazyViewModel` mounts one structured observation owner for its ViewModel identity. It reconciles every baseline projection and immediate reaction before exposing `content`, supervises the running source lanes, and requests cancellation and joined teardown when ownership ends.

Hoist `@LazyViewModel` to the stable SwiftUI root of a longer-lived flow. Mounting two owners for the same ViewModel identity is rejected rather than creating duplicate subscriptions.

### Readiness and infrastructure failure

While an enabled owner is reconciling its initial source snapshots and immediate reactions, the generated host presents labelled progress instead of exposing partial feature content. A terminal observation-infrastructure failure withdraws feature content and presents a generic unavailable state; its technical cause is recorded in the VISOR system log rather than displayed to the user.

These failures mean VISOR can no longer guarantee a coherent State. Examples include a readiness deadline exceeded by an initial asynchronous reaction, unexpected source termination, duplicate production ownership, or an internal protocol violation. Ordinary cancellation and scene-policy pausing are lifecycle events, not failures.

Domain failures such as an unavailable network request belong in ViewModel State and feature content, for example as a typed `Loadable.failure`. VISOR does not expose a manual infrastructure retry. With a pause policy, a later scene reactivation starts a fresh generation as part of the existing lifecycle, but that cannot repair a terminal source or programming error; a duplicate owner remains invalid until the competing mount is removed.

### Scene policy

Choose how the generated owner responds to scene phase:

```swift
// Runs through active, inactive, and background phases.
@LazyViewModel(ProfileViewModel.self)

// Pauses only in the background.
@LazyViewModel(
  DashboardViewModel.self,
  observationPolicy: .pauseInBackground)

// Runs only while active.
@LazyViewModel(
  SensorViewModel.self,
  observationPolicy: .pauseWhenInactive)
```

The default is `.alwaysObserving`. A pause policy revokes readiness, withdraws gated content, and cancels the generated source session. On reactivation, a fresh generation reconciles the latest snapshots before content returns. Use a pause policy when the gated content owns high-frequency renderer or presentation work that should also stop off-screen.

Producer-owned domain work has its own lifetime. VISOR does not infer that a service should stop because one view paused.

## Deliberate boundaries

There is no source-backed `@Polled`, `throttledBy:`, or `debouncedBy:` declaration.

- Durable latest domain state belongs in an `ObservationChannel`/`ObservationSource` owned by its producer.
- Elapsed-time presentation or service work belongs in an explicitly structured task using an injected `Clock`.
- Operation completion should be awaited directly.
- Lossless events need an explicitly buffered event sequence or callback with event-specific ownership.

Those forms are not automatically source-fenced. VISOR only guarantees readiness and `perform` fencing for immediate generated `@Bound` and `@Reaction` work over participating sources.
