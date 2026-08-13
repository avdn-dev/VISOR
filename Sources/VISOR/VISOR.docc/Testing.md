# Testing

Fence structured actions, inspect complete State histories, and generate isolated service doubles.

## Products and imports

VISOR 11 separates testing by responsibility:

- `VISORTesting` integrates the source-backed ViewModel runtime with Swift Testing. It re-exports `VISOR` and Swift Testing.
- `VISORTestDoubles` provides stub and spy macros without depending on `VISOR`, `VISORObservation`, SwiftUI, or Swift Testing.

A ViewModel test can import both when it needs both capabilities:

```swift
import VISORTesting
import VISORTestDoubles
```

A service or preview-fixture module that only declares generated doubles should import only `VISORTestDoubles`.

## Observation tests

`observe` owns one source-backed observation session for the duration of its body:

```swift
@Test
@MainActor
func refreshChangesPhaseAndCount() async throws {
  let service = SyncService(snapshot: .initial)
  let sut = SyncViewModel(service: service)

  try await observe(sut) { test in
    await test.perform(.refresh)

    test.expect(
      \.phase,
      hasExactChanges: [.loading, .loaded])
    test.expect(
      \.count,
      hasExactChanges: [1])
    test.expect(
      \.error,
      alwaysSatisfies: { $0 == nil })
  }
}
```

Before entering the body, `observe` opens every generated source, reconciles its finite startup frontier, applies all initial bindings, awaits all immediate initial reactions, and verifies whole-session readiness. This removes the usual race between starting observation and performing the first action.

Only one `observe` scope may reserve a State identity at a time. The `ObservationTest` handle is valid only inside its body; escaping and later using it records a Swift Testing issue. Teardown normally cancels and joins the session before `observe` returns.

## perform

Each `perform` creates one action window:

1. atomically capture every supported State baseline and activate the journal;
2. run and await the structured operation;
3. pause every participating source at a finite frontier;
4. drain and acknowledge the resulting generated bindings and reactions; and
5. close a replayable history window.

Dispatch the ViewModel's `Action` directly:

```swift
await test.perform(.refresh)
```

Or fence an arbitrary MainActor operation:

```swift
await test.perform {
  sut.state[\.query] = "Swift"
}
```

Throwing and result-bearing operations preserve their ordinary control flow:

```swift
let value = try await test.perform {
  try await sut.loadValue()
}
```

The structured operation's return is the action boundary. Fire-and-forget work launched inside it does not extend the window; a later mutation is outside matching input and is retained only as bounded diagnostic context. Await domain completion directly rather than adding a sleep or polling the State.

One closed window supports several non-consuming expectations. A later `perform` starts a new baseline and history.

## expect

Expectations use generated flat selectors with the spelling `\.field`. They inspect the most recently closed `perform` window and report mismatches through `Issue.record` at the expectation call site.

### Exact distinct history

`hasExactChanges` requires the complete distinct post-baseline trace to equal the expected array:

```swift
test.expect(
  \.phase,
  hasExactChanges: [.loading, .loaded])

test.expect(
  \.error,
  hasExactChanges: []) // no distinct change
```

Adjacent equal commits are collapsed for an `Equatable` field. An expected array containing adjacent duplicate values is invalid because it cannot describe the distinct trace. This is exact matching, not subsequence or eventual-value matching.

### Baseline-inclusive invariant

`alwaysSatisfies` requires the action baseline and every completed commit to satisfy a predicate:

```swift
test.expect(
  \.progress,
  alwaysSatisfies: { (0...1).contains($0) })
```

Use it for positive invariants and non-`Equatable` value fields. It is not a substitute for exact non-`Equatable` history.

### History boundary

Strict history applies to supported top-level stored State fields. It does not project nested members or computed properties. Direct reference-valued fields and values dynamically containing an outer reference are rejected rather than compared by mutable alias. Stable value semantics inside optionals and containers remain the caller's responsibility.

