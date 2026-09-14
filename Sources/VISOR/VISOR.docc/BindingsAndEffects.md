# Action bindings and managed effects

Keep control writes synchronous and choose an explicit lifetime and completion policy for asynchronous work.

## Bind controls to actions

Apply `@StateBinding` to a single-payload case in a ViewModel's nested
`Action` enum. Controls use the model-owned `bindings` namespace:

```swift
@MainActor
@Observable
@ViewModel
final class SettingsViewModel {
  final class State {
    private(set) var isFocusEnabled = false
  }

  enum Action {
    @StateBinding(\State.isFocusEnabled)
    case focusChanged(Bool)
  }

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    switch action {
    case .focusChanged(let enabled):
      updateState(\.isFocusEnabled, to: enabled)
    }
    return .completed
  }
}

@LazyViewModel(SettingsViewModel.self)
struct SettingsView: View {
  var content: some View {
    Toggle("Focus Mode", isOn: bindings.isFocusEnabled)
  }
}
```

A binding setter immediately calls `handle(_:)` with the proposed value and
discards its returned completion. The
handler decides whether to reject, normalise, or commit it. There is no task,
implicit mutation, deduplication, or initial action dispatch. Every write is an
event, including a write equal to the current value. Labelled payloads, such as
`case focusChanged(enabled: Bool)`, are also supported.

Use `updateState` to commit inside the handler. Source projections, `updateState`
and raw `state[\.field]` writes never dispatch actions; they retain the ordinary
Observation and test-history instrumentation. Writing `bindings.field` inside
its own handler would dispatch the action again and recurse.

Only properties selected by `@StateBinding` actions gain generated bindings.
Unannotated stored fields, including source-backed fields, have no binding
selector. Omitting or removing an annotation therefore causes a compile error
at the binding use rather than silently changing its write behaviour. Declare
an action even when its handler only assigns the value; use local SwiftUI
`@State` for input owned solely by the view. This constrains generated bindings,
not deliberate calls to `updateState` or raw State mutation APIs.

The key path must be `\State.field`, selecting one supported top-level stored
field or synchronous get-only computed property with an accessible getter.
The property must be declared directly in State, not an extension or conditional
compilation block. Nested key paths, subscripts, stored constants, writable
computed properties, and async or throwing getters are not supported.
Only one action may bind each property. Payload
types are checked by the compiler. Cases with multiple payloads, default values,
multiple declarations, or conditional compilation are diagnosed. This includes
an `Action` enum placed inside `#if`, `#elseif`, or `#else` in the ViewModel;
keep the enum and its annotated cases outside those blocks. Conditional Action
enums without binding annotations remain supported.

Every ViewModel action uses the same synchronous, nonthrowing
`handle(_ action: Action) -> ActionCompletion` contract, with or without bindings.
Swift checks the handler through protocol conformance; binding analysis does not
restrict the spelling of its return type. Move asynchronous work into an effect
owner and return its completion; no separate reducer or dispatch API is required.

### Bind a computed projection

Keep derived values get-only and route proposed writes to the action that owns
their meaning:

```swift
@MainActor
@Observable
@ViewModel
final class PickerViewModel {
  enum Sheet { case picker, settings }

  final class State {
    private(set) var activeSheet: Sheet?
    var isPickerPresented: Bool { activeSheet == .picker }
  }

  enum Action {
    @StateBinding(\State.isPickerPresented)
    case pickerPresentationChanged(Bool)
  }

  @discardableResult
  func handle(_ action: Action) -> ActionCompletion {
    switch action {
    case .pickerPresentationChanged(let presented):
      guard !presented, state.activeSheet == .picker else { return .completed }
      updateState(\.activeSheet, to: nil)
    }
    return .completed
  }
}

// Inside @LazyViewModel content:
// .sheet(isPresented: bindings.isPickerPresented) { PickerContent() }
```

Only annotated computed properties gain model binding selectors. Their getter
reads the authored property; their setter synchronously dispatches the action.
VISOR generates no inverse setter, backing value, or observation subscription.
Observation tracks the stored dependencies actually read by the getter; it does
not make a nested member of a value-type stored field independently observable.

The computed property remains get-only and gains no State mutation selector,
so `updateState(\.isPickerPresented, to: false)` and strict `hasExactChanges`
expectations for it fail to compile. Commit and
assert changes to `activeSheet` instead. Computed reads do not add mutation-history
entries; only the underlying stored-field assignments are recorded.

### Identity and construction

Each model lazily retains one ``ViewModelBindings`` value backed by a stable
reference root. Repeated access and copies share that root. SwiftUI bindings
project through generated key paths, not per-access `Binding(get:set:)`
closures. Typed static descriptors infer field types from State getters and
forward writes directly to the model; there is no action dictionary, type-erased
dispatch, or route registration.

The root retains State and holds the model weakly. Retaining a binding cannot
retain the model. After the model deinitialises, reads still access the retained
State and all binding writes do nothing. Binding creation does not read field
values or dispatch initial actions.

