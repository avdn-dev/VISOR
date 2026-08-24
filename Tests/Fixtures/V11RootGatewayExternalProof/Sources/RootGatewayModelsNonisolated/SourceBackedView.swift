import SwiftUI
import VISOR

/// Ordinary `@LazyViewModel` expansion from a package-access-disabled target.
@MainActor
@LazyViewModel(
  NonisolatedSourceBackedViewModel.self,
  observationPolicy: .pauseInBackground,
  pending: ProgressView("Preparing source-backed screen"),
  failure: ContentUnavailableView(
    "Source-Backed Screen Unavailable",
    systemImage: "exclamationmark.triangle"))
public struct NonisolatedSourceBackedView: View {
  public init() {}

  public var content: some View {
    Text("Revision \(state.revision)")
  }
}
