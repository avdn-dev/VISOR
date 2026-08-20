//
//  Router.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import Foundation
import OSLog

// MARK: - DeepLinkConfigurationError

/// An invalid value supplied to ``Router/configureDeepLinks(scheme:parsers:)``.
nonisolated public enum DeepLinkConfigurationError: Error, Equatable, Sendable {
  /// The scheme does not follow the URL scheme grammar from RFC 3986.
  ///
  /// A scheme must start with an ASCII letter and may then contain ASCII
  /// letters, digits, `+`, `-`, or `.`.
  ///
  /// - Parameter scheme: The rejected scheme.
  case invalidScheme(String)
}

extension DeepLinkConfigurationError: LocalizedError {
  /// A human-readable explanation suitable for configuration diagnostics.
  public var errorDescription: String? {
    switch self {
    case .invalidScheme(let scheme):
      "Invalid deep-link scheme '\(scheme)'. A scheme must start with an ASCII letter and contain only ASCII letters, digits, '+', '-', or '.'."
    }
  }
}

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

  /// The URL resolved, but no RouterHost is currently mounted.
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
/// The root Router coordinates one navigation tree. A ``RouterHost`` may bind
/// it directly, while top-level destinations and modal presentation records use
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
    self.rootDestination = nil
    self.parent = nil
    self.logger = logger
    self.treeContext = RouterTreeContext()
    isActive = false
  }

  /// Creates a router node in the navigation hierarchy.
  ///
  /// - Parameters:
  ///   - level: Depth in the hierarchy (0 = root). Incremented automatically by `childRouter()`.
  ///   - rootDestination: The top-level destination this router manages, or
  ///     `nil` for root and modal Routers.
  ///   - parent: The parent router. Stored as a `weak` reference to avoid retain cycles.
  ///   - logger: Optional `os.Logger` for debug-level navigation logging.
  package init(
    level: Int,
    rootDestination: Scene.Root? = nil,
    parent: Router? = nil,
    logger: Logger? = nil)
  {
    self.level = level
    self.rootDestination = rootDestination
    self.parent = parent
    self.logger = logger
    self.treeContext = parent?.treeContext ?? RouterTreeContext()
    isActive = false
  }

  // MARK: - Navigation State

  /// The currently selected top-level destination.
  ///
  /// The setter remains public so application-owned tab and split-view
  /// selectors can bind to it. Use ``select(root:)`` for imperative changes.
  public var selectedRoot: Scene.Root?

  /// The navigation stack path for push destinations.
  ///
  /// The setter remains public so a custom `NavigationStack` hosted by
  /// ``RouterHost`` can bind to it. Use ``push(_:)`` and ``popToRoot()`` for
  /// imperative changes.
  public var navigationPath: [Scene.Push] = []

  /// The currently presented sheet, if any.
  ///
  /// A Router node has one modal presentation slot. Presenting a sheet
  /// replaces any full-screen presentation held by the same Router.
  /// Use ``present(sheet:)`` and ``dismissSheet()`` to mutate it.
  public var presentingSheet: Scene.Sheet? {
    sheetPresentation?.destination
  }

  /// The currently presented destination with full-screen intent, if any.
  ///
  /// A Router node has one modal presentation slot. Presenting a full-screen
  /// destination replaces any sheet held by the same Router.
  /// Use ``present(fullScreen:)`` and ``dismissFullScreen()`` to mutate it.
  public var presentingFullScreen: Scene.FullScreen? {
    fullScreenPresentation?.destination
  }

  // MARK: - Hierarchy

  /// The depth level of this router (0 = root).
  public let level: Int

  /// The top-level destination this Router is associated with.
  ///
  /// Root and modal Routers have no root destination.
  public let rootDestination: Scene.Root?

  /// The parent router. Weak to avoid retain cycles; `let` because it never changes after init.
  package weak let parent: Router?

  /// Whether this Router is the active visible target for root navigation
  /// actions and deep links.
  public private(set) var isActive: Bool

  // MARK: - Navigation Actions

  /// Push a destination onto the navigation stack. Root calls target the
  /// currently active visible Router; child calls remain local.
  ///
  /// - Parameter destination: The typed destination to append.
  /// - Returns: `true` when the action was accepted, or `false` when no
  ///   `RouterHost` is active for a root Router.
  @discardableResult
  public func push(_ destination: Scene.Push) -> Bool {
    guard let target = navigationActionTarget(for: "push") else { return false }
    target.pushLocally(destination)
    return true
  }

  /// Present a sheet.
  ///
  /// When called on the root Router, delegates to the currently active visible
  /// Router. Calls on a child Router remain local to that child.
  ///
  /// - Parameter sheet: The typed sheet destination to present.
  /// - Returns: `true` when the action was accepted, or `false` when no
  ///   `RouterHost` is active for a root Router.
  @discardableResult
  public func present(sheet: Scene.Sheet) -> Bool {
    guard let target = navigationActionTarget(for: "present sheet") else { return false }
    target.presentSheetLocally(sheet)
    return true
  }

  /// Present a destination with full-screen intent.
  ///
  /// When called on the root Router, delegates to the currently active visible
  /// Router. Calls on a child Router remain local to that child.
  ///
  /// - Parameter fullScreen: The typed full-screen destination to present.
  /// - Returns: `true` when the action was accepted, or `false` when no
  ///   `RouterHost` is active for a root Router.
  @discardableResult
  public func present(fullScreen: Scene.FullScreen) -> Bool {
    guard let target = navigationActionTarget(for: "present fullScreen") else { return false }
    target.presentFullScreenLocally(fullScreen)
    return true
  }

  /// Select a top-level destination.
  ///
  /// Calls on child Routers propagate to the root Router.
  ///
  /// - Parameter root: The top-level destination to select.
  public func select(root: Scene.Root) {
    log("select root: \(root)")
    if let parent {
      parent.select(root: root)
    } else {
      selectedRoot = root
    }
  }

  /// Navigate to a unified destination.
  ///
  /// - Parameter destination: The root, push, sheet, or full-screen destination.
  /// - Returns: `true` when the action was accepted, or `false` when the
  ///   destination needs an active `RouterHost` and none is active.
  @discardableResult
  public func navigate(to destination: Destination<Scene>) -> Bool {
    switch destination {
    case .root(let root):
      select(root: root)
      return true
    case .push(let destination):
      return push(destination)
    case .sheet(let sheet):
      return present(sheet: sheet)
    case .fullScreen(let fullScreen):
      return present(fullScreen: fullScreen)
    }
  }

  /// Select a top-level destination and push onto its navigation stack.
  ///
  /// - Parameters:
  ///   - root: The top-level destination whose cached Router should receive the push.
  ///   - destination: The destination to append before selecting `root`.
  public func selectAndPush(root: Scene.Root, destination: Scene.Push) {
    let rootRouter = rootRouter
    rootRouter.log("selectAndPush: root=\(root), destination=\(destination)")
    rootRouter.childRouter(for: root).pushLocally(destination)
    rootRouter.selectedRoot = root
  }

  /// Pop to the root of the navigation stack. Root calls target the currently
  /// active visible Router; child calls remain local.
  ///
  /// - Returns: `true` when the action was accepted, or `false` when no
  ///   `RouterHost` is active for a root Router.
  @discardableResult
  public func popToRoot() -> Bool {
    guard let target = navigationActionTarget(for: "popToRoot") else { return false }
    target.popToRootLocally()
    return true
  }

  /// Dismiss the currently presented sheet.
  ///
  /// When called on a router that does not itself hold the sheet presentation,
  /// walks up the parent chain to find the ancestor that does and clears it there.
  ///
  /// - Returns: `true` when a sheet was dismissed; otherwise `false`.
  @discardableResult
  public func dismissSheet() -> Bool {
    guard let target = navigationActionTarget(for: "dismissSheet") else { return false }
    return target.dismissSheetLocally()
  }

  /// Dismiss the currently presented full-screen destination.
  ///
  /// When called on a router that does not itself hold the full-screen
  /// presentation, walks up the parent chain to find the ancestor that does
  /// and clears it there.
  ///
  /// - Returns: `true` when a full-screen destination was dismissed; otherwise
  ///   `false`.
  @discardableResult
  public func dismissFullScreen() -> Bool {
    guard let target = navigationActionTarget(for: "dismissFullScreen") else { return false }
    return target.dismissFullScreenLocally()
  }

  // MARK: - Active State

  /// Marks this Router as mounted and makes it active unless one of its mounted
  /// descendants is already the active visible node.
  package func activate() {
    log("activate (level \(level))")
    isMounted = true
    if let activeRouter = treeContext.activeRouter,
       activeRouter !== self,
       activeRouter.isMounted,
       activeRouter.isDescendant(of: self)
    {
      isActive = false
      return
    }
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
  ///
  /// - Parameter url: The external URL to validate and dispatch.
  /// - Returns: An explicit outcome describing whether and why dispatch succeeded.
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
        guard target.navigate(to: destination) else {
          return reportDeepLinkOutcome(.inactive)
        }
        return reportDeepLinkOutcome(.handled(destination))
      }
    }

    return reportDeepLinkOutcome(.unmatched)
  }

  // MARK: - Child Management

  /// Creates or returns the cached child Router for a top-level destination.
  ///
  /// - Parameter root: The bounded, application-owned navigation branch.
  /// - Returns: The stable Router associated with `root`.
  public func childRouter(for root: Scene.Root) -> Router {
    if let existing = rootChildren[root] {
      return existing
    }
    let child = Router(
      level: level + 1,
      rootDestination: root,
      parent: self,
      logger: logger)
    rootChildren[root] = child
    log("childRouter created for root \(root) at level \(child.level)")
    return child
  }

  /// Creates a child Router for a modal's RouterStack.
  package func childRouter() -> Router {
    let child = Router(
      level: level + 1,
      rootDestination: nil,
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

  /// Creates a preview Router with the given top-level destination selected.
  ///
  /// - Parameter root: The optional top-level destination selected initially.
  /// - Returns: An inactive Router intended for preview composition.
  public static func preview(root: Scene.Root? = nil) -> Router {
    let router = Router()
    router.selectedRoot = root
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
  /// try router.configureDeepLinks(scheme: "myapp", parsers: [
  ///   .equal(to: ["profile"], destination: .root(.profile)),
  /// ])
  /// ```
  ///
  /// An empty parser list is valid and makes matching URLs return
  /// ``DeepLinkOutcome/unmatched``.
  ///
  /// - Parameters:
  ///   - scheme: The URL scheme, without `://`.
  ///   - parsers: Parsers evaluated in declaration order.
  /// - Throws: ``DeepLinkConfigurationError/invalidScheme(_:)`` when `scheme`
  ///   is empty or violates URL scheme grammar.
  public func configureDeepLinks(
    scheme: String,
    parsers: [DeepLinkParser<Scene>]
  ) throws {
    guard Self.isValidURLScheme(scheme) else {
      throw DeepLinkConfigurationError.invalidScheme(scheme)
    }
    treeContext.deepLinkConfiguration = RouterDeepLinkConfiguration(
      scheme: scheme.lowercased(),
      parsers: parsers)
  }

  // MARK: Private

  private let logger: Logger?
  /// Cached child Routers keyed by top-level destination. The cache is
  /// intentionally never evicted so each destination preserves its navigation
  /// state while another destination is selected.
  @ObservationIgnored private var rootChildren: [Scene.Root: Router] = [:]
  @ObservationIgnored private let treeContext: RouterTreeContext<Scene>
  @ObservationIgnored private var isMounted = false
  private var modalPresentation: RouterModalPresentation<Scene>?

  private var rootRouter: Router {
    parent?.rootRouter ?? self
  }

  private func isDescendant(of router: Router) -> Bool {
    var ancestor = parent
    while let candidate = ancestor {
      if candidate === router { return true }
      ancestor = candidate.parent
    }
    return false
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
    if let selectedRoot = root.selectedRoot,
       let selectedRouter = root.rootChildren[selectedRoot],
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

    log("\(action) rejected: no RouterHost is active")
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

  private func dismissSheetLocally() -> Bool {
    if case .sheet = modalPresentation {
      log("dismissSheet")
      modalPresentation = nil
      return true
    } else if let parent {
      log("dismissSheet (walking up)")
      return parent.dismissSheetLocally()
    }
    return false
  }

  private func dismissFullScreenLocally() -> Bool {
    if case .fullScreen = modalPresentation {
      log("dismissFullScreen")
      modalPresentation = nil
      return true
    } else if let parent {
      log("dismissFullScreen (walking up)")
      return parent.dismissFullScreenLocally()
    }
    return false
  }

  private func log(_ message: String) {
    logger?.debug("Router[\(self.level)]: \(message)")
  }

  private nonisolated static func isValidURLScheme(_ scheme: String) -> Bool {
    let scalars = scheme.unicodeScalars
    guard let first = scalars.first, isASCIILetter(first) else { return false }
    return scalars.dropFirst().allSatisfy { scalar in
      isASCIILetter(scalar)
        || (48...57).contains(scalar.value)
        || scalar == "+"
        || scalar == "-"
        || scalar == "."
    }
  }

  private nonisolated static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
    (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
  }
}
