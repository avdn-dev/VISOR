//
//  Router.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import OSLog
import SwiftUI

// MARK: - Router

/// Observable router that manages navigation state for a NavigationScene.
///
/// Each NavigationContainer creates a child Router. The root Router is created
/// at the app level and passed to the first NavigationContainer.
@MainActor @Observable
public final class Router<Scene: NavigationScene> {

  // MARK: Lifecycle

  // Workaround: Swift 6.2 compiler crash in the SIL EarlyPerfInliner on Router.deinit
  // when compiled with -default-isolation MainActor + -O. The inliner's layout constraint
  // check enters infinite recursion on the generic type. Explicit @MainActor on the class
  // with nonisolated deinit produces different SIL that avoids the crash.
  nonisolated deinit { }

  /// Creates a router node in the navigation hierarchy.
  ///
  /// - Parameters:
  ///   - level: Depth in the hierarchy (0 = root). Incremented automatically by `childRouter()`.
  ///   - identifierTab: The tab this router manages, or `nil` for root/modal routers.
  ///   - parent: The parent router. Stored as a `weak` reference to avoid retain cycles.
  ///   - logger: Optional `os.Logger` for debug-level navigation logging.
  /// Creates a root router.
  ///
  /// - Parameter logger: Optional `os.Logger` for debug-level navigation logging.
  public init(logger: Logger? = nil) {
    self.level = 0
    self.identifierTab = nil
    self.parent = nil
    self.logger = logger
    isActive = true
  }

  /// Creates a router node in the navigation hierarchy.
  ///
  /// - Parameters:
  ///   - level: Depth in the hierarchy (0 = root). Incremented automatically by `childRouter()`.
  ///   - identifierTab: The tab this router manages, or `nil` for root/modal routers.
  ///   - parent: The parent router. Stored as a `weak` reference to avoid retain cycles.
  ///   - logger: Optional `os.Logger` for debug-level navigation logging.
  package init(
    level: Int,
    identifierTab: Scene.Tab? = nil,
    parent: Router? = nil,
    logger: Logger? = nil)
  {
    self.level = level
    self.identifierTab = identifierTab
    self.parent = parent
    self.logger = logger
    isActive = parent == nil // root is active by default
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
  public let identifierTab: Scene.Tab?

  /// The parent router. Weak to avoid retain cycles; `let` because it never changes after init.
  package weak let parent: Router?

  /// Whether this router is the currently active one for deep linking.
  public private(set) var isActive: Bool

  // MARK: - Navigation Actions

  /// Push a destination onto the navigation stack.
  public func push(_ destination: Scene.Push) {
    log("push: \(destination)")
    navigationPath.append(destination)
  }

  /// Present a sheet.
  public func present(sheet: Scene.Sheet) {
    log("present sheet: \(sheet)")
    presentingSheet = sheet
  }

  /// Present a full-screen cover.
  public func present(fullScreen: Scene.FullScreen) {
    log("present fullScreen: \(fullScreen)")
    presentingFullScreen = fullScreen
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
    log("selectAndPush: tab=\(tab), destination=\(destination)")
    childRouter(for: tab).push(destination)
    select(tab: tab)
  }

  /// Pop to the root of the navigation stack.
  public func popToRoot() {
    log("popToRoot")
    navigationPath.removeAll()
  }

  /// Dismiss the currently presented sheet.
  public func dismissSheet() {
    log("dismissSheet")
    presentingSheet = nil
  }

  /// Dismiss the currently presented full-screen cover.
  public func dismissFullScreen() {
    log("dismissFullScreen")
    presentingFullScreen = nil
  }

  // MARK: - Active State

  /// Mark this router as the active one. Deactivates the parent.
  package func activate() {
    log("activate (level \(level))")
    isActive = true
    parent?.deactivate()
  }

  /// Mark this router as inactive.
  package func deactivate() {
    log("deactivate (level \(level))")
    isActive = false
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
      identifierTab: tab,
      parent: self,
      logger: logger)
    child.deepLinkHandler = deepLinkHandler
    tabChildren[tab] = child
    log("childRouter created for tab \(tab) at level \(child.level)")
    return child
  }

  /// Create a child router for a modal's NavigationContainer.
  package func childRouter() -> Router {
    let child = Router(
      level: level + 1,
      identifierTab: nil,
      parent: self,
      logger: logger)
    child.deepLinkHandler = deepLinkHandler
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

  /// Handler that converts a URL into a `Destination`, set by `configureDeepLinks`.
  ///
  /// This closure is retained for the router's lifetime (often app lifetime) and propagated
  /// to all child routers. Prefer `configureDeepLinks(scheme:parsers:)` which captures only
  /// value types. If setting directly, use `[weak self]` to avoid retain cycles.
  @ObservationIgnored public private(set) var deepLinkHandler: (@MainActor @Sendable (URL) -> Destination<Scene>?)?

  /// Configure deep link handling with a URL scheme and an ordered list of parsers.
  ///
  /// The URL's scheme must match `scheme` (case-insensitive). Parsers are tried
  /// in order; the first non-nil result wins.
  ///
  /// ```swift
  /// router.configureDeepLinks(scheme: "myapp", parsers: [
  ///   .equal(to: ["settings"], destination: .tab(.settings)),
  /// ])
  /// ```
  public func configureDeepLinks(scheme: String, parsers: [DeepLinkParser<Scene>]) {
    deepLinkHandler = { url in
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

  private func log(_ message: String) {
    logger?.debug("Router[\(self.level)]: \(message)")
  }
}
