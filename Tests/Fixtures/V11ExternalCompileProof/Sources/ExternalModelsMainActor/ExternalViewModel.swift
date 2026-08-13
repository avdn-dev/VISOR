import Observation
import VISOR

@MainActor
@Observable
@ViewModel
public final class ExternalViewModel {
  public enum Phase: Equatable {
    case idle
    case loading
    case loaded
  }

  public struct Settings: Equatable {
    public var revision: Int

    public init(revision: Int) {
      self.revision = revision
    }
  }

  public final class ReferenceValue: Equatable {
    public var revision: Int

    public init(revision: Int) {
      self.revision = revision
    }

    public static func == (
      lhs: ReferenceValue,
      rhs: ReferenceValue
    ) -> Bool {
      lhs.revision == rhs.revision
    }
  }

  public enum Action {
    case refresh
  }

  public final class State {
    public private(set) var phase: Phase = .idle
    public private(set) var count = 0
    public private(set) var settings = Settings(revision: 0)
    public private(set) var reference = ReferenceValue(revision: 0)

    public init() {}

    public func setCountDirectly(_ value: Int) {
      count = value
    }

    public func mutateReferenceInterior() {
      reference.revision += 1
    }
  }

  public let state: State

  public init(state: State = State()) {
    self.state = state
  }

  public func handle(_ action: Action) async {
    switch action {
    case .refresh:
      updateState(\.phase, to: .loading)
      updateState(\.count, to: state.count + 1)
      updateState(\.phase, to: .loaded)
    }
  }
}
