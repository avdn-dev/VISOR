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

    // MARK: Public

    public private(set) var isEnabled = false
    public private(set) var preparedValue = 0

    public var displayOnly: String {
      isEnabled.description
    }

    public var isDisabled: Bool {
      !isEnabled
    }

    // MARK: Private

    private var hidden: Bool {
      isEnabled
    }

  }

  public enum Action {
    @StateBinding(\State.isEnabled)
    case enabledChanged(Bool)
    @StateBinding(\State.isDisabled)
    case disabledChanged(Bool)
    case prepare(Int)
  }

  public private(set) var handledValues = [Bool]()

  @discardableResult
  public func handle(_ action: Action) -> ActionCompletion {
    switch action {
    case .enabledChanged(let value):
      handledValues.append(value)
      updateState(\.isEnabled, to: value)

    case .disabledChanged(let value):
      handledValues.append(!value)
      updateState(\.isEnabled, to: !value)

    case .prepare(let value):
      return prepare(value).completion
    }
    return .completed
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

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public var body: some View {
    content
      .navigationTitle(state?.displayOnly ?? "Settings")
      .toolbar {
        Button("Enable") { send(.enabledChanged(true)) }
          .disabled(state == nil)
      }
  }

  public func readyContent(
    viewModel: MainActorBindingViewModel,
    bindings: ViewModelBindings<MainActorBindingViewModel>,
  ) -> some View {
    VStack {
      Text(viewModel.state.displayOnly)
      Toggle("Enabled", isOn: bindings.isEnabled)
      Toggle("Disabled", isOn: bindings.isDisabled)
    }
  }
}
