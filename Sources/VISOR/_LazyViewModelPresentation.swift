import Observation
import SwiftUI

/// Shared presentation state for a generated lazy view. Public only so macro
/// expansions can retain it; the observation lifetime remains in the host.
@MainActor
@Observable
public final class _LazyViewModelPresentation<VM: ViewModel>: _LazyViewModelStateValue {

  // MARK: Lifecycle

  public init() { }

  deinit { }

  // MARK: Public

  public func _visorState(
    observationPolicy: ObservationPolicy,
    scenePhase: ScenePhase,
  ) -> VM.State? {
    readyModel(isEnabled: observationPolicy._visorIsEnabled(in: scenePhase))?.state
  }

  public func _visorSender(
    observationPolicy: ObservationPolicy,
    scenePhase: ScenePhase,
  ) -> _LazyViewModelActionSender<VM> {
    _LazyViewModelActionSender(presentation: self, observationPolicy: observationPolicy, scenePhase: scenePhase)
  }

  // MARK: Package

  package private(set) var model: VM?
  package var owner: _ViewModelObservationOwner<VM>?

  @discardableResult
  package func _visorSend(
    _ action: VM.Action,
    observationPolicy: ObservationPolicy,
    scenePhase: ScenePhase,
  ) -> ActionCompletion? {
    readyModel(isEnabled: observationPolicy._visorIsEnabled(in: scenePhase))?.handle(action)
  }

  package func prepare(factory: ViewModelFactory<VM>, router: AnyObject?) -> VM {
    if let model { return model }
    let model = factory._visorMakeViewModel(router: router)
    self.model = model
    return model
  }

  package func readyModel(isEnabled: Bool) -> VM? {
    guard let model, let owner, owner._visorCanExposeContent(for: model, isEnabled: isEnabled) else {
      return nil
    }
    return model
  }

  package func readyBindings(for model: VM) -> ViewModelBindings<VM> {
    let owner = owner
    let generation = owner?._visorGenerationCount
    return model.bindings._visorGuarded { [weak owner, weak model] in
      guard let owner, let model, owner._visorGenerationCount == generation else { return false }
      return owner._visorCanExposeContent(for: model, isEnabled: true)
    }
  }
}