Both synthesised and authored initialisers work without connection hooks or
factory preparation. `@LazyViewModel` exposes `bindings` as a convenience for
`viewModel.bindings`. Use this retained namespace rather than constructing
`ViewModelBindings(model)` in a view body.

State contains only values, Observation and mutation recording—not its owner's
action routes. Even if two models share State, each binding dispatches only to
its own model. Raw `Bindable(model.state)[\.field]` writes remain ordinary
stored-field mutations and **never** invoke an annotated action. Controls that
dispatch actions must use `model.bindings.field`.

## Dispatch and join an action

`handle(_:)` accepts an action synchronously on MainActor. Return `.completed`
for synchronous work, including a rejected proposal with nothing to await.
Return an effect handle's `.completion` for asynchronous work:

```swift
@discardableResult
func handle(_ action: Action) -> ActionCompletion {
  switch action {
  case .nameChanged(let name):
    updateState(\.name, to: name)
    return .completed
  case .save:
    let name = state.name
    return writes.enqueue(for: self) { [service] in
      try await service.save(name)
    } receive: { model, result in
      model.applySaveResult(result)
    }.completion
  }
}

model.handle(.save)              // Dispatch; the owner keeps the work alive.
await model.handle(.save).wait() // Dispatch another action and join its work.
```

Each call dispatches a new action. To join an action already dispatched, retain
its returned completion and call `await completion.wait()`. Copies and multiple
waiters all join the same work. From another actor, reaching `handle(_:)` itself
requires an actor hop; that is separate from waiting for its accepted work.

``ActionCompletion`` is join-only: termination is not success. It joins operation
unwinding and any permitted synchronous result delivery. Cancelled or superseded
submissions skip receiver delivery. Keep domain outcomes and failure policy in
the interactor or service; the ViewModel maps those outcomes into presentation
State. Expose a result-bearing domain operation when a caller needs an output or
error. The original effect handle retains its `result`, `value()` and explicit
`cancel()` APIs.

Dropping completion does not cancel work. Cancelling a waiter neither cancels
the command nor abandons the join. It does not extend the effect owner's lifetime;
releasing the owner still requests cancellation. If a cancelled operation never
unwinds, its completion never finishes.

For an action that submits several operations, return
`ActionCompletion.all([first.completion, second.completion])`. This joins all
supplied work without starting tasks or changing its scheduling policy. An empty
collection is complete. Unrelated work and future submissions are never included.
Do not await an action's completion from work included in that completion.

The handler must return the work it promises to join. Returning `.completed`
after starting asynchronous work deliberately excludes that work. Unstructured
tasks spawned by an operation or its receiver are also excluded. Completion
adds no automatic source fence; `test.perform` adds one for participating sources.

## Choose an effect owner

Retain one owner per independent responsibility:

| Owner | Submission | Behaviour |
|---|---|---|
| `LatestEffect` | `run` | Cancels the previous invocation; only the current result is delivered |
| `SerialEffectQueue` | `enqueue` | Every accepted operation runs in FIFO order, including across awaits and failures |
| `ConcurrentEffects` | `run` | Independent operations may overlap; none replaces another |

All three owners are MainActor-isolated. Their asynchronous operation closures
start on MainActor; move CPU-intensive preparation to an appropriately isolated
service. `async` alone does not move synchronous work off the main actor.

### Prepare, then receive

The common API captures dependencies for preparation and supplies a weakly held
target only when applying the result:

```swift
private let search = LatestEffect()

func searchChanged(_ query: String) {
  search.run(for: self) { [service] in
    try await service.search(query)
  } receive: { model, result in
    switch result {
    case .success(let items):
      model.updateState(\.items, to: items)
    case .failure(let error):
      model.presentSearchFailure(error)
    }
  }
}
```

A nonthrowing operation passes its output directly to `receive`. A throwing
operation passes `Result<Output, any Error>`. Receiver callbacks are synchronous
on MainActor, with no suspension between the currentness check and delivery.
Cancellation and supersession suppress both success and failure delivery, even
if the operation ignores cancellation. They remain visible through the handle.
A thrown `CancellationError` is also treated as cancellation, not a domain error.

`for: self` does not retain the model during preparation. Do not undo that
guarantee by capturing `self` in either closure. Capture the required service
and input values explicitly; use the receiver's model parameter for commits.
Outputs are `Sendable` and must not themselves retain an owner whose lifetime
should end independently.

The overload without a receiver is useful for independent side effects or for
callers that await the output. Failures remain on the handle; failures without
a failure-capable receiver also produce a generic system-log diagnostic. The
diagnostic does not expose the error's potentially sensitive contents.

### Toggle on and off

Use replacement for preparation and explicit cancellation when turning off:

```swift
private let focusPreparation = LatestEffect()

@discardableResult
func handle(_ action: Action) -> ActionCompletion {
  switch action {
  case .focusChanged(let enabled):
    updateState(\.isFocusEnabled, to: enabled)
    guard enabled else {
      focusPreparation.cancel()
      updateState(\.focusConfiguration, to: nil)
      return .completed
    }

    return focusPreparation.run(for: self) { [focusService] in
      try await focusService.prepareConfiguration()
    } receive: { model, result in
      model.applyFocusPreparation(result)
    }.completion
  }
}
```

