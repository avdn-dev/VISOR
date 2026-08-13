import Observation
import RootTestingSupport
import VISOR

@MainActor
@Observable
@ViewModel
public final class MainActorRootTestingViewModel {
  public final class State {
    @Bound(source: \MainActorRootTestingViewModel.service.source)
    public private(set) var sourceValue = -1

    public private(set) var reactedValue = -1
    public private(set) var count = 0

    public init() {}

    deinit {}
  }

  public enum Action {
    case setCount(Int)
  }

  public let state = State()
  public let service: RootTestingService

  public init(service: RootTestingService) {
    self.service = service
  }

  public func handle(_ action: Action) async {
    switch action {
    case let .setCount(value):
      updateState(\.count, to: value)
    }
  }

  @Reaction(source: \MainActorRootTestingViewModel.service.source)
  private func sourceChanged(_ value: Int) {
    updateState(\.reactedValue, to: value)
  }

  deinit {}
}
