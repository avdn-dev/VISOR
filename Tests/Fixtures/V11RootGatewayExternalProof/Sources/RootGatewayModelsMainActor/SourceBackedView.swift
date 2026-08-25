import SwiftUI
import VISOR

/// Ordinary `@LazyViewModel` expansion under MainActor-by-default settings.
@LazyViewModel(
  MainActorSourceBackedViewModel.self,
  observationPolicy: .pauseWhenInactive,
)
public struct MainActorSourceBackedView: View {
  public init() { }

  public var content: some View {
    Text("Revision \(state.revision)")
  }
}
