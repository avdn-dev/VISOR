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
| **Router** | Owns typed navigation, presentation, tabs, and deep links | — |
| **Factory** | Creates a ViewModel with its dependencies without exposing composition to the View | Composition root |

Dependencies point towards domain and platform capabilities. A service is not required to be MainActor or `@Observable`; source-backed state crosses that boundary through `ObservationSource` snapshots.

Feature navigation follows **View → routed ViewModel → Router**. A View
dispatches an action; its ViewModel decides whether and how to navigate. A
navigation host View still binds `NavigationContainer`, `TabView`, and Router
state as composition infrastructure, but it does not move feature navigation
decisions into rendering code.

## View and Content

Split an integration-owning view from its plain rendering component:

```swift
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
    List(state.items.value ?? []) { item in
      Text(item.name)
    }
  }
}

#Preview {
  DashboardContent(
    state: .init(items: .loaded([Item(name: "Preview")])),
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

A VISOR 11 ViewModel is an explicitly MainActor, observable class with a plain nested State:

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

  let state = State()

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
- `state` is a stored `let`, preserving one State identity for SwiftUI ownership and scoped testing.
- An `Action` enum is optional. Read-only ViewModels use the default `Never` action.

For a public ViewModel, nested State and the stored `state` property must also be public enough to satisfy the generated conformance.

### Generated surface

For the source-backed shape, `@ViewModel` generates:

1. `ViewModel` and source-backed runtime conformance;
2. `typealias Factory = ViewModelFactory<ClassName>`;
3. State Observation accessors and flat routed selectors;
4. a grouped internal observation recipe for source-backed `@Bound` and `@Reaction` declarations; and
5. a per-instance structured-owner identity token.

Swift 6.2.4 can crash in release optimisation while synthesising destruction for these explicitly MainActor macro-expanded classes. VISOR emits inert `deinit {}` declarations for the ViewModel and State when the user has not written an unconditional deinitialiser. A user-authored unconditional `deinit` is preserved. Conditional deinitialiser declarations are diagnosed because the macro cannot safely guarantee the workaround on every build path.

### State initialisation

State fields keep ordinary declaration defaults or values assigned by a custom initialiser:

```swift
final class State {
  private(set) var title: String
  private(set) var items: Loadable<[Item]> = .loading

  init(title: String) {
    self.title = title
  }
}

let state: State

init(title: String, service: ItemService) {
  state = State(title: title)
  self.service = service
}
```

A source-backed `@Bound` field may also have a placeholder default. The generated owner replaces it from the source baseline before content or an observation test becomes ready.

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

```swift
protocol SessionInteractor {
  func signIn(email: String, password: String) async throws -> User
}

final class LiveSessionInteractor: SessionInteractor {
  private let authService: AuthService
  private let profileService: ProfileService
  private let analyticsService: AnalyticsService

  init(
    authService: AuthService,
    profileService: ProfileService,
    analyticsService: AnalyticsService
  ) {
    self.authService = authService
    self.profileService = profileService
    self.analyticsService = analyticsService
  }

  func signIn(email: String, password: String) async throws -> User {
    let session = try await authService.signIn(
      email: email,
      password: password)
    let user = try await profileService.loadProfile(for: session.userID)
    analyticsService.track(.signedIn(user.id))
    return user
  }
}
```

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

### Routed factories

Use a routed factory for every ViewModel that can navigate. `NavigationContainer`
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

The View sends `.openPhoto(id:)`; it does not resolve or call the Router itself.
This is the preferred navigation path for feature code.

## Scene lifetime

The generated owner normally observes through all scene phases. Use `observationPolicy: .pauseInBackground` or `.pauseWhenInactive` when gated presentation or renderer work should stop with the scene.

Pausing revokes readiness and cancels the source session. A later activation reconciles the latest source snapshots before content becomes actionable again. Producer-owned domain activity is independent and must have its own explicit lifetime.

## Loadable

`Loadable<Value>` models per-field loading semantics inside State:

```swift
final class State {
  private(set) var items: Loadable<[Item]> = .loading
  private(set) var profile: Loadable<Profile> = .empty
}
```

| Case | Meaning |
|---|---|
| `.loading` | Work is in progress |
| `.empty` | Work completed without a value |
| `.loaded(Value)` | A value is available |
| `.error(String)` | Work failed with a displayable message |

Use `value`, `isLoading`, `isEmpty`, `isError`, `error`, `map(_:)`, and `flatMap(_:)` to work with it. Conditional `Equatable`, `Hashable`, and `Sendable` conformances follow the wrapped value.
