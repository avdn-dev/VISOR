# Architecture

The VISOR layers, View/Content pattern, and Factory injection.

## The Layers

VISOR defines five roles. Each role has a single responsibility and dependencies only point downward.

| Layer | Responsibility | Depends On |
|-------|---------------|------------|
| **View** | Renders UI. No business logic. | ViewModel |
| **ViewModel** | Owns state, dispatches actions, forwards side effects. | Interactor, Service |
| **Interactor** | Coordinates multiple services for a use case. Optional. | Service |
| **Service** | Platform or domain concern (networking, caching, auth). `@Observable`. | Other Services |
| **Router** | Navigation state, parent-child hierarchy, deep linking. | — |

The **Factory** (`ViewModelFactory<VM>`) bridges the gap between the View and ViewModel layers. It's injected via `@Environment` so views don't know how their ViewModel is created.

## View / Content Pattern

VISOR splits UI into two roles:

- The **`@LazyViewModel` view** owns the ViewModel. It's the integration point — it wires the factory, starts observation, and passes state to the Content. This can be a full screen, a section of a screen, or any component that needs its own ViewModel.
- The **Content** is a pure function of state. It takes state and action closures as plain parameters. No factories, no observation, no services. This makes it trivially previewable and testable.

```swift
// @LazyViewModel view — owns the ViewModel
@LazyViewModel(DashboardViewModel.self)
struct DashboardView: View {
  var content: some View {
    DashboardContent(state: viewModel.state) { action in
      Task { await viewModel.handle(action) }
    }
  }
}

// Content — pure UI
struct DashboardContent: View {
  let state: DashboardViewModel.State
  let onAction: (DashboardViewModel.Action) -> Void

  var body: some View {
    List(state.items.value ?? []) { item in
      Text(item.name)
    }
  }
}

// Previewable with static data — no factory needed
#Preview {
  DashboardContent(
    state: .init(items: .loaded([Item(name: "Preview")])),
    onAction: { _ in }
  )
}
```

## @ViewModel Macro

Apply `@Observable` and `@ViewModel` to a class to generate:

1. **Memberwise `init`** from stored `let` properties (skipped if you write your own)
2. **`var state`** with observation tracking (generated when `@Bound` or `@Polled` properties exist)
3. **`startObserving()`** from `@Bound`, `@Polled`, and `@Reaction` annotations
4. **`typealias Factory = ViewModelFactory<ClassName>`**
5. **`ViewModel` protocol conformance** via extension

```swift
@Observable
@ViewModel
final class CounterViewModel {
  struct State: Equatable {
    var count = 0
  }

  enum Action { case increment }

  func handle(_ action: Action) {
    switch action {
    case .increment: updateState(\.count, to: state.count + 1)
    }
  }
}
```

### State and Actions

Every ViewModel requires a nested `struct State: Equatable`. Actions are optional — omit the `Action` enum for read-only ViewModels.

Mutate state via `updateState(_:to:)`, which skips the write when the new value equals the current one (preventing unnecessary observation triggers):

```swift
updateState(\.count, to: newCount) // no-op if count == newCount
```

The `handle(_:)` method can be sync or async. The protocol requires `async`, but a sync implementation also satisfies it — implement whichever you need.

### Init-from-Service

When `@Bound` or `@Polled` properties exist in State, the generated init reads their initial values from the service:

```swift
struct State: Equatable {
  @Bound(\ProfileViewModel.profileService.name) var name: String
  @Bound(\ProfileViewModel.profileService.email) var email: String
  var filter: Filter = .all  // non-bound properties still use defaults
}

private let profileService: ProfileService

// Generated init:
// init(profileService: ProfileService) {
//   self.profileService = profileService
//   self._state = State(name: profileService.name, email: profileService.email)
// }
```

`@Bound` properties cannot have default values — they're always initialised from the service so state starts with real data, never stale placeholders. Non-bound properties coexist naturally and keep their defaults.

## Factory Injection

`@ViewModel` generates a `Factory` typealias. Create the factory at your composition root and inject it via `@Environment`:

```swift
// At the composition root
ProfileScreen()
  .environment(ProfileViewModel.Factory {
    ProfileViewModel(profileService: profileService)
  })
```

### Routed Factories

If a ViewModel needs a ``Router``, use a routed factory. The ``NavigationContainer`` automatically passes the router at creation time:

```swift
let factory: GalleryViewModel.Factory = .routed { (router: Router<AppScene>) in
  GalleryViewModel(router: router, galleryService: galleryService)
}
```

## When to Use @ViewModel vs Protocol

| Scenario | Use |
|----------|-----|
| Standard ViewModel with service dependencies | `@ViewModel` macro |
| Custom `init` (e.g., `NSObject` subclass) | `@ViewModel` macro (init skipped, factory still generated) |
| Factory creates interactors or has complex setup | `ViewModel` protocol + manual factory |

## Loadable

`Loadable<Value>` is a standalone enum for per-field loading semantics within State:

```swift
struct State: Equatable {
  var items: Loadable<[Item]> = .loading
  var profile: Loadable<Profile> = .loading
  var filter: Filter = .all
}
```

| Case | Description |
|------|-------------|
| `.loading` | Data is being fetched |
| `.empty` | Fetch completed, no data |
| `.loaded(Value)` | Data available |
| `.error(String)` | Fetch failed with message |

Accessors: `value`, `isLoading`, `isEmpty`, `isError`, `error`, `map(_:)`, `flatMap(_:)`.

Conforms to `Equatable`, `Hashable`, and `Sendable` when `Value` does.
