import Observation

/// Implementation macro applied to a ViewModel's nested State type.
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
  module: "VISORMacros",
  type: "ViewModelStateMacro")

/// Implementation macro applied to stored fields of a generated State type.
@attached(
  accessor,
  names: named(init), named(get), named(set), named(_modify))
@attached(peer, names: prefixed(_))
public macro _ViewModelStateField() = #externalMacro(
  module: "VISORMacros",
  type: "ViewModelStateFieldMacro")
