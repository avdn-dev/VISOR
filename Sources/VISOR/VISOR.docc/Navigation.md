# Navigation

Type-safe navigation with Router, NavigationScene, deep linking, and modal hierarchies.

## Overview

VISOR's navigation system centralises all navigation state in a ``Router`` object, decoupling views from their destinations. Feature Views dispatch actions to routed ViewModels, which decide what to show and call the Router. ``NavigationContainer`` handles the SwiftUI wiring.

Destination types are route-value enums — they carry stable identifiers and any
lightweight input needed to configure a screen, but don't create the view. Prefer
model identifiers over complete model snapshots so a destination resolves current
data. View creation is handled by content closures passed to
``NavigationContainer``, which means the destination enums can live in a shared
module without importing feature view types.

## Defining Destinations

Define destination types as plain `Hashable` enums:

```swift
nonisolated enum AppPush: PushDestination {
  case detail(id: String)
  case settings
}

nonisolated enum AppSheet: SheetDestination {
  case preferences
  case share(itemID: Item.ID)

  var id: Self { self }
}

nonisolated enum AppFullScreen: FullScreenDestination {
  case onboarding

  var id: Self { self }
}

// Declare this only when the application uses a TabView.
nonisolated enum AppTab: TabDestination {
  case home, search, profile
}
```

### Destination Protocols

| Protocol | Requires | Used For |
|----------|----------|----------|
| ``PushDestination`` | `Hashable` | `NavigationStack` push |
| ``SheetDestination`` | `Hashable`, `Identifiable` | `.sheet(item:)` |
| ``FullScreenDestination`` | `Hashable`, `Identifiable` | Full-screen intent; adapts to `.sheet(item:)` on macOS |
| ``TabDestination`` | `Hashable` | Tab selection (no view — defined in your `TabView`) |

``SheetDestination`` and ``FullScreenDestination`` both inherit from ``PresentableDestination``, which provides the shared `Hashable & Identifiable` requirements.

A presentation's `id` is its logical screen identity; it does not have to be
the complete destination value. This is useful when the route carries changing
input for the same screen. Namespace identities by destination case so unrelated
screens cannot accidentally share one:

```swift
nonisolated enum EditorSheet: SheetDestination {
  case editor(documentID: Document.ID, revision: Int)

  enum ID: Hashable {
    case editor(Document.ID)
  }

  var id: ID {
    switch self {
    case .editor(let documentID, _): .editor(documentID)
    }
  }
}
```

Presenting updated payload with the same ID preserves that modal's child Router.
A different ID or presentation style creates a fresh child. Each Router node has
one direct modal slot, so the latest sheet or full-screen request replaces the
previous request on that node. Nested presentation remains available from the
presented modal's child Router.

`Hashable` lets push destinations participate in a navigation path; it does not
make the path unique. Repeated equal push destinations are appended normally.

### NavigationScene

Group the destination types into a single generic parameter:

```swift
nonisolated enum AppScene: NavigationScene {
  typealias Push = AppPush
  typealias Sheet = AppSheet
  typealias FullScreen = AppFullScreen
  typealias Tab = AppTab
}
```

`Tab` is optional. A single-stack application omits it and receives
``NoTabDestination`` as the default:

```swift
nonisolated enum SingleStackScene: NavigationScene {
  typealias Push = AppPush
  typealias Sheet = AppSheet
  typealias FullScreen = AppFullScreen
}
```

This is the generic parameter used by ``Router``, ``NavigationContainer``, ``NavigationButton``, and ``Destination``.
Its conformance is nonisolated so the scene metatype can safely participate in
`Sendable` navigation values and parsers. Spell `nonisolated` explicitly in
MainActor-by-default targets, as shown above.

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
  case .share(let itemID): ShareScreen(itemID: itemID)
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

``Router`` is an `@Observable` object that manages one navigation tree. Create
one root Router per window or scene and pass it to ``NavigationContainer``:

```swift
let router = Router<AppScene>()
```

### Navigation Methods

