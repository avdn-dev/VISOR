import RootGatewayModelsNonisolated
import SwiftUI
import Testing
import VISOR

// MARK: - ParameterisedLazyView

@MainActor
@LazyViewModel(NonisolatedSourceBackedViewModel.self)
private struct ParameterisedLazyView: View {
  let title: String
  let dismiss: () -> Void

  func readyContent(state: NonisolatedSourceBackedViewModel.State) -> some View {
    Text("\(title): \(state.revision)")
  }
}

// MARK: - LazyViewInitialiserTests

@Suite("Lazy view initialisers in a nonisolated consumer")
@MainActor
struct LazyViewInitialiserTests {
  @Test
  func `Memberwise initialisation remains available with generated state storage`() {
    // Given
    var dismissals = 0

    // When
    let view = ParameterisedLazyView(title: "Library", dismiss: { dismissals += 1 })
    view.dismiss()

    // Then
    #expect(view.title == "Library")
    #expect(dismissals == 1)
  }
}
