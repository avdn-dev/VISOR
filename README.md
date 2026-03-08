# VISOR

A Swift macro package that eliminates boilerplate for the **VISOR** (View-Interactor-Service-Observable(View Model)-Router) architecture pattern.

## Requirements

- Swift 6.2+ with `MainActorByDefault` enabled in the consuming target
- iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+ / visionOS 2+

## Installation

Add VISOR to your project via Swift Package Manager:

```swift
dependencies: [
  .package(url: "https://github.com/avdn-dev/VISOR.git", from: "1.0.0"),
]
```

Then add the dependency to your target:

```swift
.target(name: "MyApp", dependencies: ["VISOR"])
```

Importing `VISOR` re-exports `Observation`, so a single import is sufficient.

## Architecture Overview

```
View  -->  ViewModel  -->  Interactor  -->  Service
 |            |                |              |
(UI only) (owns State,    (coordinates  (platform/domain,
 |         dispatches      services,     may depend on
 |         Actions)        use-case      other services)
Factory ------+              logic)
(creates VM   |
 with deps)   |
              |
           Router
        (navigation state,
         parent-child hierarchy,
         deep linking)
```

Dependencies may only point downward: **View → ViewModel / Router → Interactor → Service**. The only exception is services, which may depend on other services.

- **View**: Responsible for UI only. Contains no business logic; as dumb as possible. The `@LazyViewModel` view owns the ViewModel; child views receive state and actions as plain parameters.
- **ViewModel**: The "brain" of the view. Owns a `struct State: Equatable` that is directly mutated. Dispatches user intent via an `Action` enum. Forwards side effects to interactors/services.
- **Router**: Provides uncoupled navigation to any presentation within the app.
- **Factory**: `ViewModelFactory<VM>` injected via `@Environment`, creates ViewModel instances with their dependencies.
- **Interactor (optional)**: Coordinates multiple services and executes business logic for a use case.
- **Service**: Specialized components handling feature state or lower-level concerns (e.g., networking, caching). Platform or domain services providing shared `@Observable` state.

## Quick Start

### 1. Define a ViewModel

```swift
import VISOR

@Observable
@ViewModel
final class ProfileViewModel {
  struct State: Equatable {
    @Bound(\ProfileViewModel.profileService) var name = ""
    @Bound(\ProfileViewModel.profileService) var email = ""
  }

  enum Action {
    case refresh
  }

  var state = State()

  func handle(_ action: Action) async {
    switch action {
    case .refresh:
      await profileService.refresh()
    }
  }

  private let profileService: ProfileService
}
// @ViewModel auto-generates:
// - init(profileService:)
// - ViewModel protocol conformance
// - typealias Factory = ViewModelFactory<ProfileViewModel>
// - startObserving() from @Bound annotations
```

### 2. Create the View

The `@LazyViewModel` view owns the ViewModel. Pass state and actions to child views as plain parameters for easy previewing and testability:

```swift
@LazyViewModel(ProfileViewModel.self)
struct ProfileView: View {
  var content: some View {
    VStack {
      Text(viewModel.state.name)
      Text(viewModel.state.email)
      Button("Refresh") {
        Task { await viewModel.handle(.refresh) }
      }
    }
  }
}
```

### 3. Inject the Factory

```swift
ProfileScreen()
  .environment(ProfileViewModel.Factory { ProfileViewModel(profileService: profileService) })
```

### 4. Routed Factories (Optional)

If a ViewModel needs a `Router`, use a routed factory. The `NavigationContainer` automatically passes the router at creation time:

```swift
let factory: GalleryViewModel.Factory = .routed { (router: Router<AppScene>) in
  GalleryViewModel(router: router, galleryService: galleryService)
}
```

## Macros

### `@ViewModel`

Apply to a ViewModel class to auto-generate:
1. **Memberwise `init`** from stored `let` properties (skipped if an init already exists)
2. **`ViewModel` protocol conformance** via extension
3. **`typealias Factory = ViewModelFactory<ClassName>`**
4. **`startObserving()`** from `@Bound` and `@Reaction` annotations (see below)

```swift
@Observable
@ViewModel
final class CounterViewModel {
  struct State: Equatable {
    @Bound(\CounterViewModel.counterService) var count = 0
  }

  var state = State()

  private let counterService: CounterService
}
```

### `@Bound`

Marks a `var` property **inside `struct State`** for automatic observation binding. The `@ViewModel` macro reads `@Bound` annotations and generates a `startObserving()` method that observes the dependency and assigns changes via `updateState`.

```swift
@Observable
@ViewModel
final class ProfileViewModel {
  struct State: Equatable {
    @Bound(\ProfileViewModel.profileService) var isLoggedIn = false
    @Bound(\ProfileViewModel.profileService) var recentItems: [String] = []
  }

  var state = State()

  private let profileService: ProfileService
}
// Generates observe methods that watch profileService.isLoggedIn
// and profileService.recentItems, calling updateState for each change.
```

