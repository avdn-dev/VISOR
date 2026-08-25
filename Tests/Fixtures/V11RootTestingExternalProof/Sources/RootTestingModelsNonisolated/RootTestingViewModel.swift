import Observation
import RootTestingSupport
import VISOR

@MainActor
@Observable
@ViewModel
public final class NonisolatedRootTestingViewModel {

  // MARK: Lifecycle

  public init(service: RootTestingService) {
    self.service = service
  }

  deinit { }

  // MARK: Public

  public final class State {

    // MARK: Lifecycle

    public init() { }

    deinit { }

    // MARK: Public

    @Bound(source: \NonisolatedRootTestingViewModel.service.source)
    public private(set) var sourceValue = -1

    public private(set) var reactedValue = -1
    public private(set) var count = 0

    // MARK: Internal

    private(set) var internalRevision = 0

    // MARK: Fileprivate

    fileprivate private(set) var fileRevision = 0

  }

  public enum Action {
    case setCount(Int)
  }

  public let state = State()
  public let service: RootTestingService

  public func handle(_ action: Action) async {
    switch action {
    case .setCount(let value):
      updateState(\.count, to: value)
    }
  }

  // MARK: Private

  @Reaction(source: \NonisolatedRootTestingViewModel.service.source)
  private func sourceChanged(_ value: Int) {
    updateState(\.reactedValue, to: value)
  }

}
