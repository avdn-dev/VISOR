import Foundation
import Observation
import RootObservationConsumer
import SwiftUI
import VISOR

// MARK: - DocumentationPush

nonisolated public enum DocumentationPush: PushDestination {
  case detail(id: String)
}

// MARK: - DocumentationSheet

nonisolated public enum DocumentationSheet: SheetDestination {
  case preferences

  public var id: Self {
    self
  }
}

// MARK: - DocumentationFullScreen

nonisolated public enum DocumentationFullScreen: FullScreenDestination {
  case onboarding

  public var id: Self {
    self
  }
}

// MARK: - DocumentationRootDestination

nonisolated public enum DocumentationRootDestination: String, RootDestination, Identifiable {
  case library
  case settings

  public var id: Self {
    self
  }

  var title: String {
    rawValue.capitalized
  }
}

// MARK: - DocumentationScene

nonisolated public enum DocumentationScene: NavigationScene {
  public typealias Push = DocumentationPush
  public typealias Sheet = DocumentationSheet
  public typealias FullScreen = DocumentationFullScreen
  public typealias Root = DocumentationRootDestination
}

// MARK: - DocumentationPushOnlyScene

nonisolated public enum DocumentationPushOnlyScene: NavigationScene {
  public typealias Push = DocumentationPush
}

@MainActor
func openDocumentationDeepLink(
  _ url: URL,
  with router: Router<DocumentationScene>,
) throws -> DeepLinkOutcome<DocumentationScene> {
  try router.configureDeepLinks(scheme: "documentation", parsers: [
    .matching(components: ["library"], destination: .root(.library)),
    DeepLinkParser { request in
      guard request.routeComponents.first == "detail" else { return .noMatch }
      guard
        request.routeComponents.count == 2,
        let id = request.routeComponents[1].removingPercentEncoding,
        !id.isEmpty
      else { return .invalid }
      return .destination(.push(.detail(id: id)))
    },
  ])
  return router.openDeepLink(url)
}

// MARK: - DocumentationLoadFailure

nonisolated enum DocumentationLoadFailure: Error, Equatable, Hashable, Sendable {
  case offline
  case unavailable
}

// MARK: - DocumentationViewModel

@MainActor
@Observable
@ViewModel
final class DocumentationViewModel {

  // MARK: Lifecycle

  init(
    router: Router<DocumentationScene>,
    consumer: RootObservationConsumer,
  ) {
    self.router = router
    self.consumer = consumer
  }

  // MARK: Internal

  final class State {

    // MARK: Lifecycle

    init(
      revision: Int = -1,
      draft: String = "",
      items: Loadable<[String], DocumentationLoadFailure> = .loading,
    ) {
      self.revision = revision
      self.draft = draft
      self.items = items
    }

    // MARK: Internal

    @Bound(source: \DocumentationViewModel.consumer.source)
    private(set) var revision: Int

    var draft: String
    private(set) var items: Loadable<[String], DocumentationLoadFailure>

  }

  enum Action {
    case showDetail(id: String)
  }

  let state = State()
  let consumer: RootObservationConsumer

  func handle(_ action: Action) {
    switch action {
    case .showDetail(let id):
      router.push(.detail(id: id))
    }
  }

  // MARK: Private

  private let router: Router<DocumentationScene>

}

extension DocumentationViewModel.State {
  convenience init(previewRevision: Int, previewDraft: String) {
    self.init(items: .loaded(["Preview item"]))
    self[\.revision] = previewRevision
    self[\.draft] = previewDraft
  }
}

// MARK: - DocumentationScreen

@MainActor
@LazyViewModel(DocumentationViewModel.self)
struct DocumentationScreen: View {
  var content: some View {
    DocumentationContent(state: state) { action in
      viewModel.handle(action)
    }
  }
}

// MARK: - DocumentationContent

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
            systemImage: "exclamationmark.triangle",
          )
        }
      }

      Button("Show detail") {
        onAction(.showDetail(id: "preview"))
      }
    }
  }
}

// MARK: - DocumentationRoot

@MainActor
struct DocumentationRoot: View {

  // MARK: Internal

  var body: some View {
    RouterStack(
      router: router,
      pushContent: { destination in
        switch destination {
        case .detail(let id): Text("Detail \(id)")
        }
      },
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") },
    ) {
      DocumentationScreen()
    }
    .environment(
      DocumentationViewModel.Factory.routed { router in
        DocumentationViewModel(
          router: router,
          consumer: RootObservationConsumer(initialValue: 0),
        )
      }
    )
  }

  // MARK: Private

  @State private var router = Router<DocumentationScene>()

}

// MARK: - DocumentationPushOnlyRoot

@MainActor
struct DocumentationPushOnlyRoot: View {
  var body: some View {
    RouterStack(
      router: router,
      pushContent: { destination in
        switch destination {
        case .detail(let id): Text("Detail \(id)")
        }
      },
    ) {
      Text("Library")
    }
  }

  @State private var router = Router<DocumentationPushOnlyScene>()

}

// MARK: - DocumentationSplitRoot

@MainActor
struct DocumentationSplitRoot: View {

  // MARK: Internal

  var body: some View {
    @Bindable var router = router

    RouterHost(
      router: router,
      pushContent: pushContent(for:),
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") },
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
            fullScreenContent: { _ in Text("Onboarding") },
          ) {
            Text(root.title)
          }
        } else {
          ContentUnavailableView("Select a Destination", systemImage: "sidebar.left")
        }
      }
    }
  }

  // MARK: Private

  @State private var router = Router<DocumentationScene>.preview(root: .library)

  @ViewBuilder
  private func pushContent(for destination: DocumentationPush) -> some View {
    switch destination {
    case .detail(let id): Text("Detail \(id)")
    }
  }
}

// MARK: - DocumentationTabRoot

@MainActor
struct DocumentationTabRoot: View {

  // MARK: Internal

  var body: some View {
    @Bindable var router = router

    RouterHost(
      router: router,
      pushContent: pushContent(for:),
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") },
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

  // MARK: Private

  @State private var router = Router<DocumentationScene>.preview(root: .library)

  private func rootStack(for root: DocumentationRootDestination) -> some View {
    RouterStack(
      parentRouter: router,
      root: root,
      pushContent: pushContent(for:),
      sheetContent: { _ in Text("Preferences") },
      fullScreenContent: { _ in Text("Onboarding") },
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

// MARK: - DocumentationContentPreviews

@MainActor
struct DocumentationContentPreviews: PreviewProvider {
  static var previews: some View {
    DocumentationContent(
      state: DocumentationViewModel.State(
        previewRevision: 42,
        previewDraft: "Preview",
      ),
      onAction: { _ in },
    )
  }
}