The key path argument (`\ProfileViewModel.profileService`) identifies which dependency owns the source property. Use the full root type — `\.dep` can't infer the root inside a struct. The generated code uses `valuesOf()` with the Equatable-constrained overload for automatic deduplication.

### `@Reaction`

Marks a method for automatic observation reaction. The `@ViewModel` macro reads `@Reaction` annotations and generates an observation wrapper that calls the annotated method whenever the observed expression changes.

- **Sync methods**: Uses `valuesOf()` — the method is called for every emitted value.
- **Async methods**: Uses `latestValuesOf()` — previous in-flight handler is cancelled when a new value arrives.

```swift
@Observable
@ViewModel
final class HomeViewModel {
  @Reaction(\Self.deepLinkService.pendingDestination)
  func handleDeepLink(destination: Destination<AppScene>?) {
    guard let destination else { return }
    router.navigate(to: destination)
  }

  private let deepLinkService: DeepLinkService
  private let router: Router<AppScene>
}
// Generates: for every change to deepLinkService.pendingDestination,
// calls self.handleDeepLink(destination:) with the new value.
```

The method must take exactly one parameter whose type matches the observed property. When multiple `@Bound` or `@Reaction` annotations exist, `startObserving()` runs them concurrently in a `withDiscardingTaskGroup`.

### `@LazyViewModel`

Apply to a View struct for single-ViewModel lazy initialization:

```swift
@LazyViewModel(ProfileViewModel.self)
struct ProfileView: View {
  var content: some View {
    Text(viewModel.state.name)
  }
}
```

Generates: `@Environment` factory, `@State` backing, `viewModel` accessor, and full `body` with lazy initialization and observation lifecycle.

For previewing, extract a child view that takes state as a parameter:

```swift
struct ProfileContent: View {
  let state: ProfileViewModel.State
  var body: some View { Text(state.name) }
}

#Preview {
  ProfileContent(state: .init(name: "Alice", email: "alice@example.com"))
}
```

### `@LazyViewModels`

For views needing multiple ViewModels:

```swift
@LazyViewModels(
  ProfileViewModel.self,
  SettingsViewModel.self)
struct DashboardView: View {
  var content: some View {
    TabView {
      // Access via profileViewModel, settingsViewModel
    }
  }
}
```

Property names are derived from ViewModel type names (e.g., `SettingsViewModel` becomes `settingsViewModel`).

### `@Stubbable`

Apply to a protocol to auto-generate a `Stub<Name>` class for previews and tests:

```swift
@Stubbable
protocol ProfileService {
  var name: String { get }
  var isLoggedIn: Bool { get }
  func load() async throws -> [String]
}
// Generates: StubProfileService with canned defaults
```

The generated stub provides sensible defaults for common types:

| Type | Default |
|------|---------|
| `Bool` | `false` |
| `Int`, `UInt`, etc. | `0` |
| `Float`, `Double`, `CGFloat` | `0.0` |
| `Decimal` | `0` |
| `String` | `""` |
| `Data` | `Data()` |
| `[T]`, `Array<T>` | `[]` |
| `[K: V]`, `Dictionary<K, V>` | `[:]` |
| `Set<T>` | `[]` |
| `T?`, `Optional<T>` | `nil` |
| `AsyncStream<T>` | `AsyncStream { $0.finish() }` |

