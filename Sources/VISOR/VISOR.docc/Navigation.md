# Navigation

Type-safe navigation with Router, native SwiftUI containers, deep links, and modal hierarchies.

## Overview

VISOR centralises navigation state in a ``Router`` without prescribing how the
application presents its top-level destinations. Feature Views dispatch actions
to routed ViewModels, which make navigation decisions and call their local
Router. ``RouterHost`` supplies the SwiftUI environment and lifecycle boundary;
``RouterStack`` is the single-stack convenience built on top of it.

Destination types are route values. They carry stable identifiers and the
lightweight input needed to configure a screen, but do not create views. Prefer
model identifiers over complete snapshots so a destination resolves current
data. Content closures perform view resolution in the application target, where
all relevant feature view types are visible.

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

nonisolated enum AppRoot: RootDestination {
  case home
  case search
  case profile
}
```

### Destination Protocols

| Protocol | Requires | Used For |
|----------|----------|----------|
| ``PushDestination`` | `Hashable` | `NavigationStack` push |
| ``SheetDestination`` | `Hashable`, `Identifiable` | `.sheet(item:)` |
| ``FullScreenDestination`` | `Hashable`, `Identifiable` | Full-screen intent; adapts to `.sheet(item:)` on macOS |
| ``RootDestination`` | `Hashable`, `CaseIterable` | Top-level tabs, sidebar rows, or another application-owned selector |

``SheetDestination`` and ``FullScreenDestination`` inherit from
``PresentableDestination``, which provides their shared `Hashable & Identifiable`
requirements.

A presentation's `id` is its logical screen identity; it does not have to be
the complete destination value. This allows changing input for an existing
presentation without discarding its child Router. Namespace identities by case
so unrelated screens cannot accidentally share one:

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
one direct modal slot, so its latest sheet or full-screen request replaces its
previous request. A presented child Router can still present another modal.

`Hashable` lets push destinations participate in a navigation path; it does not
make that path unique. Repeated equal push destinations are appended normally.

`RootDestination.allCases` declares the complete finite set of independently
stateful branches. A Router tree snapshots that set at creation and fails a
diagnostic precondition for a root absent from it. This bounds the never-evicted
child Router cache while preserving each declared branch's path. Prefer a
no-payload enum; if you provide `allCases` manually, include every supported
root.

### NavigationScene

Group the destination types into a single generic parameter:

```swift
nonisolated enum AppScene: NavigationScene {
  typealias Push = AppPush
  typealias Sheet = AppSheet
  typealias FullScreen = AppFullScreen
  typealias Root = AppRoot
}
```

`Root` is optional. A single-stack application omits it and receives
``NoRootDestination`` as the default:

```swift
nonisolated enum SingleStackScene: NavigationScene {
  typealias Push = AppPush
  typealias Sheet = AppSheet
  typealias FullScreen = AppFullScreen
}
```

This scene is the generic parameter used by ``Router``, ``RouterHost``,
``RouterStack``, ``NavigationButton``, and ``Destination``. Its conformance is
nonisolated so the scene metatype can participate safely in `Sendable`
navigation values and parsers. Spell `nonisolated` explicitly in
MainActor-by-default targets.

## Writing Content Closures

Content closures map route values to views. Write them as `@ViewBuilder`
functions that switch over each destination:

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

## Router

``Router`` is an `@Observable` object that manages one navigation tree:

```swift
let router = Router<AppScene>()
```

### Navigation Methods

| Method | Description |
|--------|-------------|
| `push(_:)` | Push onto the active navigation stack |
| `present(sheet:)` | Present a sheet |
| `present(fullScreen:)` | Present a destination with full-screen intent |
| `select(root:)` | Select a top-level destination |
| `navigate(to:)` | Unified dispatch via ``Destination`` |
| `selectAndPush(root:destination:)` | Select a root destination and push in one operation |
| `popToRoot()` | Clear the active navigation stack |
| `dismissSheet()` | Dismiss the current sheet |
| `dismissFullScreen()` | Dismiss the current full-screen destination |
| `childRouter(for:)` | Get or create the cached Router for a root destination |

Actions that require a mounted host return `true` when accepted and `false`
when no active target exists. Dismissal methods return `false` when there is no
matching presentation to remove. The results are discardable for fire-and-forget
UI actions and available when application logic needs an explicit outcome.

```swift
// Once a RouterHost has appeared:
router.push(.detail(id: "42"))
router.present(sheet: .preferences)
router.select(root: .profile)
router.popToRoot()
```

In feature code, prefer making these calls from a routed ViewModel's action
handler.

Calls on the root Router target the currently active visible Router: the root
stack in a single-stack application, the selected root destination, or the
topmost modal. Calls on a non-root Router obtained from the SwiftUI environment
remain local to that host. `select(root:)` and
`selectAndPush(root:destination:)` explicitly coordinate the root Router from
any node in its tree.

A Router is **mounted** while its host exists in the visible SwiftUI hierarchy.
Exactly one mounted Router in a tree is **active** and receives root actions and
deep links. A newly visible child becomes active; dismissing it restores the
nearest mounted ancestor. A late disappearance from an old branch cannot
deactivate a newer branch.

Calls made before any host is mounted are rejected rather than retained as
invisible navigation state. Check the returned `Bool` when the caller must react
to rejection, and pass an `os.Logger` to the root initialiser to record those
diagnostics.

### Root and Modal Children

Each root destination receives a cached child Router with its own navigation
path. Switching between tabs or sidebar rows therefore preserves independent
stack state. Modal presentations receive fresh child Routers whose lifetime is
owned by the presentation record.

Create a preview Router with an optional initial root selection:

```swift
Router<AppScene>.preview(root: .home)
```

## RouterStack

Use ``RouterStack`` when a navigation surface is one `NavigationStack`:

```swift
@State private var router = Router<SingleStackScene>()

