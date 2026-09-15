import Observation
import VISOR

// MARK: - RouterPathObservationModel

@MainActor
@Observable
@ViewModel
final class RouterPathObservationModel {

  // MARK: Internal

  final class State {

    // MARK: Lifecycle

    init(path: [TestPush]) {
      self.path = path
    }

    // MARK: Internal

    @Bound(source: \RouterPathObservationModel.router.navigationPathValues)
    private(set) var path: [TestPush]

    private(set) var reactedPath = [TestPush]()
    private(set) var reactionCount = 0
  }

  let router: Router<TestScene>

  // MARK: Private

  @Reaction(source: \RouterPathObservationModel.router.navigationPathValues)
  private func pathChanged(_ path: [TestPush]) {
    updateState(\.reactedPath, to: path)
    updateState(\.reactionCount, to: state.reactionCount + 1)
  }
}
