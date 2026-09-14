import SwiftUI

/// Callable action dispatch used by generated views. It weakly references the
/// presentation, so retaining a sender cannot retain the observation lifetime.
@MainActor
public struct _LazyViewModelActionSender<VM: ViewModel> {
  package init(
    presentation: _LazyViewModelPresentation<VM>,
    observationPolicy: ObservationPolicy,
    scenePhase: ScenePhase,
  ) {
    self.presentation = presentation
    self.observationPolicy = observationPolicy
    self.scenePhase = scenePhase
  }

  @discardableResult
  public func callAsFunction(_ action: VM.Action) -> ActionCompletion? {
    presentation?._visorSend(action, observationPolicy: observationPolicy, scenePhase: scenePhase)
  }

  private weak var presentation: _LazyViewModelPresentation<VM>?
  private let observationPolicy: ObservationPolicy
  private let scenePhase: ScenePhase
}
