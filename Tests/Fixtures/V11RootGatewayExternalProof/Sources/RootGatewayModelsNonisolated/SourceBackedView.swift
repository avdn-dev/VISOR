import SwiftUI
import VISOR

/// Ordinary `@LazyViewModel` expansion from a package-access-disabled target.
@MainActor
@LazyViewModel(
  NonisolatedSourceBackedViewModel.self,
  observationPolicy: .pauseInBackground,
)
public struct NonisolatedSourceBackedView: View {
  public init() { }

  public func readyContent(state: NonisolatedSourceBackedViewModel.State) -> some View {
    Text("Revision \(state.revision)")
  }

  var pendingContent: some View {
    ProgressView("Preparing source-backed screen")
  }

  var failureContent: some View {
    ContentUnavailableView("Source-Backed Screen Unavailable", systemImage: "exclamationmark.triangle")
  }

}
