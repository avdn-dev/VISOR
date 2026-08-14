//
//  Router.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import Foundation
import OSLog

// MARK: - DeepLinkOutcome

/// The result of asking a Router tree to open an external URL.
public enum DeepLinkOutcome<Scene: NavigationScene> {
  /// The URL was validated and its destination was opened.
  case handled(Destination<Scene>)

  /// No deep-link configuration has been installed for this Router tree.
  case unconfigured

  /// The URL scheme does not match the configured scheme.
  case schemeMismatch

  /// Every parser reported that it did not recognise the route.
  case unmatched

  /// A parser recognised the route but rejected its inputs.
  case invalid

  /// The URL resolved, but no navigation container is currently mounted.
  case inactive
}

nonisolated extension DeepLinkOutcome: Equatable {}
nonisolated extension DeepLinkOutcome: Hashable {}
nonisolated extension DeepLinkOutcome: Sendable {}

@MainActor
private struct RouterDeepLinkConfiguration<Scene: NavigationScene> {
  let scheme: String
  let parsers: [DeepLinkParser<Scene>]
}

@MainActor
private final class RouterTreeContext<Scene: NavigationScene> {
  weak var activeRouter: Router<Scene>?
  var deepLinkConfiguration: RouterDeepLinkConfiguration<Scene>?
}

package struct RouterSheetPresentation<Scene: NavigationScene>: Identifiable {
  package let id: Scene.Sheet.ID
  package var destination: Scene.Sheet
  package let router: Router<Scene>
}

package struct RouterFullScreenPresentation<Scene: NavigationScene>: Identifiable {
  package let id: Scene.FullScreen.ID
  package var destination: Scene.FullScreen
  package let router: Router<Scene>
}

private enum RouterModalPresentation<Scene: NavigationScene> {
  case sheet(RouterSheetPresentation<Scene>)
  case fullScreen(RouterFullScreenPresentation<Scene>)
}

// MARK: - Router