| Method | Description |
|--------|-------------|
| `push(_:)` | Push onto the navigation stack |
| `present(sheet:)` | Present a sheet |
| `present(fullScreen:)` | Present a destination with full-screen intent |
| `select(tab:)` | Switch tab (propagates to root) |
| `navigate(to:)` | Unified dispatch via ``Destination`` |
| `selectAndPush(tab:destination:)` | Switch tab and push in one step |
| `popToRoot()` | Clear the navigation stack |
| `dismissSheet()` | Dismiss the current sheet |
| `dismissFullScreen()` | Dismiss the current full-screen destination |
| `childRouter(for:)` | Get or create a cached child router for a tab |

```swift
// Once the root NavigationContainer has appeared:
router.push(.detail(id: "42"))
router.present(sheet: .preferences)
router.select(tab: .profile)
router.popToRoot()
```

These calls are shown directly to document the Router API. In feature code,
prefer making them from a routed ViewModel's action handler.

Calls on the root Router target the currently active visible Router: the root
stack in a single-stack application, the selected tab, or the topmost modal.
Calls on a non-root Router read from the SwiftUI environment remain local to
that container. In a single-stack application the environment Router is also
the root coordinator. `select(tab:)` and `selectAndPush(tab:destination:)`
explicitly coordinate tabs regardless of the active container.

A Router becomes active when its container appears. Calls made before any
container is mounted are rejected rather than being retained as invisible
navigation state. Pass an `os.Logger` to the root initialiser to record those
diagnostics.

### Parent-Child Hierarchy

Routers form a tree. Each child tracks its depth (`level`) and the tab it manages (`tab`). The hierarchy enables:

- **Optional tabs**: A root container binds the root Router directly when the application has one stack.
- **Tab isolation**: Each tab has its own navigation stack via `childRouter(for:)`.
- **Modal nesting**: Sheets and full-screen presentations get their own child router, enabling push navigation within modals.
- **Active-leaf routing**: One visible Router receives root actions and deep links. Dismissing a modal restores its nearest mounted ancestor.

Late disappearance from an old tab or modal cannot deactivate a newer visible
Router.

### Previews

Create a preview router with an optional tab selection:

```swift
Router<AppScene>.preview(tab: .home)
```

## NavigationContainer

``NavigationContainer`` wires a ``Router`` to `NavigationStack` and platform-adaptive modal presentation. Pass content closures that map each destination type to its view.

For a single stack, bind the root Router directly:

```swift
NavigationContainer(
  router: router,
  pushContent: pushContent(for:),
  sheetContent: sheetContent(for:),
  fullScreenContent: fullScreenContent(for:)
) {
  HomeScreen()
}
```

For a tab, create or reuse that tab's child Router:

```swift
NavigationContainer(
  parentRouter: router,
  tab: .home,
  pushContent: pushContent(for:),
  sheetContent: sheetContent(for:),
  fullScreenContent: fullScreenContent(for:)
) {
  HomeScreen()
}
```

Modal containers are created automatically by the sheet and adaptive
full-screen presentation modifiers.

The container:
- Borrows a root Router, reuses a tab child, or owns a manually requested modal child.
- Manages active state (`onAppear` / `onDisappear`).
- Routes incoming URLs via `onOpenURL`.
- Wraps sheets and full-screen presentations in their own NavigationContainer, automatically propagating the content closures so push navigation works within modals.

Full-screen destinations use SwiftUI's native `.fullScreenCover(item:)` on iOS,
Mac Catalyst, tvOS, watchOS, and visionOS. On macOS, where SwiftUI marks that
modifier unavailable, ``NavigationContainer`` adapts the route to a
`.sheet(item:)`. On visionOS this remains a modal presentation; it does not open
an `ImmersiveSpace`.

### Example App Structure

