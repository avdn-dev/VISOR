/// Routes writes through `viewModel.bindings` into the annotated action synchronously.
///
/// Apply to a single-payload case in a `@ViewModel`'s nested `Action` enum.
/// Only properties selected by this annotation gain generated model bindings.
/// The model implements synchronous `handle(_:)` returning `ActionCompletion`.
/// Binding setters discard that completion. The handler owns the
/// commit through `updateState(_:to:)`; rejecting a proposed value is allowed.
/// Source projections and `updateState` never dispatch a binding action.
/// Select a stored field or a synchronous, get-only computed property declared
/// directly in State. Computed bindings route writes only: the handler updates
/// their underlying stored fields, not the computed property itself.
///
/// ```swift
/// enum Action {
///   @StateBinding(\State.isEnabled)
///   case enabledChanged(Bool)
/// }
/// ```
@attached(peer)
public macro StateBinding<Root, Value>(
  _ field: KeyPath<Root, Value>
) = #externalMacro(module: "VISORMacros", type: "StateBindingMacro")
