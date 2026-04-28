# VISOR

Macro-powered architecture for SwiftUI — eliminates observation boilerplate, enforces testability, and provides type-safe navigation.

## Why VISOR?

SwiftUI gives you powerful primitives, but it leaves most feature architecture as an exercise for the app. `@Observable` solved "how does the view notice a value changed?" It did not solve "where should this state come from, who owns the async work, how do I test it, and how do I keep navigation from leaking through the whole feature?"

VISOR is useful when your SwiftUI app has moved past simple local view state and into the usual product-app problems:

- **State is duplicated across layers.** Services already know the source of truth, but screens still need shaped, UI-ready state. VISOR lets a ViewModel declare exactly which service properties it mirrors, then generates the observation, initial seeding, and deduplication code.
- **Feature code accumulates invisible async plumbing.** Without a convention, every screen invents its own observation tasks, cancellation behavior, polling loops, throttling, and "only update if changed" checks. VISOR makes those mechanics declarative so the ViewModel mostly shows product intent.
- **Views become hard to preview and test.** If a SwiftUI view constructs dependencies or reaches into services directly, previews and tests need too much setup. VISOR's View/Content split keeps the owning view responsible for integration while the Content view is plain UI over plain state and action closures.
- **Navigation becomes ambient coupling.** Large SwiftUI apps often spread `NavigationStack`, sheets, deep links, and tab selection through unrelated views. VISOR's `Router` centralises navigation state behind a typed API so features can request navigation without owning destination construction.
- **Testing architecture has a tax.** Protocol-oriented services are testable in theory, but handwritten stubs and spies are repetitive enough that teams skip them. VISOR generates those doubles from the protocol, making the testable path the cheap path.

The package is intentionally opinionated. It is probably overkill for a tiny app, a throwaway prototype, or a screen whose state is entirely local. It is aimed at apps with repeated feature modules, service-backed state, async side effects, previews that need to stay cheap, and tests that should assert behavior without booting the whole dependency graph.

In practice, VISOR gives you a consistent feature shape:

- **`@Bound`** declares which service properties a ViewModel tracks. The macro generates observation loops, deduplication, and initial state — you never write `for await` observation by hand.
- **`@LazyViewModel`** separates view ownership from rendering. The `@LazyViewModel` view gets its ViewModel from a Factory; child views receive state as plain parameters, trivially previewable and testable.
- **Interactors** are optional plain Swift use-case objects for workflows that coordinate multiple services, keeping ViewModels focused on state and user intent.
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

// 1. Service — observable source of truth for the feature
@Observable
final class ProfileService {
  var name = "Alice"
  var email = "alice@example.com"

  func refresh() async {
    // Fetch profile data, then update name/email.
  }
}

// 2. ViewModel — declare state bindings, the macro handles the rest
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

// 3. View — @LazyViewModel view owns the VM, Content is pure UI
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

// 4. Inject the factory at the composition root
let profileService = ProfileService()

ProfileScreen()
  .environment(ProfileViewModel.Factory { ProfileViewModel(profileService: profileService) })
```

When `profileService.name` or `.email` changes, the view updates automatically. `State` is an `@Observable` class for per-field SwiftUI invalidation. `@Bound` properties have no default values — they're initialised from the service at creation time, so state always starts with real data.

`State` initializers use `nonisolated` so previews and generated view-model initializers can construct state without a main-actor hop. Assign the `@Observable` backing storage (`self._name = name`), not the observable property setter (`self.name = name`), inside these initializers.

## What's Included

| Feature | Description |
|---------|-------------|
| `@ViewModel` | Generates init, state, observation, and factory from a class declaration |
| `@Bound` | Observation bindings inside `State` — push-based, from `@Observable` sources |
| `@Polled` | Pull-based polling for non-observable sources (sensors, system APIs) |
| `@Reaction` | Calls a method whenever an observed property changes |
| `@LazyViewModel` | Factory injection, lazy init, and observation lifecycle for views |
| `Loadable<Value>` | Enum for per-field loading/empty/error states within `State` |
| Interactors | Optional use-case layer for coordinating multiple services |
| `Router` | Type-safe navigation with deep linking, externalised view resolution, and modal hierarchies |
| `@Stubbable` / `@Spyable` | Generate test doubles from protocol declarations |
| `observing()` / `Expectation` | Testing DSL for asserting on observable ViewModel state |

All observation macros support `throttledBy:` for rate-limiting rapid-fire updates.

## Documentation

Full API documentation is available at [**avdn-dev.github.io/VISOR**](https://avdn-dev.github.io/VISOR/documentation/visor/), or locally via Xcode (**Product > Build Documentation**):

- **Architecture** — VISOR layers, View/Content pattern, Interactors, Factory injection
- **Observation** — `@Bound`, `@Polled`, `@Reaction`, rate limiting, `valuesOf()`
- **Navigation** — Router, NavigationScene, content-based view resolution, deep linking, NavigationContainer
- **Testing** — `observing()` DSL, `@Stubbable`, `@Spyable`

## License

MIT — see [LICENSE](LICENSE).
