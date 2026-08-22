# Architecture

Compose source-owning services, MainActor ViewModels, structured SwiftUI owners, and pure Content views.

## Layers

VISOR defines five application roles plus a factory boundary:

| Role | Responsibility | Depends on |
|---|---|---|
| **View** | Owns UI integration, renders State, and dispatches actions | ViewModel |
| **ViewModel** | Owns stable UI State, handles actions, projects service snapshots, and coordinates feature navigation | Interactor, Service, Router when routed |
| **Interactor** | Coordinates a named use case across services; optional | Service |
| **Service** | Owns domain or platform state and its natural isolation | Other services |
| **Router** | Owns typed navigation, presentation, top-level destinations, and deep links | — |
| **Factory** | Creates a ViewModel with its dependencies without exposing composition to the View | Composition root |

Dependencies point towards domain and platform capabilities. A service is not required to be MainActor or `@Observable`; source-backed state crosses that boundary through `ObservationSource` snapshots.

Feature navigation follows **View → routed ViewModel → Router**. A View
dispatches an action; its ViewModel decides whether and how to navigate. A
navigation host View still binds `RouterHost`, `RouterStack`, native SwiftUI
containers, and Router state as composition infrastructure, but it does not
move feature navigation decisions into rendering code.

## View and Content

Split an integration-owning view from its plain rendering component:

```swift
enum DashboardLoadFailure: Error {
  case offline
  case unavailable
}

@MainActor
@Observable
@ViewModel
final class DashboardViewModel {
  final class State {
    private(set) var items: Loadable<[Item], DashboardLoadFailure>

    init(items: Loadable<[Item], DashboardLoadFailure> = .loading) {
      self.items = items
    }
  }

  enum Action { case refresh }

  let state = State()

  func handle(_ action: Action) async {
    // Perform the requested work and update State.
  }
}

@LazyViewModel(DashboardViewModel.self)
struct DashboardView: View {
  var content: some View {
    DashboardContent(state: state) { action in
      Task { await viewModel.handle(action) }
    }
  }
}

struct DashboardContent: View {
  let state: DashboardViewModel.State
  let onAction: (DashboardViewModel.Action) -> Void

  var body: some View {
    switch state.items {
    case .loading:
      ProgressView("Loading dashboard")
    case .empty:
      ContentUnavailableView("No Items", systemImage: "tray")
    case .loaded(let items):
      List(items) { item in
        Text(item.name)
      }
    case .failure(let failure):
      VStack {
        switch failure {
        case .offline:
          ContentUnavailableView(
            "You're Offline",
            systemImage: "wifi.slash")
        case .unavailable:
          ContentUnavailableView(
            "Dashboard Unavailable",
            systemImage: "exclamationmark.triangle")
        }

        Button("Try Again") {
          onAction(.refresh)
        }
      }
    }
  }
}

#Preview {
  DashboardContent(
    state: DashboardViewModel.State(
      items: .loaded([Item(name: "Preview")])),
    onAction: { _ in })
}
```

The `@LazyViewModel` view owns integration. The macro resolves its factory, creates the ViewModel lazily, mounts one structured observation owner, and exposes `content` only after all source baselines and immediate reactions are ready.

The Content view is a pure function of State and action closures. It does not resolve factories, subscribe to services, or construct dependencies. This keeps previews and rendering tests small.

When an action can navigate, prefer a routed ViewModel. This keeps navigation
decisions beside the rest of the action handling and makes them testable without
rendering SwiftUI.

Place `@LazyViewModel` at the stable SwiftUI root that should own the ViewModel. If descendants survive a local layout branch, their owner must live above that branch as well.

## Source-backed @ViewModel

A VISOR ViewModel is an explicitly MainActor, observable class with a plain nested State:

```swift
@MainActor
@Observable
@ViewModel
final class CounterViewModel {
  final class State {
    private(set) var count = 0
    private(set) var phase = Phase.idle
  }

  enum Action {
    case increment
  }

  func handle(_ action: Action) {
    switch action {
    case .increment:
      updateState(\.count, to: state.count + 1)
    }
  }
}
```

The shape is intentional:

