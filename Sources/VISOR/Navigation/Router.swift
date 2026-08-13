//
//  Router.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import Foundation
import OSLog

@MainActor
private final class RouterTreeContext<Scene: NavigationScene> {
  weak var activeRouter: Router<Scene>?
  var deepLinkHandler: (@MainActor @Sendable (URL) -> Destination<Scene>?)?
}

// MARK: - Router

/// Observable router that manages navigation state for a NavigationScene.
///
/// The root Router coordinates one navigation tree. A root NavigationContainer
/// may bind it directly for a single stack, while tab and modal containers create
/// child Routers with isolated navigation state.
@MainActor @Observable
public final class Router<Scene: NavigationScene> {

  // MARK: Lifecycle

  // Workaround: Swift 6.2 compiler crash in the SIL EarlyPerfInliner on Router.deinit
  // when compiled with -default-isolation MainActor + -O. The inliner's layout constraint
  // check enters infinite recursion on the generic type. Explicit @MainActor on the class
  // with nonisolated deinit produces different SIL that avoids the crash.
  nonisolated deinit { }

  /// Creates a root router.
  ///
  /// - Parameter logger: Optional `os.Logger` for debug-level navigation logging.
  public init(logger: Logger? = nil) {
    self.level = 0
    self.tab = nil
    self.parent = nil
    self.logger = logger
    self.treeContext = RouterTreeContext()
    isActive = false
  }

  /// Creates a router node in the navigation hierarchy.
  ///
  /// - Parameters:
  ///   - level: Depth in the hierarchy (0 = root). Incremented automatically by `childRouter()`.
  ///   - tab: The tab this router manages, or `nil` for root/modal routers.
  ///   - parent: The parent router. Stored as a `weak` reference to avoid retain cycles.
  ///   - logger: Optional `os.Logger` for debug-level navigation logging.
  package init(
    level: Int,
    tab: Scene.Tab? = nil,
    parent: Router? = nil,
    logger: Logger? = nil)
  {
    self.level = level
    self.tab = tab
    self.parent = parent
    self.logger = logger
    self.treeContext = parent?.treeContext ?? RouterTreeContext()
    isActive = false
  }

  // MARK: - Navigation State

  /// The currently selected tab (only meaningful on the root router).
  public var selectedTab: Scene.Tab?

  /// The navigation stack path for push destinations.
  public var navigationPath: [Scene.Push] = []

  /// The currently presented sheet, if any.
  public var presentingSheet: Scene.Sheet?

  /// The currently presented full-screen cover, if any.
  public var presentingFullScreen: Scene.FullScreen?

  // MARK: - Hierarchy

  /// The depth level of this router (0 = root).
  public let level: Int

  /// The tab this router is associated with (nil for root/modal routers).
  public let tab: Scene.Tab?

  /// The parent router. Weak to avoid retain cycles; `let` because it never changes after init.
  package weak let parent: Router?

  /// Whether this Router is the active visible target for root navigation
  /// actions and deep links.
  public private(set) var isActive: Bool

  // MARK: - Navigation Actions

  /// Push a destination onto the navigation stack. Root calls target the
  /// currently active visible Router; child calls remain local.
  public func push(_ destination: Scene.Push) {
    guard let target = navigationActionTarget(for: "push") else { return }
    target.pushLocally(destination)
  }

  /// Present a sheet.
  ///
  /// When called on the root Router, delegates to the currently active visible
  /// Router. Calls on a child Router remain local to that child.
  public func present(sheet: Scene.Sheet) {
    guard let target = navigationActionTarget(for: "present sheet") else { return }
    target.presentSheetLocally(sheet)
  }

  /// Present a full-screen cover.
  ///
  /// When called on the root Router, delegates to the currently active visible
  /// Router. Calls on a child Router remain local to that child.
  public func present(fullScreen: Scene.FullScreen) {
    guard let target = navigationActionTarget(for: "present fullScreen") else { return }
    target.presentFullScreenLocally(fullScreen)
  }

  /// Select a tab (propagates to parent if this is a child router).
  public func select(tab: Scene.Tab) {
    log("select tab: \(tab)")
    if let parent {
      parent.select(tab: tab)
    } else {
      selectedTab = tab
    }
  }

  /// Navigate to a unified destination.
  public func navigate(to destination: Destination<Scene>) {
    switch destination {
    case .tab(let tab):
      select(tab: tab)
    case .push(let destination):
      push(destination)
    case .sheet(let sheet):
      present(sheet: sheet)
    case .fullScreen(let fullScreen):
      present(fullScreen: fullScreen)
    }
  }

  /// Switch to a tab and push a destination onto that tab's navigation stack.
  public func selectAndPush(tab: Scene.Tab, destination: Scene.Push) {
    let root = rootRouter
    root.log("selectAndPush: tab=\(tab), destination=\(destination)")
    root.childRouter(for: tab).pushLocally(destination)
    root.selectedTab = tab
  }

  /// Pop to the root of the navigation stack. Root calls target the currently
  /// active visible Router; child calls remain local.
  public func popToRoot() {
    guard let target = navigationActionTarget(for: "popToRoot") else { return }
    target.popToRootLocally()
  }

  /// Dismiss the currently presented sheet.
  ///
  /// When called on a router that does not itself hold the sheet presentation,
  /// walks up the parent chain to find the ancestor that does and clears it there.
  public func dismissSheet() {
    guard let target = navigationActionTarget(for: "dismissSheet") else { return }
    target.dismissSheetLocally()
  }