RouterStack(
  router: router,
  pushContent: pushContent(for:),
  sheetContent: sheetContent(for:),
  fullScreenContent: fullScreenContent(for:)
) {
  HomeScreen()
}
```

`RouterStack` composes ``RouterHost`` with a `NavigationStack`, binds
`router.navigationPath`, and registers the push destination resolver. Sheets
and adaptive full-screen presentations receive their own `RouterStack`, so a
presented flow can push without additional wiring.

Full-screen destinations use SwiftUI's native `.fullScreenCover(item:)` where
available. On macOS, where that modifier is unavailable, the same route intent
adapts to `.sheet(item:)`. On visionOS this remains a modal presentation; it
does not open an `ImmersiveSpace`.

## Native Top-Level Navigation

``RouterHost`` mounts a Router around arbitrary SwiftUI content. VISOR owns the
Router lifecycle, deep links, environment and modal state; the application owns
the native navigation container, columns, sidebar content, window chrome and
size adaptation.

### Tabs

Render each root destination as a tab by placing one branch ``RouterStack`` in
the `TabView`:

```swift
struct AppRootView: View {
  @State private var router = Router<AppScene>.preview(root: .home)

  var body: some View {
    @Bindable var router = router

    RouterHost(
      router: router,
      pushContent: pushContent(for:),
      sheetContent: sheetContent(for:),
      fullScreenContent: fullScreenContent(for:)
    ) {
      TabView(selection: $router.selectedRoot) {
        RouterStack(
          parentRouter: router,
          root: .home,
          pushContent: pushContent(for:),
          sheetContent: sheetContent(for:),
          fullScreenContent: fullScreenContent(for:)
        ) {
          HomeScreen()
        }
        .tabItem { Label("Home", systemImage: "house") }
        .tag(AppRoot.home as AppRoot?)

        RouterStack(
          parentRouter: router,
          root: .profile,
          pushContent: pushContent(for:),
          sheetContent: sheetContent(for:),
          fullScreenContent: fullScreenContent(for:)
        ) {
          ProfileScreen()
        }
        .tabItem { Label("Profile", systemImage: "person") }
        .tag(AppRoot.profile as AppRoot?)
      }
    }
  }
}
```

The same root selection works with SwiftUI's sidebar-adaptable tab style on
platform versions that provide it; the Router API does not change.

### Sidebars and Split Views

On iPadOS and macOS, bind a `NavigationSplitView` sidebar to the same root
selection and place the selected branch's stack in the detail column:

```swift
struct SplitAppRootView: View {
  @State private var router = Router<AppScene>.preview(root: .home)

  var body: some View {
    @Bindable var router = router

    RouterHost(
      router: router,
      pushContent: pushContent(for:),
      sheetContent: sheetContent(for:),
      fullScreenContent: fullScreenContent(for:)
    ) {
      NavigationSplitView {
        List(selection: $router.selectedRoot) {
          Label("Home", systemImage: "house").tag(AppRoot.home)
          Label("Search", systemImage: "magnifyingglass").tag(AppRoot.search)
          Label("Profile", systemImage: "person").tag(AppRoot.profile)
        }
        .navigationTitle("VISOR")
      } detail: {
        if let root = router.selectedRoot {
          RouterStack(
            parentRouter: router,
            root: root,
            pushContent: pushContent(for:),
            sheetContent: sheetContent(for:),
            fullScreenContent: fullScreenContent(for:)
          ) {
            rootContent(for: root)
          }
        } else {
          ContentUnavailableView(
            "Select a Destination",
            systemImage: "sidebar.left")
        }
      }
    }
  }
}
```

Do not switch between stack and split layouts by horizontal size class inside
VISOR. `NavigationSplitView` already owns its platform collapse behaviour, and
the application is the only layer that knows which content belongs in each
column. macOS inspectors, commands, menus and toolbar composition remain native
application concerns and can dispatch into the focused window's Router.

### Windows and Scenes

Place Router state inside the scene-root View to give every `WindowGroup`
instance an independent navigation tree:

```swift
@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup {
      AppRootView() // AppRootView owns its Router in @State.
    }
  }
}
```

Move the Router into `App` state only when multiple windows should deliberately
share one navigation tree. Sharing by default breaks per-window selection,
stack and presentation state expected on macOS and iPadOS.

## Modal Completion and Dismissal

VISOR does not inject Close, Cancel or Done controls because only the feature
knows whether leaving confirms work, abandons a draft, or merely closes
information. Provide a visible semantic action where the platform and flow need
one:

```swift
struct EditProfileScreen: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    EditProfileContent()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
  }
}
```

Use `.confirmationAction` for a genuine confirmation. A routed ViewModel may
instead call `dismissSheet()` or `dismissFullScreen()` when dismissal follows a
domain action. A sheet or full-screen onboarding flow may present another sheet
through its local Router; nested presentation is part of the Router hierarchy.

## NavigationButton

``NavigationButton`` reads the local Router from the environment and dispatches
directly:

```swift
NavigationButton<AppScene, _>(push: .detail(id: "1")) {
  Text("Show Detail")
}

