/// Routes writes to a State selector into the annotated action synchronously.
///
/// Apply to a single-payload case in a `@ViewModel`'s nested `Action` enum.
/// The model must implement synchronous `handle(_:)`. The handler owns the
/// commit through `updateState(_:to:)`; rejecting a proposed value is allowed.
/// Source projections and `updateState` never dispatch a binding action.
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

/// Generated route storage. Public only for downstream macro expansion.
@attached(member, names: named(_visorStateBindingRoutes))
public macro _ViewModelStateBindings(_ fields: String...) = #externalMacro(
  module: "VISORMacros",
  type: "ViewModelStateBindingsMacro",
)
