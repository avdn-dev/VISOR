# Observation

Automatic observation with `@Bound`, pull-based polling with `@Polled`, and method reactions with `@Reaction`.

## Overview

VISOR provides three attributes for declaring observation intent inside `@ViewModel` classes. The macro reads these annotations and generates the observation code — loops, deduplication, task management, and initial state.

All three support `throttledBy:` for rate-limiting rapid-fire updates.

## @Bound — Push-Based Observation

`@Bound` marks a property inside `struct State` for automatic observation from an `@Observable` source. The key path identifies the source property on a dependency:

```swift
@Observable
@ViewModel
final class ConnectionsViewModel {
  struct State: Equatable {
    @Bound(\ConnectionsViewModel.connectionService.isAuthenticated) var isAuthenticated: Bool
    @Bound(\ConnectionsViewModel.connectionService.recentItems) var recentItems: [String]
  }

  private let connectionService: ConnectionService
}
```

### What Gets Generated

For each `@Bound` property, the macro generates an observe method:

```swift
// Generated for isAuthenticated:
func observeIsAuthenticated() async {
  for await value in VISOR.valuesOf({ self.connectionService.isAuthenticated }) {
    self.updateState(\.isAuthenticated, to: value)
  }
}
```

When multiple observations exist, `startObserving()` runs them concurrently in a `withDiscardingTaskGroup`.

### Key Path Format

The key path must use the full class name as the root and include at least two components — the dependency and the property:

```swift
// Correct — full path: ClassName.dependency.property
@Bound(\MyViewModel.service.count) var count: Int

// Wrong — \Self refers to State, not the class
@Bound(\Self.service.count) var count: Int

// Wrong — needs the property component too
@Bound(\MyViewModel.service) var count: Int
```

### No Default Values

`@Bound` properties cannot have default values. They're initialised from the service at `init` time:

```swift
// Correct — initialised from service
@Bound(\MyViewModel.service.name) var name: String

// Compile error — remove the default
@Bound(\MyViewModel.service.name) var name = ""
```

This ensures state always starts with real data. Non-bound properties in the same State struct keep their defaults normally.

## @Polled — Pull-Based Observation

`@Polled` is the pull-based counterpart to `@Bound`. Use it for non-observable sources that don't participate in `@Observable` — hardware sensors, system APIs, or computed properties:

```swift
@Observable
@ViewModel
final class DashboardViewModel {
  struct State: Equatable {
    @Polled(\DashboardViewModel.batteryMonitor.level, every: .seconds(30)) var batteryLevel: Float
    @Polled(\DashboardViewModel.locationTracker.heading, every: .seconds(1)) var heading: Double
  }

  private let batteryMonitor: BatteryMonitor
  private let locationTracker: LocationTracker
}
```

The generated code polls on a timer, using `updateState` for automatic deduplication. Zero CPU cost between polls.

Like `@Bound`, `@Polled` properties cannot have default values — they're initialised from the source at creation time.

## @Reaction — Method-Level Reactions

`@Reaction` calls a method whenever an observed property changes. Use it for side effects that don't map to State properties:

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
```

### Requirements

- The method must take exactly **one parameter** whose type matches the observed property.
- The key path uses `\Self` (which refers to the class, not a nested struct).

### Delivery Semantics

Both sync and async methods use **sequential delivery** via `for await`. Each handler completes before the next value is processed:

```swift
// Sync — called for every value change
@Reaction(\Self.service.status)
func handleStatus(status: Status) { ... }

// Async — also sequential; each handler completes before the next starts
@Reaction(\Self.service.query)
func performSearch(query: String) async { ... }
```

If you need cancel-previous semantics (where a new value cancels the in-flight handler), use `latestValuesOf()` directly instead of `@Reaction`.

## Rate Limiting with throttledBy:

All three observation attributes support `throttledBy:` to limit rapid-fire updates. The observation loop pauses after each update, dropping intermediate values:

```swift
struct State: Equatable {
  // Limit to ~8 updates/second
  @Bound(\MyViewModel.headTracker.posture, throttledBy: .seconds(0.125)) var posture: Posture

  // Poll heading, but also throttle processing
  @Polled(\MyViewModel.compass.heading, every: .seconds(0.5)) var heading: Double
}

// Throttle a reaction
@Reaction(\Self.recorder.audioLevel, throttledBy: .seconds(0.1))
func handleAudioLevel(level: Float) { ... }
```

When the source is quiet, there's zero CPU cost — throttling only adds a sleep after processing an actual change.

## Low-Level: valuesOf() and latestValuesOf()

The macros are built on two public functions you can use directly:

### valuesOf()

Returns an `AsyncStream` that emits the current value and re-emits on every change. The `Equatable`-constrained overload automatically deduplicates:

```swift
for await count in valuesOf({ service.count }) {
  print(count) // only fires when count actually changes
}
```

- On iOS 26+: Backed by `Observations` (SE-0475, transactional did-set semantics).
- On earlier OS: Backed by `ObservationSequence` using `withObservationTracking`.

### latestValuesOf()

Observes a value and runs an async handler, cancelling any previous in-flight handler when a new value arrives:

```swift
await latestValuesOf({ router.pendingDestination }) { destination in
  await handleNavigation(destination)
}
```

Use this when only the latest value matters and stale work should be abandoned.

## ObservationPolicy

`@LazyViewModel` accepts an `observationPolicy` parameter that controls whether observation pauses based on scene phase:

```swift
// Default — observation runs continuously
@LazyViewModel(ProfileViewModel.self)

// Pauses when the app enters background
@LazyViewModel(DashboardViewModel.self, observationPolicy: .pauseInBackground)

// Pauses when the scene is not active (background or inactive)
@LazyViewModel(SensorViewModel.self, observationPolicy: .pauseWhenInactive)
```

The default `.alwaysObserving` is correct for most ViewModels. Tearing down and re-establishing observation adds overhead that outweighs the near-zero cost of an idle callback. Use `.pauseInBackground` or `.pauseWhenInactive` only when observation drives high-frequency work (polling, real-time rendering) that wastes resources when the UI is not visible.

## stateBinding

`@LazyViewModel` generates a `stateBinding` property for two-way SwiftUI bindings:

```swift
@LazyViewModel(SettingsViewModel.self)
struct SettingsScreen: View {
  var content: some View {
    Toggle("Notifications", isOn: stateBinding.notificationsEnabled)
    TextField("Display Name", text: stateBinding.displayName)
  }
}
```

This is a `Binding<State>` created from `Bindable(viewModel).state`, giving you key-path access to individual state fields.