- `@MainActor` is explicit on every ViewModel; consumer targets do not need MainActor-by-default.
- `@Observable` applies to the ViewModel, not its nested State declaration.
- State is a plain `final class`. `@ViewModel` attaches its MainActor Observation accessors and routed field selectors.
- `state` is a stored `let`, preserving one State identity for SwiftUI ownership and scoped testing. `@ViewModel` synthesises it when safe, or accepts an authored property for custom construction.
- An `Action` enum is optional. Read-only ViewModels use the default `Never` action.

For a public ViewModel, nested State must be public enough to satisfy the generated conformance. A synthesised `state` property and memberwise initialiser inherit that public access.

### Generated surface

For the source-backed shape, `@ViewModel` generates:

1. `ViewModel` and source-backed runtime conformance;
2. `typealias Factory = ViewModelFactory<ClassName>`;
3. State Observation accessors and flat routed selectors;
4. a stable `state` property and memberwise dependency initialiser when State construction is unambiguous;
5. a grouped internal observation recipe for source-backed `@Bound` and `@Reaction` declarations; and
6. a per-instance structured-owner identity token.

Swift 6.2.4 can crash in release optimisation while synthesising destruction for these explicitly MainActor macro-expanded classes. VISOR emits inert `deinit {}` declarations for the ViewModel and State when the user has not written an unconditional deinitialiser. A user-authored unconditional `deinit` is preserved. Conditional deinitialiser declarations are diagnosed because the macro cannot safely guarantee the workaround on every build path.

### State initialisation

When no ViewModel initialiser is authored, `@ViewModel` synthesises one from uninitialised stored `let` dependencies. It also synthesises `state` when State can be constructed from declaration defaults or required `@Bound` fields. Fields selecting the same source are seeded from one coherent current snapshot:

```swift
final class State {
  @Bound(
    source: \ProfileViewModel.service.source,
    selecting: \ProfileSnapshot.name)
  private(set) var name: String

  init(name: String) {
    self.name = name
  }
}

let service: ProfileService
// `@ViewModel` synthesises `let state: State` and `init(service:)`.
```

Write the property and initialiser explicitly when construction needs a derived value, side effect, multiple State initialisers, or any other policy VISOR cannot prove:

```swift
let state: State
let service: ItemService

init(service: ItemService) {
  self.service = service
  state = State(title: service.makeInitialTitle())
}
```

A source-backed `@Bound` field may instead have a placeholder default. The generated owner replaces it from the source baseline before content or an observation test becomes ready.

### Routed mutation

Every supported top-level stored State field is instrumented for normal Observation invalidation and optional test-history capture. ViewModel mutations use the generated selector:

```swift
updateState(\.phase, to: .loading)
```

Explicit State and SwiftUI binding writes use the same route:

```swift
state[\.query] = "Swift"

@Bindable var state = viewModel.state
TextField("Search", text: $state[\.query])
```

The gateway guarantees how a write travels; it does not decide which layer is authorised to make it. Use actions for validation, persistence, analytics, async work, or coupled mutations. Direct bindings are appropriate for genuinely local control input.

Selectors are flat. `\.settings` can route replacement or value write-back of the top-level field; VISOR does not generate `\.settings.theme` history. A nested mutable reference should own its own Observation boundary or be represented by a stable domain snapshot.

## Source projection and reactions

Services expose durable latest State through `ObservationSource`. The ViewModel declares complete-value or selected-value bindings and reactions:

```swift
final class State {
  @Bound(
    source: \ProfileViewModel.service.source,
    selecting: \ProfileSnapshot.name)
  private(set) var name = ""
}

@Reaction(
  source: \ProfileViewModel.service.source,
  selecting: \ProfileSnapshot.status)
private func statusChanged(_ status: Status) async {
  // Runs during initial reconciliation and later delivery.
}
```

Declarations selecting the same source share one subscription and coherent revision lane. At startup, all baseline projections run before any immediate reaction. See [Observation](Observation.md) for the full source contract and deliberate polling/delay boundaries.

## Interactors

An Interactor is an optional plain Swift type representing a named application use case. Introduce one when an action coordinates several services, enforces domain sequencing, is shared across screens, or deserves focused tests without ViewModel State machinery.

Do not add an Interactor when the ViewModel merely forwards one action to one service. Interactors pair naturally with protocols and doubles generated by `VISORTestDoubles`.

## Factory injection

`@ViewModel` generates a `Factory` alias. Construct it at the composition root and inject it through the environment:

```swift
ProfileScreen()
  .environment(ProfileViewModel.Factory {
    ProfileViewModel(profileService: profileService)
  })
```

The view knows that it can request a `ProfileViewModel`; it does not know how the service graph is assembled.

### Dependency ownership and lifetime

VISOR manages ViewModel and observation-session lifetime, not services or
Interactors. The composition root decides their ownership.

A factory-created dependency normally shares the ViewModel's lifetime:

```swift
ProfileViewModel.Factory {
  ProfileViewModel(
    profileService: LiveProfileService(apiClient: apiClient))
}
```

Capturing an existing dependency instead shares the factory owner's lifetime:

```swift
let profileService = LiveProfileService(apiClient: apiClient)

let factory = ProfileViewModel.Factory {
  ProfileViewModel(profileService: profileService)
}
```

If that factory is installed at the application root, the captured service is
effectively application-lived.

Choose ownership according to the state being preserved:

| Required lifetime | Ownership |
|---|---|
| One ViewModel | Construct the dependency inside its factory |
| One multi-screen flow | Retain it with `@State` in the stable flow-owning view |
| One scene or window | Retain it with `@State` in a scene-root view inside `WindowGroup` |
| Whole application process | Construct it at the application composition root and capture it in factories |

`@State` preserves an owned reference across reconstruction of an ordinary
SwiftUI `View`; VISOR source observation does not require it. An
application-root dependency whose identity never changes may be stored as
`let`.

A service publishing an `ObservationSource` must remain alive for every observation session that consumes that
source. Sources of truth and producer-owned domain work should therefore have explicit strong ownership for the
lifetime they require.

Stateless Interactors can normally be constructed inside factories. Do not inject a dependency container into
ViewModels; resolve dependencies at the composition root and pass them explicitly.

### Routed factories

Use a routed factory for every ViewModel that can navigate. `RouterHost`
supplies its local Router when `@LazyViewModel` creates the ViewModel:

```swift
@MainActor
@Observable
@ViewModel
final class GalleryViewModel {
  final class State {}

  enum Action {
    case openPhoto(id: String)
  }

  let state = State()
  private let router: Router<AppScene>

  init(router: Router<AppScene>) {
    self.router = router
  }

  func handle(_ action: Action) {
    switch action {
    case .openPhoto(let id):
      router.push(.detail(id: id))
    }
  }
}

let factory: GalleryViewModel.Factory = .routed {
  (router: Router<AppScene>) in
  GalleryViewModel(router: router)
}
```

Every `@LazyViewModel` view that consumes this factory must render beneath a
``RouterHost`` for the same `AppScene`. A missing or differently typed Router is
a composition error and fails a precondition during ViewModel creation. In a
preview, mount the matching host or inject a non-routed preview factory when the
preview deliberately does not exercise navigation.

The View sends `.openPhoto(id:)`; it does not resolve or call the Router itself.
This is the preferred navigation path for feature code.

## Scene lifetime

The generated owner normally observes through all scene phases. Use `observationPolicy: .pauseInBackground` or `.pauseWhenInactive` when gated presentation or renderer work should stop with the scene.

Pausing revokes readiness and cancels the source session. A later activation reconciles the latest source snapshots before content becomes actionable again. Producer-owned domain activity is independent and must have its own explicit lifetime.

## Loadable

`Loadable<Value, Failure>` models per-field loading semantics inside State while
preserving a feature-specific `Error`:

```swift
enum FeatureLoadFailure: Error, Equatable, Hashable, Sendable {
  case offline
  case unauthorised
}

final class State {
  private(set) var items: Loadable<[Item], FeatureLoadFailure> = .loading
  private(set) var profile: Loadable<Profile, FeatureLoadFailure> = .empty
}
```

| Case | Meaning |
|---|---|
| `.loading` | Work is in progress |
| `.empty` | Work completed without a value |
| `.loaded(Value)` | A value is available |
| `.failure(Failure)` | Work failed with a typed feature error |

Use `value`, `failure`, `isLoading`, `isEmpty`, `isFailure`, `map(_:)`,
`mapFailure(_:)`, and `flatMap(_:)` to work with it. `map` and `flatMap`
preserve the failure type; `mapFailure` translates a lower-layer error into the
feature's vocabulary.

Keep localised display copy in the Content view. Switch over the typed failure
there so the same failure can produce context-appropriate messaging and actions.
