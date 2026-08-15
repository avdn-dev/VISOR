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
  nonisolated let source: ObservationSource<SyncSnapshot>

  init(initialSnapshot: SyncSnapshot) {
    let channel = ObservationChannel(initialSnapshot)
    self.channel = channel
    source = channel.source
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

For a public service API, declare the consumer capability directly.
`@ObservationState(initial:)` generates a private channel, a stable source
getter, and a private `publish<Property>(_)` producer operation:

```swift
actor SyncService {
  @ObservationState(initial: SyncSnapshot.initial)
  nonisolated var sync: ObservationSource<SyncSnapshot>

  func apply(_ snapshot: SyncSnapshot) {
    publishSync(snapshot)
  }
}

let service = SyncService()
let source = service.sync
```

The authored property is exactly the read-only public contract. The generated
channel and publisher are private implementation details, and the expansion
has the same runtime shape as the explicit channel example above: one channel,
one stable source, and no task or additional subscription. Publication remains
synchronous. The macro is restricted to classes and actors so copying a
value-type producer cannot accidentally share one channel.

The macro's generic `Value` is inferred from `initial:` before the property is
typechecked. Spell contextual baselines explicitly—for example,
`CustomerInfo?.none` rather than `nil`, and `[Item]()` rather than `[]`.
The macro uses a collision-resistant private backing name and reserves the
private `publish<Property>` method name for its publishing operation.

The value-first spelling remains available for existing implementations whose
canonical producer state is a directly mutated stored value:

```swift
@ObservationState
private(set) var syncSnapshot: SyncSnapshot = .initial

// Generated compatibility projection: syncSnapshotSource
```

That form publishes assignments and in-place value mutations. Prefer the
source-first form at module and protocol boundaries so consumer names describe
domain State rather than the observation mechanism.

A producer does not need `@Observable` merely to expose an observation source.
When its enclosing type does use `@Observable` for other properties, place
`@ObservationIgnored` immediately below `@ObservationState`; Swift otherwise
expands both accessor macros from the same authored declaration:

```swift
@Observable
final class TransitionalService {
  @ObservationState(initial: SyncSnapshot.initial)
  @ObservationIgnored
  var sync: ObservationSource<SyncSnapshot>
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

  var status: ObservationSource<Status> {
    statusChannel.source
  }

  init(configuration: Configuration) throws {
    try configuration.validate()
  }
}
```

Use the same source-first declaration in protocols:

```swift
@GenerateSpy
protocol SyncServicing {
  @ObservationState(initial: SyncSnapshot.initial)
  var sync: ObservationSource<SyncSnapshot> { get }
}
```

The source remains explicit because it is the protocol's consumer capability.
The `initial:` expression supplies generated spies and stubs with a baseline;
it does not constrain how production conformers acquire their initial domain
State. Generated doubles expose `publishSync(_:)` so tests can drive later
snapshots without replacing the stable source.

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
  for await status in dependency.status {
    guard !Task.isCancelled else { return }
    await self?.apply(status)
  }
}
```

The sequence emits the atomic baseline and then the newest pending snapshot.
It is intentionally outside generated ViewModel readiness, acknowledgements,
and `VISORTesting.perform` fences. Use `@Bound` or `@Reaction` inside a
ViewModel. Keep lossless events on an explicitly buffered event contract.

## Source-backed ViewModels

A VISOR ViewModel has this shape:

```swift
@MainActor
@Observable
@ViewModel
final class SyncViewModel {
  final class State {
    @Bound(
      source: \SyncViewModel.service.source,
      selecting: \SyncSnapshot.revision)
    private(set) var revision = 0

    @Bound(
      source: \SyncViewModel.service.source,
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
@Bound(source: \PlayerViewModel.player.currentItem)
private(set) var currentItem = PlayerItem.empty
```

The State field type matches the source snapshot type.

### Select a field from a source snapshot

```swift
@Bound(
  source: \PlayerViewModel.player.snapshot,
  selecting: \PlayerSnapshot.currentItem)
private(set) var currentItem = PlayerItem.empty
```

Several selections from the same source share its baseline, revision lane, and subscription. All baseline projections run before any initial reaction.

### React to a complete source value

```swift
@Reaction(source: \PlayerViewModel.player.currentItem)
private func currentItemChanged(_ item: PlayerItem) {
  updateState(\.title, to: item.title)
}
```

### React to a selected snapshot field

```swift
@Reaction(
  source: \PlayerViewModel.player.snapshot,
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