For types without auto-detected defaults (e.g. custom enums), use [`@StubbableDefault`](#stubbabledefault).

Methods with return values get a `<methodName>ReturnValue` property you can set. Void methods generate empty bodies.

> **Limitations**: Protocols with associated types are not supported (compile-time error). Subscripts and static members are skipped with a warning.

### `@Spyable`

Apply to a protocol to auto-generate a `Spy<Name>` test double with call recording:

```swift
@Spyable
protocol ProfileService {
  func load() async throws -> [String]
  func save(_ name: String) async throws
}
// Generates: SpyProfileService
```

The generated spy class is `@Observable` and includes:

- **`<method>CallCount: Int`** — how many times the method was called
- **`<method>Received<Param>: T?`** — last received argument (single-parameter methods)
- **`<method>ReceivedInvocations: [T]`** — all received arguments
- **`<method>ReceivedArguments: (named tuple)?`** — last received arguments (multi-parameter methods)
- **`<method>ReturnValue: T`** — configurable return value
- **`Call` enum** — one case per method, with associated values for arguments
- **`calls: [Call]`** — ordered log of all calls

```swift
let spy = SpyProfileService()
spy.loadReturnValue = ["Alice"]
let names = try await spy.load()
#expect(spy.loadCallCount == 1)
#expect(spy.calls == [.load])
```

Properties use the same default value logic as `@Stubbable`, including `@StubbableDefault` support.

> **Limitations**: Same as `@Stubbable` — no associated types, subscripts/statics skipped.

### `@StubbableDefault`

Provides a custom default value for a protocol property in `@Stubbable` and `@Spyable` generated classes. Use this when the property type has no auto-detected default (e.g. custom enums):

```swift
@Stubbable @Spyable
protocol ContentLoading: AnyObject {
  @StubbableDefault(LoadStatus.idle)
  var status: LoadStatus { get }
}
// StubContentLoading.status defaults to .idle
// SpyContentLoading.status defaults to .idle
```

> **Important**: The expression must be fully qualified — `.idle` alone can't infer the type in attribute context. Use `LoadStatus.idle`, not `.idle`.

## Loadable

`Loadable<Value>` is a standalone enum for per-field loading semantics within `State` structs:

```swift
public enum Loadable<Value> {
  case loading
  case empty
  case loaded(Value)
  case error(String)
}
```

Use it for any field that has independent loading/empty/error states:

```swift
struct State: Equatable {
  var items: Loadable<[Item]> = .loading
  var profile: Loadable<Profile> = .loading
  var filter: Filter = .all  // non-loadable fields coexist naturally
}
```

### Accessors

| Accessor | Type | Description |
|----------|------|-------------|
| `value` | `Value?` | Unwraps `.loaded`, `nil` otherwise |
| `isLoading` | `Bool` | `true` iff `.loading` |
| `isEmpty` | `Bool` | `true` iff `.empty` |
| `isError` | `Bool` | `true` iff `.error` |
| `error` | `String?` | Unwraps error message, `nil` otherwise |
| `map(_:)` | `Loadable<U>` | Transforms the loaded value |
| `flatMap(_:)` | `Loadable<U>` | Transforms the loaded value, returning a new `Loadable` |

`Loadable` conforms to `Equatable`, `Hashable`, and `Sendable` when `Value` does.

## State Management

### `updateState(_:to:)`

Keypath-based mutation with automatic Equatable deduplication. Skips the write (and avoids triggering observation) when the new value equals the current value:

```swift
// Only triggers observation if count actually changed
updateState(\.count, to: newCount)
```

A non-Equatable fallback always writes. The compiler selects the correct overload automatically.

### `handle(_:)`

Define a `handle` method to process actions. The protocol requirement is async, but a sync implementation also satisfies it — implement whichever you need:

```swift
enum Action {
  case refresh
  case delete(Item)
}

// Async — for actions that need side effects
func handle(_ action: Action) async {
  switch action {
  case .refresh:
    updateState(\.items, to: .loading)
    let result = await service.fetchItems()
    updateState(\.items, to: .loaded(result))
  case .delete(let item):
    await service.delete(item)
  }
}

// Or sync — when all actions are pure state mutations
func handle(_ action: Action) {
  switch action {
  case .increment:
    updateState(\.count, to: state.count + 1)
  }
}
```

On concrete types (not existentials), the compiler uses the concrete signature — sync implementations can be called without `await`.

## Observation Utilities

### `valuesOf()`

A free function that returns an `AsyncStream` emitting the current value and re-emitting on every change. Works with protocol existentials where `KeyPath<Self, T>` cannot be used.

```swift
for await value in valuesOf({ service.count }) {
  print(value)
}
```

The Equatable-constrained overload automatically deduplicates consecutive equal values. The compiler prefers this overload when `T: Equatable`.

- On iOS 26+: Backed by `Observations` (SE-0475, transactional did-set semantics)
- On earlier OS: Backed by `ObservationSequence` using `withObservationTracking`

### `latestValuesOf()`

Observes a value and runs an async handler, automatically cancelling any previous in-flight handler when a new value arrives. Useful for side-effect reactions where only the latest value matters.

```swift
await latestValuesOf({ router.pendingDestination }) { destination in
  await handleNavigation(destination)
}
```

This is what `@Reaction` generates for async methods.

## Testing DSL

VISOR includes a lightweight testing DSL (DEBUG only) for asserting on observable ViewModel state.

### `observing(_:body:)`

Starts observation on a ViewModel (calls `startObserving()`), provides an `Expectation` to the body, and cancels observation when the body returns:

```swift
@Test(.timeLimit(.minutes(1)))
func updatesOnServiceChange() async {
  let spy = SpyProfileService()
  let vm = ProfileViewModel(profileService: spy)

  await observing(vm) { expect in
    spy.name = "Alice"
    await expect(\.state.name, equals: "Alice")
  }
}
```

### `Expectation`

The `Expectation<VM>` struct provides three assertion methods, all called via `callAsFunction`:

| Method | Description |
|--------|-------------|
| `expect(\.prop, equals: value)` | Awaits until the property equals the expected value |
| `expect(\.prop, isNot: value)` | Awaits until the property does NOT equal the value |
| `expect(\.prop, satisfies: { ... })` | Awaits until the predicate returns `true` |

Each method observes the ViewModel property and returns as soon as the condition is met. Use Swift Testing's `@Test(.timeLimit(...))` to bound the wait.

## Navigation

VISOR includes a type-safe navigation system.

### NavigationScene

Define all navigation destinations for your app:

```swift
enum AppScene: NavigationScene {
  typealias Push = AppPush
  typealias Sheet = AppSheet
  typealias FullScreen = AppFullScreen
  typealias Tab = AppTab
}
```

Each destination type conforms to a protocol:

| Protocol | Requirements |
|----------|-------------|
| `PushDestination` | `Hashable`, provides `destinationView` |
| `SheetDestination` | `Hashable & Identifiable`, provides `destinationView` |
| `FullScreenDestination` | `Hashable & Identifiable`, provides `destinationView` |
| `TabDestination` | `Hashable` (no view — defined in consumer's TabView) |

```swift
enum AppPush: PushDestination {
  case detail(id: String)
  case settings

  var destinationView: some View {
    switch self {
    case .detail(let id): DetailView(id: id)
    case .settings: SettingsView()
    }
  }
}
```

### Destination

A unified enum for Router navigation and deep link dispatch:

```swift
enum Destination<Scene: NavigationScene> {
  case tab(Scene.Tab)
  case push(Scene.Push)
  case sheet(Scene.Sheet)
  case fullScreen(Scene.FullScreen)
}
```

### Router

Observable router that manages navigation state:

```swift
let router = Router<AppScene>()
router.push(.detail(id: "42"))
router.present(sheet: .preferences)
router.select(tab: .settings)
router.popToRoot()
```

| Method | Description |
|--------|-------------|
| `push(_:)` | Push onto navigation stack |
| `present(sheet:)` | Present a sheet |
| `present(fullScreen:)` | Present a full-screen cover |
| `select(tab:)` | Switch tab (propagates to root) |
| `navigate(to:)` | Unified dispatch via `Destination` |
| `selectAndPush(tab:destination:)` | Switch tab and push in one step |
| `popToRoot()` | Clear navigation stack |
| `dismissSheet()` | Dismiss current sheet |
| `dismissFullScreen()` | Dismiss current full-screen cover |
| `deepLinkOpen(to:)` | Navigate only if router is active |
| `childRouter(for:)` | Cached child router for a tab |
| `childRouter()` | Child router for a modal |

Routers form a parent-child hierarchy. Each child tracks its `level` (depth), `identifierTab`, and `isActive` state. Pass an `os.Logger` to the initializer for debug logging.

### NavigationContainer

Wires a Router to `NavigationStack`, `.sheet`, and `.fullScreenCover`:

```swift
NavigationContainer(parentRouter: router, tab: .home) {
  HomeView()
}
```

Creates a child Router from the parent. Sheets and full-screen covers automatically get their own child NavigationContainer, enabling push navigation within modals.

> **Note**: `fullScreenCover` is only available on iOS (`#if os(iOS)`).

For modals (no tab association):

```swift
NavigationContainer(parentRouter: router) {
  ModalContentView()
}
```

### NavigationButton

Convenience button that reads the Router from the environment:

```swift
NavigationButton<AppScene, _>(push: .detail(id: "1")) {
  Text("Show Detail")
}

NavigationButton<AppScene, _>(sheet: .preferences) {
  Text("Preferences")
}

NavigationButton<AppScene, _>(fullScreen: .onboarding) {
  Text("Start Onboarding")
}
```

**Tip**: Define a typealias to avoid repeating the Scene parameter:

```swift
typealias AppNavigationButton<Label: View> = NavigationButton<AppScene, Label>
// Then: AppNavigationButton(push: .detail(id: "1")) { Text("Go") }
```

## Protocols

| Protocol | Purpose |
|----------|---------|
| `ViewModel` | `@Observable`, requires `State: Equatable` + `state` property + optional `Action`/`handle` + optional `startObserving()` |
| `PushDestination` | Hashable destination with `destinationView` for NavigationStack |
| `SheetDestination` | Hashable & Identifiable destination for `.sheet(item:)` |
| `FullScreenDestination` | Hashable & Identifiable destination for `.fullScreenCover(item:)` |
| `TabDestination` | Hashable tab identifier |
| `NavigationScene` | Groups Push/Sheet/FullScreen/Tab into a single generic parameter |

## When to Use `@ViewModel` vs Protocol Directly

| Scenario | Use |
|----------|-----|
| Simple deps, standard factory | `@ViewModel` macro |
| Custom `init` (e.g., `NSObject`) | `@ViewModel` macro (init skipped, factory still generated) |
| Factory creates interactors | `ViewModel` protocol + manual factory |

## License

MIT — see [LICENSE](LICENSE).
