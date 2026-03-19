# Navigation

Type-safe navigation with Router, NavigationScene, deep linking, and modal hierarchies.

## Overview

VISOR's navigation system centralizes all navigation state in a ``Router`` object, decoupling views from their destinations. Views never directly present other views — they tell the Router what to show, and ``NavigationContainer`` handles the SwiftUI wiring.

## Defining Destinations

Start by defining destination types that conform to VISOR's protocols:

```swift
enum AppPush: PushDestination {
  case detail(id: String)
  case settings

  var destinationView: some View {
    switch self {
    case .detail(let id): DetailScreen(id: id)
    case .settings: SettingsScreen()
    }
  }
}

enum AppSheet: SheetDestination {
  case preferences
  case share(item: Item)

  var id: Self { self }

  var destinationView: some View {
    switch self {
    case .preferences: PreferencesScreen()
    case .share(let item): ShareScreen(item: item)
    }
  }
}

enum AppFullScreen: FullScreenDestination {
  case onboarding

  var id: Self { self }

  var destinationView: some View {
    switch self {
    case .onboarding: OnboardingScreen()
    }
  }
}

enum AppTab: TabDestination {
  case home, search, profile
}
```

### Destination Protocols

| Protocol | Requires | Used For |
|----------|----------|----------|
| ``PushDestination`` | `Hashable`, `destinationView` | `NavigationStack` push |
| ``SheetDestination`` | `Hashable`, `Identifiable`, `destinationView` | `.sheet(item:)` |
| ``FullScreenDestination`` | `Hashable`, `Identifiable`, `destinationView` | `.fullScreenCover(item:)` |
| ``TabDestination`` | `Hashable` | Tab selection (no view — defined in your `TabView`) |

``SheetDestination`` and ``FullScreenDestination`` both inherit from ``PresentableDestination``, which provides the shared `Hashable & Identifiable` requirements.

### NavigationScene

Group all four destination types into a single generic parameter:

```swift
enum AppScene: NavigationScene {
  typealias Push = AppPush
  typealias Sheet = AppSheet
  typealias FullScreen = AppFullScreen
  typealias Tab = AppTab
}
```

This is the generic parameter used by ``Router``, ``NavigationContainer``, ``NavigationButton``, and ``Destination``.

## Router

``Router`` is an `@Observable` object that manages navigation state. Create a root router and pass it to ``NavigationContainer``:

```swift
let router = Router<AppScene>()
```

### Navigation Methods

| Method | Description |
|--------|-------------|
| `push(_:)` | Push onto the navigation stack |
| `present(sheet:)` | Present a sheet |
| `present(fullScreen:)` | Present a full-screen cover |
| `select(tab:)` | Switch tab (propagates to root) |
| `navigate(to:)` | Unified dispatch via ``Destination`` |
| `selectAndPush(tab:destination:)` | Switch tab and push in one step |
| `popToRoot()` | Clear the navigation stack |
| `dismissSheet()` | Dismiss the current sheet |
| `dismissFullScreen()` | Dismiss the current full-screen cover |
| `childRouter(for:)` | Get or create a cached child router for a tab |

```swift
router.push(.detail(id: "42"))
router.present(sheet: .preferences)
router.select(tab: .settings)
router.popToRoot()
```

### Parent-Child Hierarchy

Routers form a tree. Each child tracks its depth (`level`) and the tab it manages (`identifierTab`). The hierarchy enables:

- **Tab isolation**: Each tab has its own navigation stack via `childRouter(for:)`.
- **Modal nesting**: Sheets and full-screen covers get their own child router, enabling push navigation within modals.
- **Deep link routing**: Only the active router processes deep links.

Pass an `os.Logger` to the initializer for debug-level navigation logging.

### Previews

Create a preview router with an optional tab selection:

```swift
Router<AppScene>.preview(tab: .home)
```

## NavigationContainer

``NavigationContainer`` wires a ``Router`` to `NavigationStack`, `.sheet`, and `.fullScreenCover`:

```swift
// For a tab
NavigationContainer(parentRouter: router, tab: .home) {
  HomeScreen()
}

// For a modal (sheet or full-screen cover)
NavigationContainer(parentRouter: router) {
  ModalContentScreen()
}
```

The container:
- Creates a child Router from the parent.
- Manages active state (`onAppear` / `onDisappear`).
- Routes incoming URLs via `onOpenURL`.
- Wraps sheets and full-screen covers in their own NavigationContainer, enabling push navigation within modals.

> Note: `fullScreenCover` is only available on iOS (`#if os(iOS)`).

### Example App Structure

```swift
@main
struct MyApp: App {
  let router = Router<AppScene>()

  var body: some Scene {
    WindowGroup {
      TabView(selection: Bindable(router).selectedTab) {
        Tab("Home", systemImage: "house", value: AppTab.home) {
          NavigationContainer(parentRouter: router, tab: .home) {
            HomeScreen()
          }
        }
        Tab("Profile", systemImage: "person", value: AppTab.profile) {
          NavigationContainer(parentRouter: router, tab: .profile) {
            ProfileScreen()
          }
        }
      }
    }
  }
}
```

## NavigationButton

A convenience button that reads the ``Router`` from the environment:

```swift
NavigationButton<AppScene, _>(push: .detail(id: "1")) {
  Text("Show Detail")
}

NavigationButton<AppScene, _>(sheet: .preferences) {
  Text("Preferences")
}
```

Define a typealias to avoid repeating the Scene parameter:

```swift
typealias AppNavButton<Label: View> = NavigationButton<AppScene, Label>

AppNavButton(push: .detail(id: "1")) { Text("Go") }
```

## Deep Linking

Configure deep link handling with a URL scheme and composable parsers:

```swift
router.configureDeepLinks(scheme: "myapp", parsers: [
  // Static match
  .equal(to: ["settings"], destination: .tab(.settings)),

  // Custom parser
  DeepLinkParser { url in
    guard url.deepLinkComponents.first == "item",
          let id = url.deepLinkComponents.dropFirst().first
    else { return nil }
    return .push(.detail(id: id))
  }
])
```

``DeepLinkParser`` provides `.equal(to:destination:)` for static matches and an init that takes a custom parsing closure. Parsers are tried in order; the first non-nil result wins.

The URL extension `deepLinkComponents` strips the scheme and splits into components:
- `myapp://settings` → `["settings"]`
- `myapp://item/42` → `["item", "42"]`

Deep link handlers propagate to child routers automatically.

## Routed Factories

If a ViewModel needs a ``Router``, use a routed factory. ``NavigationContainer`` passes the router automatically:

```swift
let factory: GalleryViewModel.Factory = .routed { (router: Router<AppScene>) in
  GalleryViewModel(router: router, galleryService: galleryService)
}

// Inject as usual
GalleryScreen()
  .environment(factory)
```

## Destination

``Destination`` is a unified enum for navigation dispatch:

```swift
enum Destination<Scene: NavigationScene> {
  case tab(Scene.Tab)
  case push(Scene.Push)
  case sheet(Scene.Sheet)
  case fullScreen(Scene.FullScreen)
}
```

Use it with `router.navigate(to:)` for programmatic navigation, or as the return type of deep link parsers.