  /// Dismiss the currently presented full-screen cover.
  ///
  /// When called on a router that does not itself hold the full-screen
  /// presentation, walks up the parent chain to find the ancestor that does
  /// and clears it there.
  public func dismissFullScreen() {
    guard let target = navigationActionTarget(for: "dismissFullScreen") else { return }
    target.dismissFullScreenLocally()
  }

  // MARK: - Active State

  /// Mark this Router as mounted and make it the active visible node.
  package func activate() {
    log("activate (level \(level))")
    isMounted = true
    if let previous = treeContext.activeRouter, previous !== self {
      previous.isActive = false
    }
    treeContext.activeRouter = self
    isActive = true
  }

  /// Mark this Router as unmounted and restore its nearest mounted ancestor.
  /// A late disappearance cannot deactivate a newer active sibling.
  package func deactivate() {
    log("deactivate (level \(level))")
    isMounted = false
    isActive = false
    guard treeContext.activeRouter === self else { return }

    var replacement = parent
    while let candidate = replacement, !candidate.isMounted {
      replacement = candidate.parent
    }
    treeContext.activeRouter = replacement
    replacement?.isActive = true
  }

  // MARK: - Deep Linking

  /// Open a deep link destination. Only navigates if this router is active.
  package func deepLinkOpen(to destination: Destination<Scene>) {
    guard isActive else {
      log("deepLinkOpen ignored (inactive, level \(level))")
      return
    }
    log("deepLinkOpen: \(destination)")
    navigate(to: destination)
  }

  // MARK: - Child Management

  /// Create or return the cached child router for a tab's NavigationContainer.
  public func childRouter(for tab: Scene.Tab) -> Router {
    if let existing = tabChildren[tab] {
      return existing
    }
    let child = Router(
      level: level + 1,
      tab: tab,
      parent: self,
      logger: logger)
    tabChildren[tab] = child
    log("childRouter created for tab \(tab) at level \(child.level)")
    return child
  }

  /// Create a child router for a modal's NavigationContainer.
  package func childRouter() -> Router {
    let child = Router(
      level: level + 1,
      tab: nil,
      parent: self,
      logger: logger)
    log("childRouter created (modal) at level \(child.level)")
    return child
  }

  // MARK: - Preview

  /// Create a preview router with the given tab selected.
  public static func preview(tab: Scene.Tab? = nil) -> Router {
    let router = Router()
    router.selectedTab = tab
    return router
  }

  // MARK: - Deep Link Configuration

  /// The tree-wide handler that converts a URL into a `Destination`.
  ///
  /// Configure it with `configureDeepLinks(scheme:parsers:)`. Every Router in
  /// this tree reads the same latest handler, regardless of creation order.
  public var deepLinkHandler: (@MainActor @Sendable (URL) -> Destination<Scene>?)? {
    treeContext.deepLinkHandler
  }

  /// Configure deep link handling with a URL scheme and an ordered list of parsers.
  ///
  /// Configuration applies to this Router's entire tree. The URL's scheme must
  /// match `scheme` (case-insensitive). Parsers are tried in order; the first
  /// non-nil result wins.
  ///
  /// ```swift
  /// router.configureDeepLinks(scheme: "myapp", parsers: [
  ///   .equal(to: ["settings"], destination: .tab(.settings)),
  /// ])
  /// ```
  public func configureDeepLinks(scheme: String, parsers: [DeepLinkParser<Scene>]) {
    treeContext.deepLinkHandler = { url in
      guard url.scheme?.lowercased() == scheme.lowercased() else { return nil }
      for parser in parsers {
        if let destination = parser.parse(url) {
          return destination
        }
      }
      return nil
    }
  }

  // MARK: Private

  private let logger: Logger?
  /// Cached child routers keyed by tab. Bounded by the finite `Scene.Tab` enum;
  /// intentionally never evicted so tab navigation state is preserved across switches.
  @ObservationIgnored private var tabChildren: [Scene.Tab: Router] = [:]
  @ObservationIgnored private let treeContext: RouterTreeContext<Scene>
  @ObservationIgnored private var isMounted = false

  private var rootRouter: Router {
    parent?.rootRouter ?? self
  }

  private func navigationActionTarget(for action: String) -> Router? {
    guard parent == nil else { return self }

    if let activeRouter = treeContext.activeRouter, activeRouter.isMounted {
      return activeRouter
    }
    if let selectedTab,
       let selectedRouter = tabChildren[selectedTab],
       selectedRouter.isMounted
    {
      return selectedRouter
    }
    if isMounted {
      return self
    }

    log("\(action) rejected: no navigation container is active")
    return nil
  }

  private func pushLocally(_ destination: Scene.Push) {
    log("push: \(destination)")
    navigationPath.append(destination)
  }

  private func presentSheetLocally(_ sheet: Scene.Sheet) {
    log("present sheet: \(sheet)")
    presentingSheet = sheet
  }

  private func presentFullScreenLocally(_ fullScreen: Scene.FullScreen) {
    log("present fullScreen: \(fullScreen)")
    presentingFullScreen = fullScreen
  }

  private func popToRootLocally() {
    log("popToRoot")
    navigationPath.removeAll()
  }

  private func dismissSheetLocally() {
    if presentingSheet != nil {
      log("dismissSheet")
      presentingSheet = nil
    } else if let parent {
      log("dismissSheet (walking up)")
      parent.dismissSheetLocally()
    }
  }

  private func dismissFullScreenLocally() {
    if presentingFullScreen != nil {
      log("dismissFullScreen")
      presentingFullScreen = nil
    } else if let parent {
      log("dismissFullScreen (walking up)")
      parent.dismissFullScreenLocally()
    }
  }

  private func log(_ message: String) {
    logger?.debug("Router[\(self.level)]: \(message)")
  }
}
