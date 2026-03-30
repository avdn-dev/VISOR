# Navigation

Type-safe navigation with Router, NavigationScene, deep linking, and modal hierarchies.

## Overview

VISOR's navigation system centralises all navigation state in a ``Router`` object, decoupling views from their destinations. Views never directly present other views — they tell the Router what to show, and ``NavigationContainer`` handles the SwiftUI wiring.

Destination types are identity-only enums — they carry the data needed to identify a screen but don't create the view. View creation is handled by content closures passed to ``NavigationContainer``, which means the destination enums can live in a shared module without importing feature view types.

## Defining Destinations

Define destination types as plain `Hashable` enums:

```swift
nonisolated enum AppPush: PushDestination {
  case detail(id: String)
  case settings
}

nonisolated enum AppSheet: SheetDestination {
  case preferences
  case share(item: Item)

  var id: Self { self }
}

nonisolated enum AppFullScreen: FullScreenDestination {
  case onboarding

  var id: Self { self }
}

nonisolated enum AppTab: TabDestination {
  case home, search, profile
}
```

### Destination Protocols

| Protocol | Requires | Used For |
|----------|----------|----------|
| ``PushDestination`` | `Hashable` | `NavigationStack` push |
| ``SheetDestination`` | `Hashable`, `Identifiable` | `.sheet(item:)` |
| ``FullScreenDestination`` | `Hashable`, `Identifiable` | `.fullScreenCover(item:)` |
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

## Writing Content Closures

Content closures map destination values to views. Write them as `@ViewBuilder` functions that switch over each destination:

```swift
@ViewBuilder
func pushContent(for destination: AppPush) -> some View {
  switch destination {
  case .detail(let id): DetailScreen(id: id)
  case .settings: SettingsScreen()
  }
}

@ViewBuilder
func sheetContent(for destination: AppSheet) -> some View {
  switch destination {
  case .preferences: PreferencesScreen()
  case .share(let item): ShareScreen(item: item)
  }
}

@ViewBuilder
func fullScreenContent(for destination: AppFullScreen) -> some View {
  switch destination {
  case .onboarding: OnboardingScreen()
  }
}
```

Place these functions in a target that can see all feature view types (typically the app target). The compiler enforces exhaustive switching, so adding a new destination case immediately flags every call site that needs a view.

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

Routers form a tree. Each child tracks its depth (`level`) and the tab it manages (`tab`). The hierarchy enables:

- **Tab isolation**: Each tab has its own navigation stack via `childRouter(for:)`.
- **Modal nesting**: Sheets and full-screen covers get their own child router, enabling push navigation within modals.
- **Deep link routing**: Only the active router processes deep links.

Pass an `os.Logger` to the initialiser for debug-level navigation logging.

### Previews

Create a preview router with an optional tab selection:

```swift
Router<AppScene>.preview(tab: .home)
```

## NavigationContainer

``NavigationContainer`` wires a ``Router`` to `NavigationStack`, `.sheet`, and `.fullScreenCover`. Pass content closures that map each destination type to its view:

```swift
// For a tab
NavigationContainer(
  parentRouter: router,
  tab: .home,
  pushContent: pushContent(for:),
  sheetContent: sheetContent(for:),
  fullScreenContent: fullScreenContent(for:)
) {
  HomeScreen()
}

// For a modal (sheet or full-screen cover)
NavigationContainer(
  parentRouter: router,
  pushContent: pushContent(for:),
  sheetContent: sheetContent(for:),
  fullScreenContent: fullScreenContent(for:)
) {
  ModalContentScreen()
}
```

The container:
- Creates a child Router from the parent.
- Manages active state (`onAppear` / `onDisappear`).
- Routes incoming URLs via `onOpenURL`.
- Wraps sheets and full-screen covers in their own NavigationContainer, automatically propagating the content closures so push navigation works within modals.

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
          NavigationContainer(
            parentRouter: router,
            tab: .home,
            pushContent: pushContent(for:),
            sheetContent: sheetContent(for:),
            fullScreenContent: fullScreenContent(for:)
          ) {
            HomeScreen()
          }
        }
        Tab("Profile", systemImage: "person", value: AppTab.profile) {
          NavigationContainer(
            parentRouter: router,
            tab: .profile,
            pushContent: pushContent(for:),
            sheetContent: sheetContent(for:),
            fullScreenContent: fullScreenContent(for:)
          ) {
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
  // Static match: myapp://settings
  .equal(to: ["settings"], destination: .tab(.settings)),

  // Custom parser: myapp://item/42
  DeepLinkParser { url in
    guard url.host() == "item",
          let id = url.pathComponents.dropFirst().first
    else { return nil }
    return .push(.detail(id: String(id)))
  }
])
```

``DeepLinkParser`` provides `.equal(to:destination:)` for static matches and an init that takes a custom parsing closure. Parsers are tried in order; the first non-nil result wins.

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