Rapid on/off/on input commits immediately. The cancelled preparation cannot
later overwrite the current configuration through its receiver. The next
`run` is reusable after cancellation.

Turning off returns `.completed` after requesting cancellation and clearing the
configuration; it does not join the previous preparation's unwinding. Its
original completion can still join that work. If turning off must promise that
cleanup has finished, retain and return that preparation's completion instead.

Cancellation is cooperative: old preparation can overlap newer preparation
until it unwinds. Receiver protection cannot undo external side effects already
performed by the operation. Do not use latest-wins for ordered persistence or
operations where every event must be attempted.

Replacement is registered before the previous operation is cancelled. If a
cancellation callback synchronously submits newer work to the same effect,
that re-entrant submission becomes current and supersedes the incoming work.

### Preserve every accepted event

Capture each accepted value when submitting to a serial queue:

```swift
private let writes = SerialEffectQueue()

func saveFocusPreference(_ enabled: Bool) -> EffectHandle<Void> {
  writes.enqueue { [preferences] in
    try await preferences.saveFocusEnabled(enabled)
  }
}
```

Do not reread `state.isFocusEnabled` inside a queued closure: several queued
events could then save the same later value. The queue awaits each operation
and its synchronous receiver before starting the next. A failure does not stop
later operations. Cancelling a running operation does not allow the next one
to start until the cancelled operation has unwound.

The default queue is unbounded. `SerialEffectQueue(capacity: 32)` bounds all
outstanding work, including the running operation. A full queue does not start
the submitted operation: its handle fails with `EffectQueueFullError` and a
failure-capable receiver is notified synchronously during `enqueue`. This is
rejection, not backpressure; choose a capacity and handle admission failures
deliberately.

Starting or cancelling a pending entry removes its ID from the queue immediately.
A continuously occupied queue retains bookkeeping for pending work, rather
than accumulating IDs from completed or cancelled submissions.

Queues are in-memory, not durable delivery systems. Every accepted operation is
attempted only while the queue remains alive and is not explicitly cancelled.
Keep a queue in a service if work must outlive a screen; use persisted jobs if
it must survive process termination. The API does not guarantee successful or
exactly-once external side effects.

## Completion and cancellation

Every submission returns an `EffectHandle<Output>` identifying that exact
invocation:

```swift
let handle = writes.enqueue { [preferences] in
  try await preferences.saveFocusEnabled(true)
}
try await handle.value()
```

`value()` returns the output or throws the operation's error,
`CancellationError`, or `EffectSupersededError`. `await handle.result` provides
an explicit `EffectOutcome`: `.success`, `.failure`, `.cancelled`, or
`.superseded`. Completion includes the operation unwinding and its synchronous
receiver returning. It does not include unstructured tasks spawned by either
closure. A cancelled operation that never unwinds never completes its handle.

`handle.cancel()` affects only that invocation. Dropping a handle does not
cancel its work. Cancelling a task waiting for completion does not cancel the
operation or abandon the wait. The first explicit cancellation or supersession
reason wins; cancelling a completed handle does not change its outcome.

`LatestEffect.cancel()` and the other owners' `cancelAll()` request cancellation
of their outstanding work. Pending queue entries can complete cancellation
without starting. Releasing an owner requests cancellation of all its running
and pending work; a retained handle can still join that work afterwards.

`await owner.finish()` joins a snapshot of outstanding submissions when the call
begins, including superseded preparations still unwinding. It does not wait for
future submissions, close admission, or aggregate errors. Inspect individual
handles when errors matter. Never await a queue's `finish()` or an invocation's
own handle from that invocation: doing so would wait on itself.

### Intermediate commits

Prefer the receiver API for one final commit. For multi-stage preparation,
`LatestEffect.runWithContext` provides a currentness check:

```swift
search.runWithContext { [weak self, service] context in
  let cached = await service.cachedResults()
  try context.checkCancellation()
  self?.updateState(\.items, to: cached)

  let fresh = try await service.refreshResults()
  try context.checkCancellation()
  self?.updateState(\.items, to: fresh)
}
```

Check after every suspension and commit synchronously after the check. The
low-level API does not automatically protect intermediate writes or retain the
target weakly for you.

## Test complete effects

`test.perform(.action)` dispatches synchronously, joins the returned
`ActionCompletion`, then fences participating sources. Assert synchronous
acceptance and asynchronous result delivery in one window:

```swift
try await observe(model) { test in
  await test.perform(.save)
  // Assert committed State history here.
}
```

For result-bearing methods or binding-driven tests, explicitly join an exact
handle or the relevant owner's snapshot inside the observation window:

```swift
try await observe(model) { test in
  try await test.perform {
    let handle = model.saveFocusPreference(true)
    try await handle.value()
  }

  // Assert committed State history here.
}
```

Use `ControllableOperation` from `VISORTesting` to control start, cancellation,
and resolution without sleeps. Resolve non-cooperative work before awaiting its
cancelled or superseded handle.
