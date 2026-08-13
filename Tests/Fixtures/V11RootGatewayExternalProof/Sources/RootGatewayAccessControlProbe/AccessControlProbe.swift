import RootGatewayModelsNonisolated
import VISOR

@MainActor
public func compileRootGatewayAccessBoundary() {
  typealias State = NonisolatedGatewayState

  let field: _StateField<State, Int> = State._visorSelectors.count
  let erased = State._visorAllFields[0]
  let sourceBackedView = NonisolatedSourceBackedView()

  _ = field
  _ = erased
  _ = sourceBackedView.body

  #if VISOR_PROBE_LAZY_VIEW_MODEL
  _ = sourceBackedView.viewModel
  #endif

  #if VISOR_PROBE_FIELD_NAME
  _ = field.name
  #endif

  #if VISOR_PROBE_FIELD_IDENTITY
  _ = field.identity
  #endif

  #if VISOR_PROBE_FIELD_ELIGIBILITY
  _ = field.isDirectReference
  #endif

  #if VISOR_PROBE_ERASED_NAME
  _ = erased.name
  #endif

  #if VISOR_PROBE_ERASED_IDENTITY
  _ = erased.identity
  #endif

  #if VISOR_PROBE_ERASED_READ
  _ = erased.read(from: State())
  #endif
}
