import Foundation
import Observation
import RootObservationConsumer
import SwiftUI
import VISOR

nonisolated public enum DocumentationPush: PushDestination {
  case detail(id: String)
}

nonisolated public enum DocumentationSheet: SheetDestination {
  case preferences

  public var id: Self { self }
}

nonisolated public enum DocumentationFullScreen: FullScreenDestination {
  case onboarding

  public var id: Self { self }
}

nonisolated public enum DocumentationRootDestination: String, RootDestination, Identifiable {
  case library
  case settings

  public var id: Self { self }
  var title: String { rawValue.capitalized }
}

nonisolated public enum DocumentationScene: NavigationScene {
  public typealias Push = DocumentationPush
  public typealias Sheet = DocumentationSheet
  public typealias FullScreen = DocumentationFullScreen
  public typealias Root = DocumentationRootDestination
}

nonisolated public enum DocumentationPushOnlyScene: NavigationScene {
  public typealias Push = DocumentationPush
}

@MainActor
func openDocumentationDeepLink(
  _ url: URL,
  with router: Router<DocumentationScene>)
  throws -> DeepLinkOutcome<DocumentationScene>
{
  try router.configureDeepLinks(scheme: "documentation", parsers: [
    DeepLinkParser { request in
      guard request.components.first == "detail" else { return .noMatch }
      guard request.components.count == 2,
            let id = request.components[1].removingPercentEncoding,
            !id.isEmpty
      else { return .invalid }
      return .destination(.push(.detail(id: id)))
    },
  ])
  return router.openDeepLink(url)
}

nonisolated enum DocumentationLoadFailure: Error, Equatable, Hashable, Sendable {
  case offline
  case unavailable
}

@MainActor
@Observable
@ViewModel
final class DocumentationViewModel {
  final class State {
    @Bound(source: \DocumentationViewModel.consumer.source)
    private(set) var revision: Int

    var draft: String
    private(set) var items: Loadable<[String], DocumentationLoadFailure>

    init(
      revision: Int = -1,
      draft: String = "",
      items: Loadable<[String], DocumentationLoadFailure> = .loading
    ) {
      self.revision = revision
      self.draft = draft
      self.items = items
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
    self.init(items: .loaded(["Preview item"]))
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

      switch state.items {
      case .loading:
        ProgressView("Loading items")
      case .empty:
        ContentUnavailableView("No Items", systemImage: "tray")
      case .loaded(let items):
        ForEach(items, id: \.self) { item in
          Text(item)
        }
      case .failure(let failure):
        switch failure {
        case .offline:
          ContentUnavailableView("You're Offline", systemImage: "wifi.slash")
        case .unavailable:
          ContentUnavailableView(
            "Items Unavailable",
            systemImage: "exclamationmark.triangle")
        }
      }

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
    RouterStack(
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
struct DocumentationPushOnlyRoot: View {
  @State private var router = Router<DocumentationPushOnlyScene>()

  var body: some View {
    RouterStack(
      router: router,
      pushContent: { destination in
        switch destination {
        case .detail(let id): Text("Detail \(id)")
        }
      }
    ) {
      Text("Library")
    }
  }
}

@MainActor
struct DocumentationSplitRoot: View {
  @State private var router = Router<DocumentationScene>.preview(root: .library)

  var body: some View {
    @Bindable var router = router

    RouterHost(
      router: router,
      pushContent: pushContent(for:),
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") }
    ) {
      NavigationSplitView {
        List(selection: $router.selectedRoot) {
          ForEach(DocumentationRootDestination.allCases) { root in
            Text(root.title).tag(root)
          }
        }
      } detail: {
        if let root = router.selectedRoot {
          RouterStack(
            parentRouter: router,
            root: root,
            pushContent: pushContent(for:),
            sheetContent: { _ in Text("Preferences") },
            fullScreenContent: { _ in Text("Onboarding") }
          ) {
            Text(root.title)
          }
        } else {
          ContentUnavailableView("Select a Destination", systemImage: "sidebar.left")
        }
      }
    }
  }

  @ViewBuilder
  private func pushContent(for destination: DocumentationPush) -> some View {
    switch destination {
    case .detail(let id): Text("Detail \(id)")
    }
  }
}

@MainActor
struct DocumentationTabRoot: View {
  @State private var router = Router<DocumentationScene>.preview(root: .library)

  var body: some View {
    @Bindable var router = router

    RouterHost(
      router: router,
      pushContent: pushContent(for:),
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") }
    ) {
      TabView(selection: $router.selectedRoot) {
        rootStack(for: .library)
          .tabItem { Label("Library", systemImage: "books.vertical") }
          .tag(DocumentationRootDestination.library as DocumentationRootDestination?)

        rootStack(for: .settings)
          .tabItem { Label("Settings", systemImage: "gear") }
          .tag(DocumentationRootDestination.settings as DocumentationRootDestination?)
      }
    }
  }

  private func rootStack(for root: DocumentationRootDestination) -> some View {
    RouterStack(
      parentRouter: router,
      root: root,
      pushContent: pushContent(for:),
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") }
    ) {
      Text(root.title)
    }
  }

  @ViewBuilder
  private func pushContent(for destination: DocumentationPush) -> some View {
    switch destination {
    case .detail(let id): Text("Detail \(id)")
    }
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
