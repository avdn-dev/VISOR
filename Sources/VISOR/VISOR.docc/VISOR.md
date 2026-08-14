# ``VISOR``

Build SwiftUI features around source-owned snapshots, MainActor State, structured observation lifetime, and typed navigation.

## Overview

VISOR (View–Interactor–Service–Observable ViewModel–Router) generates the integration wiring for a testable SwiftUI architecture:

```
View  →  ViewModel  →  Interactor  →  Service
             │           ↑               │
             ↓           └─ ObservationSource
           Router
```

- **View** owns SwiftUI integration. A `@LazyViewModel` view mounts the structured owner; a child Content view renders plain State and action closures.
- **ViewModel** is explicitly MainActor and owns one stable, macro-instrumented State instance. It projects service snapshots, handles user actions, and calls its Router when routed.
- **Interactor** optionally coordinates a named use case across services.
- **Service** owns domain or platform state under its natural isolation and publishes stable snapshots.
- **Router** owns typed navigation, presentation, tabs, and deep links.
- **Factory** hides ViewModel construction behind SwiftUI environment injection.

VISOR is split into four products:

| Product | Responsibility |
|---|---|
| `VISORObservation` | `ObservationChannel` and read-only `ObservationSource` capabilities |
| `VISOR` | ViewModel, SwiftUI, navigation, State routing, and generated runtime |
| `VISORTesting` | Swift Testing `observe`/`perform`/`expect` support |
| `VISORTestDoubles` | Independent generated stubs and spies |

There is no umbrella product. Import and link only the capabilities a target uses.

## Topics

### Essentials

- <doc:Architecture>
- ``ViewModel``
- ``ViewModelFactory``
- ``Loadable``

### Observation

- [Observation](Observation.md)
- ``ObservationPolicy``

### Navigation

- [Navigation](Navigation.md)
- ``Router``
- ``NavigationContainer``
- ``NavigationButton``
- ``NavigationScene``
- ``Destination``
- ``DeepLinkRequest``
- ``DeepLinkParser``
- ``DeepLinkParseResult``
- ``DeepLinkOutcome``
- ``PushDestination``
- ``SheetDestination``
- ``FullScreenDestination``
- ``PresentableDestination``
- ``TabDestination``
- ``NoTabDestination``

### Testing

- [Testing](Testing.md)
