import Observation
import RootObservationConsumer
import SwiftUI
import VISOR

nonisolated enum DocumentationPush: PushDestination {
  case detail(id: String)
}

nonisolated enum DocumentationSheet: SheetDestination {
  case preferences

  var id: Self { self }
}

nonisolated enum DocumentationFullScreen: FullScreenDestination {
  case onboarding

  var id: Self { self }
}

nonisolated enum DocumentationScene: NavigationScene {
  typealias Push = DocumentationPush
  typealias Sheet = DocumentationSheet
  typealias FullScreen = DocumentationFullScreen
}

@MainActor
@Observable
@ViewModel
final class DocumentationViewModel {
  final class State {
    @Bound(source: \DocumentationViewModel.consumer.source)
    private(set) var revision: Int

    var draft: String

    init(revision: Int = -1, draft: String = "") {
      self.revision = revision
      self.draft = draft
    }
  }

  enum Action {
    case showDetail(id: String)
  }

  let state = State()
  let consumer: RootObservationConsumer
  private let router: Router<DocumentationScene>

  init(
    router: Router<DocumentationScene>,
    consumer: RootObservationConsumer
  ) {
    self.router = router
    self.consumer = consumer
  }

  func handle(_ action: Action) {
    switch action {
    case .showDetail(let id):
      router.push(.detail(id: id))
    }
  }
}

extension DocumentationViewModel.State {
  convenience init(previewRevision: Int, previewDraft: String) {
    self.init()
    self[\.revision] = previewRevision
    self[\.draft] = previewDraft
  }
}

@MainActor
@LazyViewModel(DocumentationViewModel.self)
struct DocumentationScreen: View {
  var content: some View {
    DocumentationContent(state: state) { action in
      viewModel.handle(action)
    }
  }
}

@MainActor
struct DocumentationContent: View {
  @Bindable var state: DocumentationViewModel.State
  let onAction: (DocumentationViewModel.Action) -> Void

  var body: some View {
    VStack {
      Text("Revision \(state.revision)")
      TextField("Draft", text: $state[\.draft])
      Button("Show detail") {
        onAction(.showDetail(id: "preview"))
      }
    }
  }
}

@MainActor
struct DocumentationRoot: View {
  @State private var router = Router<DocumentationScene>()

  var body: some View {
    NavigationContainer(
      router: router,
      pushContent: { destination in
        switch destination {
        case .detail(let id): Text("Detail \(id)")
        }
      },
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") }
    ) {
      DocumentationScreen()
    }
    .environment(
      DocumentationViewModel.Factory.routed { router in
        DocumentationViewModel(
          router: router,
          consumer: RootObservationConsumer(initialValue: 0))
      })
  }
}

@MainActor
struct DocumentationContentPreviews: PreviewProvider {
  static var previews: some View {
    DocumentationContent(
      state: DocumentationViewModel.State(
        previewRevision: 42,
        previewDraft: "Preview"),
      onAction: { _ in })
  }
}
