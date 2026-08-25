import Observation
import RootTestingModelsNonisolated
import Testing
import VISOR
import VISORTesting

// MARK: - RootSelectorProbeViewModel

@MainActor
@Observable
@ViewModel
final class RootSelectorProbeViewModel {
  struct Details: Equatable {
    var count = 0
  }

  final class State {

    // MARK: Internal

    var details = Details()

    var doubledCount: Int {
      details.count * 2
    }

    // MARK: Private

    private var hidden = 0

  }

  let state = State()
}

@MainActor
func verifySelectorProbeBaseline(
  _ test: ObservationTest<RootSelectorProbeViewModel>
) {
  test.expect(\.details, hasExactChanges: [])
}

#if VISOR_PROBE_INTERNAL_SELECTOR
@MainActor
func probeInternalSelector(
  _ test: ObservationTest<NonisolatedRootTestingViewModel>
) {
  test.expect(\.internalRevision, hasExactChanges: [1])
}
#endif

#if VISOR_PROBE_FILEPRIVATE_SELECTOR
@MainActor
func probeFileprivateSelector(
  _ test: ObservationTest<NonisolatedRootTestingViewModel>
) {
  test.expect(\.fileRevision, hasExactChanges: [1])
}
#endif

#if VISOR_PROBE_PRIVATE_SELECTOR
@MainActor
func probePrivateSelector(
  _ test: ObservationTest<RootSelectorProbeViewModel>
) {
  test.expect(\.hidden, hasExactChanges: [1])
}
#endif

#if VISOR_PROBE_COMPUTED_SELECTOR
@MainActor
func probeComputedSelector(
  _ test: ObservationTest<RootSelectorProbeViewModel>
) {
  test.expect(\.doubledCount, hasExactChanges: [2])
}
#endif

#if VISOR_PROBE_NESTED_SELECTOR
@MainActor
func probeNestedSelector(
  _ test: ObservationTest<RootSelectorProbeViewModel>
) {
  test.expect(\.details.count, hasExactChanges: [1])
}
#endif

#if VISOR_PROBE_PROJECTING_OVERLOAD
@MainActor
func probeProjectingOverload(
  _ test: ObservationTest<RootSelectorProbeViewModel>
) {
  test.expect(
    \.details,
    projecting: \.count,
    hasExactChanges: [1],
  )
}
#endif
