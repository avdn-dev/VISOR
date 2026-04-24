# ``VISOR``

Macro-powered architecture for SwiftUI — eliminates observation boilerplate, enforces testability, and provides type-safe navigation.

## Overview

VISOR (View-Interactor-Service-Observable(ViewModel)-Router) generates the boilerplate code needed for a clean, testable SwiftUI architecture. The core idea: declare your intent with attributes and let the macros generate the wiring.

```
View  →  ViewModel  →  Interactor  →  Service
 |            |                |              |
(UI only)  (owns State,    (coordinates  (platform/domain,
             dispatches      services,     may depend on
             Actions)        use-case      other services)
                              logic)
```

Dependencies only point downward: **View → ViewModel / Router → Interactor → Service**. Services may depend on other services.

- **View**: UI only. The `@LazyViewModel` view owns the ViewModel; child Content views receive state as plain parameters.
- **ViewModel**: The "brain" of the view. Owns an `@Observable final class State` that is directly mutated via `updateState` for per-field invalidation. Dispatches user intent via an `Action` enum.
- **Router**: Type-safe navigation state with parent-child hierarchy, deep linking, and modal support.
- **Factory**: `ViewModelFactory<VM>` injected via `@Environment`, creates ViewModel instances with their dependencies.
- **Interactor** (optional): Coordinates multiple services for complex use cases.
- **Service**: Platform or domain components providing shared `@Observable` state.

## Topics

### Essentials

- <doc:Architecture>
- ``ViewModel``
- ``ViewModelFactory``
- ``Loadable``

### Observation

- <doc:Observation>
- ``ObservationPolicy``

### Navigation

- <doc:Navigation>
- ``Router``
- ``NavigationContainer``
- ``NavigationButton``
- ``NavigationScene``
- ``Destination``
- ``DeepLinkParser``
- ``PushDestination``
- ``SheetDestination``
- ``FullScreenDestination``
- ``PresentableDestination``
- ``TabDestination``

### Testing

- <doc:Testing>
- ``Expectation``
