import SwiftUI
import VISOR

/// Ordinary `@LazyViewModel` expansion from a package-access-disabled target.
@MainActor
@LazyViewModel(
  NonisolatedSourceBackedViewModel.self,
  observationPolicy: .pauseInBackground)
public struct NonisolatedSourceBackedView: View {
  public init() {}

  public var content: some View {
    Text("Revision \(state.revision)")
  }
}