NavigationButton<AppScene, _>(sheet: .preferences) {
  Text("Preferences")
}
```

This bypasses ViewModel action handling. Routed ViewModels are the preferred
navigation architecture for feature flows; use the button only when deliberately
choosing direct View-to-Router dispatch.

## Deep Linking

Configure deep-link handling with a URL scheme and ordered parsers:

```swift
try router.configureDeepLinks(scheme: "myapp", parsers: [
  .equal(to: ["profile"], destination: .root(.profile)),

  DeepLinkParser { request in
    guard request.components.first == "item" else { return .noMatch }
    guard request.components.count == 2,
          let decodedID = request.components[1].removingPercentEncoding,
          let id = UUID(uuidString: decodedID)
    else { return .invalid }
    return .destination(.push(.detail(id: id.uuidString)))
  },
])
```

Configuration validates the scheme before mutating Router state. Handle
``DeepLinkConfigurationError`` at the composition boundary; schemes must start
with an ASCII letter and may then contain ASCII letters, digits, `+`, `-`, or
`.`. Do not include `://`.

``DeepLinkRequest`` exposes the original URL and its host-plus-path components.
It omits the structural leading path separator and accepts one conventional
trailing separator, so both `myapp://profile` and `myapp:///profile/` produce
`["profile"]`. Literal repeated or interior separators are preserved as empty
components and make ``DeepLinkRequest/isStructurallyValid`` false. The Router
returns ``DeepLinkOutcome/invalid`` before dispatching such a request to a
parser. A percent-encoded separator such as `%2F` remains part of one encoded
component; decode each dynamic value exactly once.

Return `.noMatch` when a parser does not recognise the route so evaluation can
continue. Once a parser recognises its route, return `.invalid` for the wrong
component count, failed decoding, or a malformed identifier. This stops a later
parser from reinterpreting invalid input.

``RouterHost`` and ``RouterStack`` call ``Router/openDeepLink(_:)`` automatically
for the active mounted Router. Supply `onDeepLinkOutcome` to present
unsupported-link UI or record telemetry for automatic URL delivery. Router-owned
modal stacks inherit the callback. If an application constructs several sibling
hosts, pass the same callback to each; only the active host processes a given
URL.

An inactive host ignores SwiftUI's tree-wide URL delivery to prevent duplicate
processing, so its callback is not invoked. Call `openDeepLink(_:)` directly
when another application boundary receives a URL and handle its explicit
outcome, including `.inactive`. A direct call does not invoke a host callback:

```swift
switch router.openDeepLink(url) {
case .handled:
  break
case .unconfigured, .schemeMismatch, .unmatched, .invalid, .inactive:
  showUnsupportedLinkMessage()
}
```

Each Router tree stores one current configuration. Configuring the root—or any
child—updates existing and future root and modal children immediately. Separate
scene-root Routers retain independent configurations.

For HTTPS links, validate the complete host with an exact, case-insensitive
comparison, then validate the path and query values:

```swift
try router.configureDeepLinks(scheme: "https", parsers: [
  DeepLinkParser { request in
    guard request.url.host()?.caseInsensitiveCompare("links.example.com")
            == .orderedSame
    else { return .noMatch }
    guard request.components == ["links.example.com", "profile"]
    else { return .noMatch }
    return .destination(.root(.profile))
  },
])
```

Parsing proves only that a URL is structurally valid. The service that loads or
mutates the referenced resource must still enforce authentication and
authorisation; possession of a deep link is not permission.

## Routed Factories

Use a routed factory for every ViewModel that can navigate. The View dispatches
an action, the ViewModel makes the navigation decision, and ``RouterHost``
supplies its local Router:

```swift
let factory: GalleryViewModel.Factory = .routed { (router: Router<AppScene>) in
  GalleryViewModel(router: router, galleryService: galleryService)
}

GalleryScreen()
  .environment(factory)
```

Render the screen beneath a ``RouterHost`` for the same `AppScene`; a missing or
differently typed Router is an invalid composition and fails during ViewModel
creation.

## Destination

``Destination`` is the unified value accepted by `router.navigate(to:)` and
emitted by deep-link parsers:

```swift
enum Destination<Scene: NavigationScene> {
  case root(Scene.Root)
  case push(Scene.Push)
  case sheet(Scene.Sheet)
  case fullScreen(Scene.FullScreen)
}
```
