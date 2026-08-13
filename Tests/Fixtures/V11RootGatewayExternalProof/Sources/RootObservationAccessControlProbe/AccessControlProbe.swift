import RootGatewayModelsNonisolated
import RootObservationConsumer
import VISOR
import VISORObservation

@MainActor
public func compileRootObservationAccessBoundary() {
  let channel = ObservationChannel(0)
  _ = channel.source.currentSnapshot()

  #if VISOR_PROBE_VISITOR_INIT
  _ = VISOR._ObservationRecipeVisitor()
  #endif

  #if VISOR_PROBE_SESSION
  _ = VISOR._ObservationSession.self
  #endif

  #if VISOR_PROBE_LANE
  _ = VISOR._ObservationLane<Int>.self
  #endif

  #if VISOR_PROBE_RECIPE
  _ = VISOR._ObservationRecipe.self
  #endif

  #if VISOR_PROBE_SOURCE_IDENTITY
  _ = channel.source._visorIdentity
  #endif

  #if VISOR_PROBE_RECIPE_FACTORY
  let consumer = RootObservationConsumer(initialValue: 0)
  let viewModel = NonisolatedSourceBackedViewModel(consumer: consumer)
  _ = viewModel._visorMakeObservationRecipes()
  #endif
}
