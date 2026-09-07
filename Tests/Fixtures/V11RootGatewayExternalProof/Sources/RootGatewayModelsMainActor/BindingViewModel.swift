import Observation
import SwiftUI
import VISOR

// MARK: - MainActorBindingViewModel

/// Exercises action routing and managed effects without package access.
@MainActor
@Observable
@ViewModel
public final class MainActorBindingViewModel {

  // MARK: Public

  public final class State {
    public private(set) var isEnabled = false
    public private(set) var preparedValue = 0
  }

  public enum Action {
    @StateBinding(\State.isEnabled)
    case enabledChanged(Bool)
  }

  public private(set) var handledValues = [Bool]()

  public func handle(_ action: Action) {
    switch action {
    case .enabledChanged(let value):
      handledValues.append(value)
      updateState(\.isEnabled, to: value)
    }
  }

  public func prepare(_ value: Int) -> EffectHandle<Int> {
    latest.run(for: self) { value } receive: { model, value in
      model.updateState(\.preparedValue, to: value)
    }
  }

  // MARK: Private

  private let latest = LatestEffect()
}

// MARK: - MainActorBindingView

@MainActor
@LazyViewModel(MainActorBindingViewModel.self)
public struct MainActorBindingView: View {
  public init() { }

  public var content: some View {
    Toggle("Enabled", isOn: bindableState[\.isEnabled])
  }
}
