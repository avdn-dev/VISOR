import ExternalModelsNonisolated
import ExternalServices
import VISOR
import VISORObservation

@MainActor
public func compileExternalAccessBoundary() {
  let field = ExternalViewModel.State._visorSelectors.reference

  _ = field

  #if VISOR_PROBE_FIELD_NAME
  _ = field.name
  #endif

  #if VISOR_PROBE_FIELD_IDENTITY
  _ = field.identity
  #endif

  #if VISOR_PROBE_FIELD_ELIGIBILITY
  _ = field.isDirectReference
  #endif

  #if VISOR_PROBE_OBSERVATION_SESSION
  _ = _ObservationSession.self
  #endif

  #if VISOR_PROBE_OBSERVATION_LANE
  _ = _ObservationLane<Int>.self
  #endif

  #if VISOR_PROBE_OBSERVATION_RECIPE
  _ = _ObservationRecipe.self
  #endif

  #if VISOR_PROBE_RECIPE_VISITOR_INIT
  _ = _ObservationRecipeVisitor()
  #endif

  let source = ExternalSyncService().observationSource

  #if VISOR_PROBE_SOURCE_OPEN
  _ = try? source._visorOpen()
  #endif

  #if VISOR_PROBE_SOURCE_IDENTITY
  _ = source._visorIdentity
  #endif

  #if VISOR_PROBE_OBSERVATION_RUNTIME
  _ = _ObservationRuntime.self
  #endif
}