/// Observable router that manages navigation state for a NavigationScene.
///
/// The root Router coordinates one navigation tree. A root NavigationContainer
/// may bind it directly for a single stack, while tab containers and modal
/// presentation records use child Routers with isolated navigation state.
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
  ///
  /// A Router node has one modal presentation slot. Setting this property
  /// replaces any full-screen presentation held by the same Router.
  public var presentingSheet: Scene.Sheet? {
    get { sheetPresentation?.destination }
    set {
      if let newValue {
        presentSheetLocally(newValue)
      } else {
        sheetPresentation = nil
      }
    }
  }

  /// The currently presented destination with full-screen intent, if any.
  ///
  /// A Router node has one modal presentation slot. Setting this property
  /// replaces any sheet held by the same Router.
  public var presentingFullScreen: Scene.FullScreen? {
    get { fullScreenPresentation?.destination }
    set {
      if let newValue {
        presentFullScreenLocally(newValue)
      } else {
        fullScreenPresentation = nil
      }
    }
  }

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

  /// Present a destination with full-screen intent.
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

  /// Dismiss the currently presented full-screen destination.
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

  /// Validate and open a deep-link URL in this Router tree.
  ///
  /// The first parser to return a destination or invalid result ends parsing.
  /// A valid destination targets the currently active mounted Router, regardless
  /// of which Router in the tree receives this call.
  @discardableResult
  public func openDeepLink(_ url: URL) -> DeepLinkOutcome<Scene> {
    guard let configuration = treeContext.deepLinkConfiguration else {
      return reportDeepLinkOutcome(.unconfigured)
    }
    guard url.scheme?.lowercased() == configuration.scheme else {
      return reportDeepLinkOutcome(.schemeMismatch)
    }

    let request = DeepLinkRequest(url: url)
    for parser in configuration.parsers {
      switch parser.parse(request) {
      case .noMatch:
        continue
      case .invalid:
        return reportDeepLinkOutcome(.invalid)
      case .destination(let destination):
        guard let target = rootRouter.currentNavigationActionTarget else {
          return reportDeepLinkOutcome(.inactive)
        }
        target.navigate(to: destination)
        return reportDeepLinkOutcome(.handled(destination))
      }
    }

    return reportDeepLinkOutcome(.unmatched)
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

  package var sheetPresentation: RouterSheetPresentation<Scene>? {
    get {
      guard case .sheet(let presentation) = modalPresentation else { return nil }
      return presentation
    }
    set {
      if let newValue {
        modalPresentation = .sheet(newValue)
      } else if case .sheet = modalPresentation {
        modalPresentation = nil
      }
    }
  }

  package var fullScreenPresentation: RouterFullScreenPresentation<Scene>? {
    get {
      guard case .fullScreen(let presentation) = modalPresentation else { return nil }
      return presentation
    }
    set {
      if let newValue {
        modalPresentation = .fullScreen(newValue)
      } else if case .fullScreen = modalPresentation {
        modalPresentation = nil
      }
    }
  }

  // MARK: - Preview

  /// Create a preview router with the given tab selected.
  public static func preview(tab: Scene.Tab? = nil) -> Router {
    let router = Router()
    router.selectedTab = tab
    return router
  }

  // MARK: - Deep Link Configuration

  /// Configure deep link handling with a URL scheme and an ordered list of parsers.
  ///
  /// Configuration applies to this Router's entire tree. The URL's scheme must
  /// match `scheme` (case-insensitive). Parsers are tried in order until one
  /// returns a destination or reports invalid input.
  ///
  /// ```swift
  /// router.configureDeepLinks(scheme: "myapp", parsers: [
  ///   .equal(to: ["profile"], destination: .tab(.profile)),
  /// ])
  /// ```
  public func configureDeepLinks(scheme: String, parsers: [DeepLinkParser<Scene>]) {
    treeContext.deepLinkConfiguration = RouterDeepLinkConfiguration(
      scheme: scheme.lowercased(),
      parsers: parsers)
  }

  // MARK: Private

  private let logger: Logger?
  /// Cached child routers keyed by tab. Bounded by the finite `Scene.Tab` enum;
  /// intentionally never evicted so tab navigation state is preserved across switches.
  @ObservationIgnored private var tabChildren: [Scene.Tab: Router] = [:]
  @ObservationIgnored private let treeContext: RouterTreeContext<Scene>
  @ObservationIgnored private var isMounted = false
  private var modalPresentation: RouterModalPresentation<Scene>?

  private var rootRouter: Router {
    parent?.rootRouter ?? self
  }

  /// Only the mounted target handles SwiftUI's tree-wide `onOpenURL` delivery.
  package var receivesDeepLinks: Bool {
    rootRouter.currentNavigationActionTarget === self
  }

  private var currentNavigationActionTarget: Router? {
    let root = rootRouter
    if let activeRouter = root.treeContext.activeRouter, activeRouter.isMounted {
      return activeRouter
    }
    if let selectedTab = root.selectedTab,
       let selectedRouter = root.tabChildren[selectedTab],
       selectedRouter.isMounted
    {
      return selectedRouter
    }
    if root.isMounted {
      return root
    }
    return nil
  }

  private func navigationActionTarget(for action: String) -> Router? {
    guard parent == nil else { return self }

    if let target = currentNavigationActionTarget {
      return target
    }

    log("\(action) rejected: no navigation container is active")
    return nil
  }

  private func reportDeepLinkOutcome(
    _ outcome: DeepLinkOutcome<Scene>)
    -> DeepLinkOutcome<Scene>
  {
    switch outcome {
    case .handled:
      log("deep link outcome: handled")
    case .unconfigured:
      log("deep link outcome: unconfigured")
    case .schemeMismatch:
      log("deep link outcome: scheme mismatch")
    case .unmatched:
      log("deep link outcome: unmatched")
    case .invalid:
      log("deep link outcome: invalid")
    case .inactive:
      log("deep link outcome: inactive")
    }
    return outcome
  }

  private func pushLocally(_ destination: Scene.Push) {
    log("push: \(destination)")
    navigationPath.append(destination)
  }

  private func presentSheetLocally(_ sheet: Scene.Sheet) {
    log("present sheet: \(sheet)")
    if case .sheet(var presentation) = modalPresentation,
       presentation.id == sheet.id
    {
      presentation.destination = sheet
      modalPresentation = .sheet(presentation)
    } else {
      modalPresentation = .sheet(RouterSheetPresentation(
        id: sheet.id,
        destination: sheet,
        router: childRouter()))
    }
  }

  private func presentFullScreenLocally(_ fullScreen: Scene.FullScreen) {
    log("present fullScreen: \(fullScreen)")
    if case .fullScreen(var presentation) = modalPresentation,
       presentation.id == fullScreen.id
    {
      presentation.destination = fullScreen
      modalPresentation = .fullScreen(presentation)
    } else {
      modalPresentation = .fullScreen(RouterFullScreenPresentation(
        id: fullScreen.id,
        destination: fullScreen,
        router: childRouter()))
    }
  }

  private func popToRootLocally() {
    log("popToRoot")
    navigationPath.removeAll()
  }

  private func dismissSheetLocally() {
    if case .sheet = modalPresentation {
      log("dismissSheet")
      modalPresentation = nil
    } else if let parent {
      log("dismissSheet (walking up)")
      parent.dismissSheetLocally()
    }
  }

  private func dismissFullScreenLocally() {
    if case .fullScreen = modalPresentation {
      log("dismissFullScreen")
      modalPresentation = nil
    } else if let parent {
      log("dismissFullScreen (walking up)")
      parent.dismissFullScreenLocally()
    }
  }

  private func log(_ message: String) {
    logger?.debug("Router[\(self.level)]: \(message)")
  }
}
