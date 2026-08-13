import Observation
import VISORObservation

/// Stage B proof macro. The production spelling remains `@ViewModel`; the
/// underscored companion macros are implementation details emitted by it.
@attached(
  member,
  names: named(_visorObservationOwnership), named(_visorBuildObservationRecipe))
@attached(memberAttribute)
@attached(extension, conformances: ViewModel)
public macro ViewModel() = #externalMacro(
  module: "V11CompileProofMacros",
  type: "ViewModelMacro")

/// Stage E compile-proof spelling. The generated body owns the package runtime
/// through `_ViewModelObservationHost`; consumers only provide construction and
/// content.
@attached(
  member,
  names: named(body), named(_viewModel), named(viewModel), named(state))
public macro LazyViewModel<VM: ViewModel>(
  _: VM.Type,
  observationPolicy: ObservationPolicy = .alwaysObserving
) = #externalMacro(
  module: "V11CompileProofMacros",
  type: "LazyViewModelMacro")

@attached(peer)
public macro Bound<Root, Snapshot: Sendable, Value>(
  source: KeyPath<Root, ObservationSource<Snapshot>>,
  selecting: KeyPath<Snapshot, Value>
) = #externalMacro(
  module: "V11CompileProofMacros",
  type: "BoundMacro")

@attached(peer)
public macro Bound<Root, Value: Sendable>(
  source: KeyPath<Root, ObservationSource<Value>>
) = #externalMacro(
  module: "V11CompileProofMacros",
  type: "BoundMacro")

@attached(peer)
public macro Reaction<Root, Snapshot: Sendable, Value>(
  source: KeyPath<Root, ObservationSource<Snapshot>>,
  selecting: KeyPath<Snapshot, Value>
) = #externalMacro(
  module: "V11CompileProofMacros",
  type: "ReactionMacro")

@attached(peer)
public macro Reaction<Root, Value: Sendable>(
  source: KeyPath<Root, ObservationSource<Value>>
) = #externalMacro(
  module: "V11CompileProofMacros",
  type: "ReactionMacro")

@attached(
  member,
  names:
    named(_$observationRegistrar),
    named(access),
    named(withMutation),
    named(_visorShouldNotifyObservers),
    named(_visorMutationRecorder),
    named(_VISORSelectors),
    named(_visorSelectors),
    named(_visorAllFields),
    arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Observable, _ViewModelState)
public macro _ViewModelState() = #externalMacro(
  module: "V11CompileProofMacros",
  type: "ViewModelStateMacro")

@attached(
  accessor,
  names: named(init), named(get), named(set), named(_modify))
@attached(peer, names: prefixed(_))
public macro _ViewModelStateField() = #externalMacro(
  module: "V11CompileProofMacros",
  type: "ViewModelStateFieldMacro")