Production Observation still supports a reference field; this restriction applies only to strict historical matching of the reference itself.

## Infrastructure failures

VISOR records one Swift Testing issue for an expectation mismatch or an observation-infrastructure failure. A running scope is poisoned after infrastructure failure so later operations cannot appear trustworthy. Examples include source termination, State identity replacement, overlapping scopes, journal exhaustion, and use of an ended handle.

Cancellation remains cancellation, and an error thrown by the test body or performed domain operation remains that error. A result already produced by a result-bearing operation is not replaced with a fabricated infrastructure result.

## Generated test doubles

Import `VISORTestDoubles` where the protocol and generated peers are declared.

### @GenerateStub

Apply `@GenerateStub` to a protocol to create `Stub<Name>` with configurable properties, return values, errors, and implementations:

```swift
import VISORTestDoubles

@GenerateStub
protocol ProfileService {
  var name: String { get }
  func load() async throws -> [Profile]
}

let stub = StubProfileService()
stub.name = "Preview"
stub.loadReturnValue = [.preview]
```

Generated defaults cover common scalar, optional, collection, `Data`, `Decimal`, and finished `AsyncStream` types. A custom property type without a known default uses an implicitly unwrapped optional; a custom method result fails fast until configured.

Provide explicit defaults with qualified expressions:

```swift
@GenerateStub
protocol ThemeService {
  @DefaultValue(Theme.system)
  var theme: Theme { get }

  @DefaultReturn(Theme.system)
  func resolvedTheme() -> Theme
}
```

Use `Theme.system`, not an unqualified `.system`, because attribute expressions do not have enough contextual type information.

### @GenerateSpy

Apply `@GenerateSpy` to create `Spy<Name>` with configurable results and ordered call recording:

```swift
@GenerateSpy
protocol ProfileService {
  func load() async throws -> [Profile]
  func save(_ profile: Profile) async throws
}

let spy = SpyProfileService()
spy.loadReturnValue = [.preview]

_ = try await spy.load()

#expect(spy.loadCallCount == 1)
#expect(spy.calls == [.load])
```

Depending on the protocol declaration, generated members include call counts, last received arguments, invocation histories, configurable return/error values and implementation closures, plus an ordered `Call` enum log.

Protocols with associated types are unsupported. Static members and subscripts are skipped with a diagnostic.

### Sendable doubles

Opt into synchronised, checked `Sendable` generation when a double crosses isolation domains:

```swift
@GenerateSpy(.sendable)
nonisolated protocol AnalyticsService: Sendable {
  @concurrent
  func load(period: DateInterval) async throws -> Snapshot
}
```

The generated double stores all mutable configuration and call history in one synchronised value. User implementation closures run after its lock is released, so they may suspend or re-enter the double.

The conformance is checked rather than `@unchecked`. Every retained property, result, error, recorded argument, and implementation closure must therefore be `Sendable`. A generic argument constrained to `Sendable` can be retained through existential erasure; an unconstrained generic is supported only where the generated double does not retain it.

These concepts are independent:

| Concept | Meaning |
|---|---|
| `.sendable` | Synchronises generated mutable State and gives the double checked `Sendable` conformance |
| `nonisolated` | Keeps the declaration independent of a consumer target's default actor isolation |
| `@concurrent` | Gives an eligible async protocol requirement its declared execution behaviour |

The trait does not infer protocol isolation or add `@concurrent`. Unqualified `@GenerateStub` and `@GenerateSpy` generation keeps its ordinary unsynchronised behaviour.

## Previewing Content views

The View/Content split usually needs no service double at all:

```swift
#Preview("Loaded") {
  ProfileContent(
    state: .init(name: "Alice", email: "alice@example.com"),
    onAction: { _ in })
}
```

Content views receive State and action closures as plain inputs. Reserve generated doubles for preview or test code that intentionally exercises the integration-owning ViewModel or service boundary.
