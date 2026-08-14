# VISOR

Macro-powered SwiftUI architecture with source-owned observation, structured view lifetime, deterministic state-history testing, and type-safe navigation.

## Why VISOR?

SwiftUI and Observation answer how a view notices a mutation. Product applications still need to decide where durable state lives, which async work owns that state, when a screen is ready, and how tests prove the complete result of an action.

VISOR gives those decisions one explicit shape:

- Producers publish stable, `Sendable` snapshots through `ObservationChannel`; consumers receive the read-only `ObservationSource` capability.
- `@ViewModel`, `@Bound`, and `@Reaction` generate MainActor State routing and cooperative observation recipes.
- `@LazyViewModel` owns the generated observation session, gates content on readiness, and applies scene-lifetime policy.
- `VISORTesting` fences one structured action at a time and checks its complete State mutation history.
- `VISORTestDoubles` generates stubs and spies without pulling the production or testing runtime into a service module.
- `Router` centralises typed navigation, modal presentation, tabs, and deep links.

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

VISOR 11 has four deliberately separate products and no umbrella product:

| Product | Use |
|---|---|
| `VISORObservation` | Isolation-neutral `ObservationChannel` and `ObservationSource` producer contracts |
| `VISOR` | ViewModel, State, SwiftUI, navigation, and architecture macros/runtime |
| `VISORTesting` | Swift Testing integration: `observe`, `perform`, and `expect` |
| `VISORTestDoubles` | `@GenerateStub`, `@GenerateSpy`, and their configuration attributes |

## Installation

Add VISOR with Swift Package Manager:

```swift
dependencies: [
  .package(url: "https://github.com/avdn-dev/VISOR.git", from: "11.0.0"),
]
```

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
import SwiftUI
import VISOR
import VISORObservation

struct ProfileSnapshot: Equatable, Sendable {
  var name: String
  var email: String
}

// The producer owns mutation. Consumers receive only its read-only source.
@MainActor
final class ProfileService {
  private let channel: ObservationChannel<ProfileSnapshot>
  let source: ObservationSource<ProfileSnapshot>

  init(snapshot: ProfileSnapshot) {
    let channel = ObservationChannel(snapshot)
    self.channel = channel
    source = channel.source
  }

  func refresh() async {
    let snapshot = ProfileSnapshot(
      name: "Alice",
      email: "alice@example.com")
    channel.publish(snapshot)
  }
}

@MainActor
@Observable
@ViewModel
final class ProfileViewModel {
  final class State {
    @Bound(
      source: \ProfileViewModel.profileService.source,
      selecting: \ProfileSnapshot.name)
    private(set) var name = ""

    @Bound(
      source: \ProfileViewModel.profileService.source,
      selecting: \ProfileSnapshot.email)
    private(set) var email = ""
  }

  enum Action { case refresh }

  let state = State()
  let profileService: ProfileService

  init(profileService: ProfileService) {
    self.profileService = profileService
  }

  func handle(_ action: Action) async {
    switch action {
    case .refresh:
      await profileService.refresh()
    }
  }
}

@LazyViewModel(ProfileViewModel.self)
struct ProfileScreen: View {
  var content: some View {
    ProfileContent(state: state) {
      Task { await viewModel.handle(.refresh) }
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

`ProfileScreen` does not expose actionable content until the source baseline has been reconciled. Both bindings select from one producer snapshot, so they share one source subscription and revision lane. State is a plain nested `final class`; `@ViewModel` supplies its Observation accessors and routed selectors.

## Observation declarations

VISOR 11 accepts exactly four source-backed declaration forms:

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

Source-backed `@Polled`, debounce, and throttle declarations are deliberately absent from 11.0. Durable latest state belongs in a producer-owned source. Elapsed-time work belongs in an explicitly structured task with an injected `Clock`. Lossless events need an event-specific buffered contract rather than a latest-state source.

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

`observe` starts and reconciles the generated session before entering the body. Each `perform` captures an action baseline, awaits the structured operation, and fences every participating source before closing the replayable window. `hasExactChanges` matches the complete distinct post-baseline trace; `alwaysSatisfies` checks the baseline and every completed commit.

Generated doubles live in their own product:

```swift
import VISORTestDoubles

@GenerateStub(.sendable)
@GenerateSpy(.sendable)
nonisolated protocol AnalyticsService: Sendable {
  func record(_ event: AnalyticsEvent)
}
```

## Documentation

Build the DocC catalogue in Xcode for guides to:

- architecture and source-backed State;
- observation sources, bindings, reactions, and scene policy;
- deterministic observation testing and generated doubles; and
- navigation and deep linking.

Existing v10 consumers should follow [MIGRATION_V11.md](MIGRATION_V11.md). VISOR 11 removes the v10 observation APIs without compatibility shims.

## Licence

MIT — see [LICENSE](LICENSE).
