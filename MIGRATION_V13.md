# Migrating to VISOR 13

VISOR 13 introduces two source and behavioural breaking changes from VISOR 12:
action handling uses synchronous dispatch returning an explicit, join-only
`ActionCompletion`, and lazy views separate persistent SwiftUI presentation from
prepared feature content. Migrate both the action handlers and their views as
part of the same upgrade.

## Replace the handler contract

The protocol requirement changes from:

```swift
func handle(_ action: Action) async
```

to:

```swift
@discardableResult
func handle(_ action: Action) -> ActionCompletion
```

Previously, synchronous Void methods could also satisfy the async requirement.
Neither those methods nor async handlers satisfy the new contract. Every model
with actions uses one synchronous, nonthrowing handler, whether or not it has
`@StateBinding` annotations. Read-only models with `Action == Never` still need
no handler. Hand-written protocol conformers must adopt the same signature.

## Return the action's completion

Commit immediate changes synchronously and return `.completed`. For asynchronous
work, submit to a retained effect owner and return the handle's `.completion`:

```swift
@discardableResult
func handle(_ action: Action) -> ActionCompletion {
  switch action {
  case .nameChanged(let name):
    guard !name.isEmpty else { return .completed }
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

private let writes = SerialEffectQueue()
```

Capture each invocation's accepted input before submitting it; do not reread
later State inside queued work. Use `LatestEffect` for replaceable preparation,
`SerialEffectQueue` for ordered submissions, and `ConcurrentEffects` for
independent work. The weak receiver form avoids retaining the model during
preparation, provided neither closure captures the model strongly.

If a model previously authored synchronous and asynchronous `handle` overloads
plus a private `dispatch` method, consolidate their switch into the one handler.
Return `.completed` instead of `nil`; return `handle.completion` instead of an
optional effect handle. Remove the forwarding overloads. Do not use an owner's
`finish()` to implement per-action completion: it includes unrelated outstanding
work on that owner.

For several submissions belonging to one action, return
`ActionCompletion.all([first.completion, second.completion])`. Composition joins
only those submissions and starts no additional tasks. `.completed` also creates
no task. Completion accepts any effect output type without exposing it through
the action handler.

## Audit every call site

For immediate UI dispatch, remove unnecessary task wrappers:

```swift
// Before
Task { await model.handle(.save) }

// After, on MainActor
model.handle(.save)
```

For callers that require the action's work to finish:

```swift
// Before
await model.handle(.save)

// After
await model.handle(.save).wait()
```

**Keeping the old `await model.handle(...)` spelling does not preserve waiting
for asynchronous work.** It can still compile: `await` may only perform the
MainActor hop, or produce an unnecessary-await warning on MainActor. Audit
refresh controls, lifecycle tasks, sequencing code and tests explicitly.

Each handler call dispatches a new action. To join a previously dispatched
action, retain its completion and call `await completion.wait()`; do not dispatch
the action a second time. Copies and multiple waiters join the same work.

`@discardableResult` belongs on authored implementations as shown above, so
concrete callers can deliberately ignore completion without a warning.

## Preserve intended cancellation and error behaviour

Previously, directly awaited async handler work could inherit cancellation from
its caller. A managed command has its owner's lifetime instead. Dropping its
completion, or cancelling a task waiting for it, does not cancel the command or
abandon the join. Releasing the effect owner still requests cancellation. Retain
the owner in a service when the work must outlive the screen.

Completion means termination, not success. It joins operation unwinding and any
permitted synchronous receiver delivery. Cancelled or superseded submissions
skip receiver delivery. It excludes unstructured tasks spawned by either closure.
A non-cooperative operation that never unwinds never completes. Keep domain
outcomes and failure policy in the interactor or service; the ViewModel maps those
outcomes into presentation State. Expose a result-bearing domain operation when
a caller needs an output or error. Existing effect handles retain their `value()`,
`result` and `cancel()`.

Returning `.completed` after requesting cancellation means the request is done,
not that earlier work has unwound. If an action must promise that cleanup has
finished, retain and return that submission's completion. Never join a completion
from work included in it.

