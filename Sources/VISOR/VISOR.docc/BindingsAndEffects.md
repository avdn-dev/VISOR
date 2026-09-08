# Action bindings and managed effects

Keep control writes synchronous and choose an explicit lifetime and completion policy for asynchronous work.

## Bind controls to actions

VISOR 11.1 adds `@StateBinding` to a single-payload case in a ViewModel's nested
`Action` enum. The control still uses a selector binding over the same stored
State instance:

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

  func handle(_ action: Action) {
    switch action {
    case .focusChanged(let enabled):
      updateState(\.isFocusEnabled, to: enabled)
    }
  }
}

@LazyViewModel(SettingsViewModel.self)
struct SettingsView: View {
  var content: some View {
    Toggle("Focus Mode", isOn: bindableState[\.isFocusEnabled])
  }
}
```

A binding setter immediately calls `handle(_:)` with the proposed value. The
handler decides whether to reject, normalise, or commit it. There is no task,
implicit mutation, deduplication, or initial action dispatch. Every write is an
event, including a write equal to the current value. Labelled payloads, such as
`case focusChanged(enabled: Bool)`, are also supported.

Use `updateState` to commit inside the handler. An annotated `state[\.field]`
write dispatches the action again and would recurse. Source projections and
`updateState` bypass action routing but retain the ordinary Observation and
test-history instrumentation. Unannotated selectors retain their direct-write
behaviour.

The key path must be `\State.field`, selecting one supported top-level stored
field with an accessible getter. Only one action may bind each field. Payload
types are checked by the compiler. Cases with multiple payloads, default values,
multiple declarations, or conditional compilation are diagnosed.

Opting in requires a synchronous, nonthrowing `handle(_ action: Action)` in the
ViewModel declaration. Existing async handlers remain supported for ViewModels
without action bindings. Move asynchronous work from a binding handler into an
effect owner; no separate reducer or dispatch API is required.

### Identity and construction

Bindings project through generated key paths over the stable `let state`.
`viewModel.bindableState` creates a lightweight `Bindable` wrapper, not an
ad-hoc `Binding(get:set:)`. The per-State action routes are connected once and
retain their ViewModel weakly. Retaining a binding cannot retain the ViewModel;
writes after its owner has deinitialised do nothing.

Synthesised initialisers connect the routes after initialisation. Authored
initialisers are not rewritten: use `viewModel.bindableState` or construct the
model through `ViewModelFactory`, including the normal `@LazyViewModel` path.
Those surfaces connect the routes before returning a binding or model.
Creating `Bindable(model.state)` yourself before either connection, or writing
an annotated selector on a standalone State, fails a descriptive precondition.
Use `viewModel.bindableState` as the normal binding entry point. Raw State reads
and `updateState` do not need a connection. A State cannot be shared by multiple
action-owning ViewModels.

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

func handle(_ action: Action) {
  switch action {
  case .focusChanged(let enabled):
    updateState(\.isFocusEnabled, to: enabled)
    guard enabled else {
      focusPreparation.cancel()
      updateState(\.focusConfiguration, to: nil)
      return
    }

    focusPreparation.run(for: self) { [focusService] in
      try await focusService.prepareConfiguration()
    } receive: { model, result in
      model.applyFocusPreparation(result)
    }
  }
}
```

Rapid on/off/on input commits immediately. The cancelled preparation cannot
later overwrite the current configuration through its receiver. The next
`run` is reusable after cancellation.

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

`test.perform(.action)` awaits the handler, not unrelated managed tasks spawned
by a synchronous handler. Join an exact handle, or the relevant owner's
snapshot, inside the observation window:

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
