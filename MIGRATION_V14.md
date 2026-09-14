# Migrating to VISOR 14

VISOR 14 separates a screen's persistent SwiftUI presentation from its prepared
feature content. This guide assumes the action-completion API described in
[Migrating to VISOR 13](MIGRATION_V13.md).

## Replace the content property

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
