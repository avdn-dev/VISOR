import RootGatewayModelsNonisolated
import VISOR

// MARK: - ProbePush

private enum ProbePush: PushDestination {
  case value
}

// MARK: - ProbeSheet

private enum ProbeSheet: SheetDestination {
  case value

  var id: Self {
    self
  }
}

// MARK: - ProbeFullScreen

private enum ProbeFullScreen: FullScreenDestination {
  case value

  var id: Self {
    self
  }
}

// MARK: - ProbeScene

private enum ProbeScene: NavigationScene {
  typealias Push = ProbePush
  typealias Sheet = ProbeSheet
  typealias FullScreen = ProbeFullScreen
}

@MainActor
public func compileRootGatewayAccessBoundary() {
  typealias State = NonisolatedGatewayState

  let field: _StateField<State, Int> = State._visorSelectors.count
  let erased = State._visorAllFields[0]
  let sourceBackedView = NonisolatedSourceBackedView()
  let router = Router<ProbeScene>()

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

  #if VISOR_PROBE_SHEET_SETTER
  router.presentingSheet = .value
  #endif

  #if VISOR_PROBE_FULL_SCREEN_SETTER
  router.presentingFullScreen = .value
  #endif

  #if VISOR_PROBE_ROUTER_LEVEL
  _ = router.level
  #endif

  #if VISOR_PROBE_ROUTER_ROOT_DESTINATION
  _ = router.rootDestination
  #endif

  #if VISOR_PROBE_ROUTER_IS_ACTIVE
  _ = router.isActive
  #endif
}