```swift
@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup {
      AppRoot()
    }
  }
}

struct AppRoot: View {
  @State private var router = Router<AppScene>()

  var body: some View {
    TabView(selection: Bindable(router).selectedTab) {
      NavigationContainer(
        parentRouter: router,
        tab: .home,
        pushContent: pushContent(for:),
        sheetContent: sheetContent(for:),
        fullScreenContent: fullScreenContent(for:)
      ) {
        HomeScreen()
      }
      .tabItem { Label("Home", systemImage: "house") }
      .tag(AppTab.home)

      NavigationContainer(
        parentRouter: router,
        tab: .profile,
        pushContent: pushContent(for:),
        sheetContent: sheetContent(for:),
        fullScreenContent: fullScreenContent(for:)
      ) {
        ProfileScreen()
      }
      .tabItem { Label("Profile", systemImage: "person") }
      .tag(AppTab.profile)
    }
  }
}
```

Placing the Router in scene-root `@State` gives every `WindowGroup` instance an
independent navigation tree. Move the Router into `App` state only when every
window should deliberately share one navigation tree. ``NavigationContainer``
borrows root and tab Routers, so replacing an input Router replaces the tree the
container observes instead of retaining its first input as local State.

## NavigationButton

A convenience button that reads the ``Router`` from the environment and
dispatches directly:

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

`NavigationButton` bypasses ViewModel action handling. Routed ViewModels are the
preferred navigation architecture for feature flows; use this convenience only
when deliberately choosing direct View-to-Router dispatch.

## Deep Linking

Configure deep link handling with a URL scheme and composable parsers:

```swift
router.configureDeepLinks(scheme: "myapp", parsers: [
  // Static match: myapp://profile
  .equal(to: ["profile"], destination: .tab(.profile)),

  // Custom parser: myapp://item/550E8400-E29B-41D4-A716-446655440000
  DeepLinkParser { request in
    guard request.components.first == "item" else { return .noMatch }
    guard request.components.count == 2,
          let decodedID = request.components[1].removingPercentEncoding,
          let id = UUID(uuidString: decodedID)
    else { return .invalid }
    return .destination(.push(.detail(id: id.uuidString)))
  }
])
```

``DeepLinkRequest`` exposes the original URL and its host-plus-path
`components`. ``DeepLinkParser`` provides `.equal(to:destination:)` for static
matches and a custom parsing closure for dynamic routes. Return `.noMatch` when
the parser does not recognise the route so evaluation can continue. Once a
parser recognises its route, return `.invalid` for a wrong component count,
failed decoding, or malformed identifier; this stops evaluation instead of
letting a later parser reinterpret bad input. Decode a component exactly once.

``NavigationContainer`` calls ``Router/openDeepLink(_:)`` automatically for the
active mounted Router. Call it directly when another application boundary
receives a URL and use the ``DeepLinkOutcome`` to make failure handling explicit:

```swift
switch router.openDeepLink(url) {
case .handled:
  break
case .unconfigured, .schemeMismatch, .unmatched, .invalid, .inactive:
  showUnsupportedLinkMessage()
}
```

Each Router tree stores one current deep-link configuration. Configuring the
root—or any child—updates existing and future tab and modal Routers immediately,
so configuration order does not affect URL handling. Separate scene-root
Routers retain independent configurations.

The configured scheme is only the first validation boundary. For HTTPS links,
validate the complete host with an exact, case-insensitive comparison—never a
suffix test—and then validate the path and query values:

```swift
router.configureDeepLinks(scheme: "https", parsers: [
  DeepLinkParser { request in
    guard request.url.host()?.caseInsensitiveCompare("links.example.com")
            == .orderedSame
    else { return .noMatch }
    guard request.components == ["links.example.com", "profile"]
    else { return .noMatch }
    return .destination(.tab(.profile))
  }
])
```

Parsing proves only that a URL is structurally valid. The service that loads or
mutates the referenced resource must still enforce authentication and
authorisation; never treat possession of a deep link as permission.

## Routed Factories

Use a routed factory for every ViewModel that can navigate. This is the
preferred feature-navigation path: the View dispatches an action, the ViewModel
makes the navigation decision, and ``NavigationContainer`` supplies the local
Router automatically:

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

Use it with `router.navigate(to:)` for programmatic navigation, or wrap it in
``DeepLinkParseResult/destination(_:)`` from a deep-link parser.
