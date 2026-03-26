# Testing

The observation assertion DSL and generated test doubles.

## Overview

VISOR provides two categories of testing support:

1. **Observation assertions** — `observing()` and ``Expectation`` for awaiting ViewModel state changes.
2. **Generated test doubles** — `@Stubbable` for preview stubs and `@Spyable` for test spies.

## Observation Assertions

### observing() and Expectation

`observing(_:body:)` starts observation on a ViewModel, provides an ``Expectation`` to the body, and cancels observation when the body returns:

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

`observing()` calls `startObserving()` in a child task that is cancelled when the body returns. This scopes observation to the test assertion block.

### Assertion Methods

``Expectation`` provides three assertion methods, all called via `callAsFunction`:

| Method | Description |
|--------|-------------|
| `expect(\.prop, equals: value)` | Awaits until the property equals the expected value |
| `expect(\.prop, isNot: value)` | Awaits until the property does NOT equal the value |
| `expect(\.prop, satisfies: { ... })` | Awaits until the predicate returns `true` |

Each method observes the ViewModel property and returns as soon as the condition is met. Use Swift Testing's `@Test(.timeLimit(...))` to bound the wait — the DSL itself does not impose a timeout.

```swift
await observing(vm) { expect in
  // Exact match
  service.count = 42
  await expect(\.state.count, equals: 42)

  // Negation
  service.isLoading = false
  await expect(\.state.isLoading, isNot: true)

  // Predicate
  service.items = ["a", "b", "c"]
  await expect(\.state.items, satisfies: { $0.value?.count == 3 })
}
```

## @Stubbable

Apply to a protocol to generate a `Stub<Name>` class for previews and tests:

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

Methods with return values get a `<methodName>ReturnValue` property you can set. Void methods generate empty bodies.

### Custom Type Defaults

When a property type is a custom type without a known default (not `Bool`, `String`, `Int`, collections, optionals, etc.), the generated stub uses an implicitly unwrapped optional (IUO) — this is required for protocol conformance. Accessing it before configuration crashes at runtime.

When a method return type is a custom type, the generated stub uses an `Optional` variable guarded by `fatalError` with a descriptive message. This crashes fast with clear guidance if you forget to configure the return value.

A compiler note is emitted whenever either pattern is generated. To silence it and provide an explicit default, use `@StubbableDefault`:

```swift
@Stubbable
protocol AnimationService {
  @StubbableDefault(AnimationState.idle) var state: AnimationState { get }
  func currentTheme() -> Theme  // ← generates optional + fatalError guard
}
```

> Protocols with associated types are not supported (compile-time error). Subscripts and static members are skipped with a warning.

## @Spyable

Apply to a protocol to generate a `Spy<Name>` test double with call recording:

```swift
@Spyable
protocol ProfileService {
  func load() async throws -> [String]
  func save(_ name: String) async throws
}
// Generates: SpyProfileService
```

The generated spy is `@Observable` and includes:

| Property | Description |
|----------|-------------|
| `<method>CallCount: Int` | How many times the method was called |
| `<method>Received<Param>: T?` | Last received argument (single-parameter methods) |
| `<method>ReceivedInvocations: [T]` | All received arguments |
| `<method>ReceivedArguments: (tuple)?` | Last received arguments (multi-parameter methods) |
| `<method>ReturnValue: T` | Configurable return value |
| `Call` enum | One case per method, with associated values for arguments |
| `calls: [Call]` | Ordered log of all calls |

```swift
let spy = SpyProfileService()
spy.loadReturnValue = ["Alice"]
let names = try await spy.load()
#expect(spy.loadCallCount == 1)
#expect(spy.calls == [.load])
```

Properties use the same default value logic as `@Stubbable`, including `@StubbableDefault` support.

> Limitations: Same as `@Stubbable` — no associated types, subscripts/statics skipped.

## @StubbableDefault

Provides a custom default value for a protocol property or return value in generated stubs and spies. Use this when the type has no auto-detected default:

```swift
@Stubbable @Spyable
protocol ContentLoading: AnyObject {
  @StubbableDefault(LoadStatus.idle)
  var status: LoadStatus { get }
}
// StubContentLoading.status defaults to .idle
// SpyContentLoading.status defaults to .idle
```

> The expression must be fully qualified — `.idle` alone can't infer the type in attribute context. Use `LoadStatus.idle`, not `.idle`.

## Previewing with Content Views

The View/Content pattern makes previews trivial. Content views take state as plain parameters:

```swift
struct ProfileContent: View {
  let state: ProfileViewModel.State
  let onAction: (ProfileViewModel.Action) -> Void

  var body: some View {
    Text(state.name)
  }
}

#Preview("Loaded") {
  ProfileContent(
    state: .init(name: "Alice", email: "alice@example.com"),
    onAction: { _ in }
  )
}

#Preview("Loading") {
  DashboardContent(
    state: .init(items: .loading),
    onAction: { _ in }
  )
}
```

No factories, no services, no mocks — just static state.
