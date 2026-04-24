# VISOR

Macro-powered architecture for SwiftUI — eliminates observation boilerplate, enforces testability, and provides type-safe navigation.

## Why VISOR?

`@Observable` solved reactivity. It didn't solve architecture.

A typical SwiftUI feature still requires you to manually wire observation loops for every service property, manage task lifecycles and deduplication, create test doubles for every protocol, and couple views to their navigation destinations. Multiply that by every feature in your app.

VISOR provides opinionated answers with macros that eliminate the boilerplate:

- **`@Bound`** declares which service properties a ViewModel tracks. The macro generates observation loops, deduplication, and initial state — you never write `for await` observation by hand.
- **`@LazyViewModel`** separates view ownership from rendering. The `@LazyViewModel` view gets its ViewModel from a Factory; child views receive state as plain parameters, trivially previewable and testable.
- **`Router`** centralises navigation behind a type-safe API with deep linking, modal hierarchies, and tab management built in.
- **`@Stubbable` / `@Spyable`** generate test doubles from protocol declarations — stubs with sensible defaults, spies with call recording.

## Requirements

- Swift 6.2+ with `MainActorByDefault` enabled in the consuming target
- iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+ / visionOS 2+

## Installation

Add VISOR to your project via Swift Package Manager:

```swift
dependencies: [
  .package(url: "https://github.com/avdn-dev/VISOR.git", from: "9.0.0"),
]
```

Then add the dependency to your target:

```swift
.target(name: "MyApp", dependencies: ["VISOR"])
```

Importing `VISOR` re-exports `Observation`, so a single import is sufficient.

## Quick Start

```swift
import VISOR

// 1. ViewModel — declare state bindings, the macro handles the rest
@Observable
@ViewModel
final class ProfileViewModel {
  @Observable
  final class State {
    @Bound(\ProfileViewModel.profileService.name) var name: String
    @Bound(\ProfileViewModel.profileService.email) var email: String

    nonisolated init(name: String, email: String) {
      self._name = name
      self._email = email
    }
  }

  enum Action { case refresh }

  func handle(_ action: Action) async {
    switch action {
    case .refresh: await profileService.refresh()
    }
  }

  private let profileService: ProfileService
}
// @ViewModel generates: init(profileService:), var state (initialised from service),
// startObserving() that watches profileService, and typealias Factory.

// 2. View — @LazyViewModel view owns the VM, Content is pure UI
@LazyViewModel(ProfileViewModel.self)
struct ProfileScreen: View {
  var content: some View {
    ProfileContent(state: viewModel.state) {
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

#Preview {
  ProfileContent(state: .init(name: "Alice", email: "alice@example.com")) {}
}

// 3. Inject the factory at the composition root
ProfileScreen()
  .environment(ProfileViewModel.Factory { ProfileViewModel(profileService: profileService) })
```

When `profileService.name` or `.email` changes, the view updates automatically. `State` is an `@Observable` class for per-field SwiftUI invalidation. `@Bound` properties have no default values — they're initialised from the service at creation time, so state always starts with real data.

## What's Included

| Feature | Description |
|---------|-------------|
| `@ViewModel` | Generates init, state, observation, and factory from a class declaration |
| `@Bound` | Observation bindings inside `State` — push-based, from `@Observable` sources |
| `@Polled` | Pull-based polling for non-observable sources (sensors, system APIs) |
| `@Reaction` | Calls a method whenever an observed property changes |
| `@LazyViewModel` | Factory injection, lazy init, and observation lifecycle for views |
| `Loadable<Value>` | Enum for per-field loading/empty/error states within `State` |
| `Router` | Type-safe navigation with deep linking, externalised view resolution, and modal hierarchies |
| `@Stubbable` / `@Spyable` | Generate test doubles from protocol declarations |
| `observing()` / `Expectation` | Testing DSL for asserting on observable ViewModel state |

All observation macros support `throttledBy:` for rate-limiting rapid-fire updates.

## Documentation

Full API documentation is available at [**avdn-dev.github.io/VISOR**](https://avdn-dev.github.io/VISOR/documentation/visor/), or locally via Xcode (**Product > Build Documentation**):

- **Architecture** — VISOR layers, View/Content pattern, Factory injection
- **Observation** — `@Bound`, `@Polled`, `@Reaction`, rate limiting, `valuesOf()`
- **Navigation** — Router, NavigationScene, content-based view resolution, deep linking, NavigationContainer
- **Testing** — `observing()` DSL, `@Stubbable`, `@Spyable`

## License

MIT — see [LICENSE](LICENSE).