## Update observation tests

`await test.perform(.action)` now joins the handler's returned completion before
fencing participating sources. Existing assertions can include both immediate
acceptance and asynchronous result delivery without custom dispatch helpers.

Closure-based tests still await only the supplied operation. Change
`await model.handle(.action)` inside such a closure to
`await model.handle(.action).wait()`. Binding setters deliberately discard
completion; join the relevant owner or an explicitly retained handle when a
binding-driven test needs to include asynchronous work.

A completion is not itself a source fence. `test.perform` adds that fence after
joining the action. Returning `.completed` while launching asynchronous work
excludes that work from the action window.

## Replace the lazy view content property

Replace `var content: some View` with a method taking explicit nonoptional State:

```swift
@LazyViewModel(LibraryViewModel.self)
struct LibraryView: View {
  func readyContent(state: LibraryViewModel.State) -> some View {
    LibraryContent(state: state, onAction: { send($0) })
  }
}
```

VISOR generates `content`, the lifecycle slot, and a default `body { content }`.
The view's generated `state` property is optional. It is `nil` before model
construction, during preparation, while paused and after infrastructure failure.
The explicit `state` parameter of `readyContent` shadows that optional property.
There are no implicit nonoptional `viewModel` or `bindings` properties.

## Keep persistent presentation in body

Write an ordinary `body` to attach titles, toolbars and presentation configuration
outside the lifecycle slot:

```swift
var body: some View {
  content
    .navigationTitle(state?.title ?? "Library")
    .toolbar {
      Button("Refresh") { send(.refresh) }
        .disabled(state?.canRefresh != true)
    }
}
```

A navigation stack owned by the destination also belongs around `content`.
There is no automatic extraction of navigation modifiers from `readyContent`.
Keep toolbar item declarations stable while their values and enablement change.
Dismissal that requires model cleanup or domain guards must preserve those
actions. Provide an appropriate way out of failed preparation.

## Request bindings explicitly

Add a labelled `bindings` parameter when the prepared content contains controls:

```swift
func readyContent(
  state: SettingsViewModel.State,
  bindings: ViewModelBindings<SettingsViewModel>
) -> some View {
  Toggle("Enabled", isOn: bindings.isEnabled)
}
```

These bindings share the model's binding root and preserve transactions, but
reject writes after their observation generation ends, including after a later
generation becomes ready. Use the newly supplied bindings after resumption.

Integration that needs additional model presentation APIs can request an explicit
`viewModel: SettingsViewModel` parameter alongside `state`. That parameter is
only supplied to prepared content. Move ordinary actions to `send` and retain
view-specific dependencies in the owning view.

## Dispatch through send

`send(_:)` accepts actions only while the current owner is ready. It returns the
accepted handler's `ActionCompletion`, or `nil` for rejected dispatch. It never
queues actions for later. Use `{ send($0) }` for a Void action closure.

Await an accepted action with `await send(.save)?.wait()`. Rejected dispatch is
not an accepted no-op; check the optional completion when admission matters.
Direct model calls keep their existing semantics and do not acquire this UI
readiness check automatically.

## Move custom phase views into properties

Replace the macro's `pending:` and `failure:` arguments with optional
`pendingContent` and `failureContent` properties. Pending content now covers the
first render before model construction as well as observation preparation.
Defaults remain transparent pending content and a generic unavailable view.

The persistent body remains mounted through preparation, readiness, pause and
failure. Ready content is still withdrawn during explicit scene pauses and
rebuilt after fresh reconciliation. Navigation covering and tab switches retain
the model and observation lifetime. Actual removal cancels and joins observation.

## Unchanged APIs

- `@StateBinding(\State.field)` and `model.bindings.field` retain their syntax
  and immediate dispatch behaviour. Generated setters discard completion.
- State identity, mutation selectors and source observation are unchanged.
- Effect admission, ordering, replacement and explicit cancellation policies
  are unchanged; completion does not introduce another scheduler.
- The four products, deployment targets and final ViewModel requirement are
  unchanged.
