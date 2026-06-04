# Testing

The observation assertion DSL and generated test doubles.

## Overview

VISOR provides two categories of testing support:

1. **Observation assertions** — `observing()` and ``Expectation`` for awaiting ViewModel state changes.
2. **Generated test doubles** — `@GenerateStub` for preview stubs and `@GenerateSpy` for test spies.

## Observation Assertions

### observing() and Expectation

`observing(_:body:)` starts observation on a ViewModel, provides an ``Expectation`` to the body, and cancels observation when the body returns:

```swift
@Test(.timeLimit(.minutes(1)))
func updatesOnServiceChange() async throws {
  let spy = SpyProfileService()
  let vm = ProfileViewModel(profileService: spy)

  try await observing(vm) { expect in
    spy.name = "Alice"
    try await expect(\.state.name, becomes: "Alice")
  }
}
```

`observing()` calls `startObserving()` in a child task that is cancelled when the body returns. This scopes observation to the test assertion block.

### Assertion Methods

``Expectation`` provides streaming assertions via `callAsFunction`:

| Method | Description |
|--------|-------------|
| `try expect(\.prop, becomes: value)` | Awaits the next change and fails on any non-matching intermediate value |
| `try expect(\.prop, eventually: value)` | Awaits until the property reaches the expected value, tolerating intermediate values |

Each method observes the ViewModel property after the current value. Use `#expect` for snapshot assertions against the current state.

```swift
try await observing(vm) { expect in
  // Snapshot
  #expect(vm.state.count == 0)

  // Strict next change
  service.count = 42
  try await expect(\.state.count, becomes: 42)

  // Lenient wait through intermediate values
  service.count = 50
  service.count = 100
  try await expect(\.state.count, eventually: 100)
}
```

## @GenerateStub

Apply to a protocol to generate a `Stub<Name>` class for previews and tests:

```swift
@GenerateStub
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

A compiler note is emitted whenever either pattern is generated. Use `@DefaultValue` for properties and `@DefaultReturn` for method returns:

```swift
@GenerateStub
protocol AnimationService {
  @DefaultValue(AnimationState.idle) var state: AnimationState { get }
  @DefaultReturn(Theme.system) func currentTheme() -> Theme
}
```

> Protocols with associated types are not supported (compile-time error). Subscripts and static members are skipped with a warning.

## @GenerateSpy

Apply to a protocol to generate a `Spy<Name>` test double with call recording:

```swift
@GenerateSpy
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

Properties and method return values use the same default value logic as `@GenerateStub`, including `@DefaultValue` and `@DefaultReturn` support.

> Limitations: Same as `@GenerateStub` — no associated types, subscripts/statics skipped.

## @DefaultValue

Provides a custom default value for a protocol property in generated stubs and spies. Use this when the property type has no auto-detected default:

```swift
@GenerateStub @GenerateSpy
protocol ContentLoading: AnyObject {
  @DefaultValue(LoadStatus.idle)
  var status: LoadStatus { get }
}
// StubContentLoading.status defaults to .idle
// SpyContentLoading.status defaults to .idle
```

> The expression must be fully qualified — `.idle` alone can't infer the type in attribute context. Use `LoadStatus.idle`, not `.idle`.

## @DefaultReturn

Provides a custom default return value for a protocol method in generated stubs and spies. Use this when the return type has no auto-detected default:

```swift
@GenerateStub @GenerateSpy
protocol ContentLoading: AnyObject {
  @DefaultReturn(ContentSnapshot.empty)
  func snapshot() -> ContentSnapshot
}
// StubContentLoading.snapshotReturnValue defaults to .empty
// SpyContentLoading.snapshotReturnValue defaults to .empty
```

> The expression must be fully qualified — `.empty` alone can't infer the type in attribute context. Use `ContentSnapshot.empty`, not `.empty`.

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

No factories, no services, no mocks — just static state. For class-based `State`, use the initializer you define on the nested `State` class.
