//
//  NavigationScene.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

// MARK: - PushDestination

/// A destination that can be pushed onto a NavigationStack.
///
/// Conforming types serve as route values — they carry stable identifiers and any
/// lightweight input needed to configure the destination, but do not create the
/// view themselves. View creation is handled by the content closures passed to
/// ``RouterStack``.
public protocol PushDestination: Hashable, Sendable { }

// MARK: - PresentableDestination

/// Shared requirements for modal destinations (sheets and full-screen presentations).
///
/// Conforming types serve as route values. `Identifiable` is required by SwiftUI's
/// item-driven presentation modifiers. The `id` identifies the logical presentation
/// and may remain stable while other destination payload changes. View resolution is
/// handled by the content closures passed to ``RouterHost`` and ``RouterStack``.
public protocol PresentableDestination: Hashable, Identifiable, Sendable { }

// MARK: - SheetDestination

/// A destination that can be presented as a sheet.
public protocol SheetDestination: PresentableDestination { }

// MARK: - FullScreenDestination

/// A destination with full-screen presentation intent.
///
/// ``RouterHost`` uses a native full-screen cover where available and
/// adapts the presentation to a sheet on macOS.
public protocol FullScreenDestination: PresentableDestination { }

// MARK: - RootDestination

/// A top-level navigation destination.
///
/// Root destinations identify independently stateful navigation branches. The
/// application decides whether to render them as tabs, sidebar rows, split-view
/// selections, or another native platform navigation pattern. `allCases`
/// declares the complete finite value space because ``Router`` retains one
/// child Router per root to preserve each branch's navigation state. Prefer a
/// no-payload enum so Swift can synthesise `CaseIterable` correctly.
public protocol RootDestination: CaseIterable, Hashable, Sendable { }

// MARK: - NoRootDestination

/// The default root destination for navigation scenes with a single stack.
public enum NoRootDestination: RootDestination { }

// MARK: - NoModalDestination

/// The default modal destination for navigation scenes without routed presentations.
///
/// Its sole case is unavailable, so application code cannot construct a sheet or
/// full-screen destination when the corresponding associated type uses this default.
public enum NoModalDestination: SheetDestination, FullScreenDestination {
  @available(*, unavailable, message: "No modal destination can be constructed.")
  case unavailable

  public var id: Self {
    self
  }
}

// MARK: - NavigationScene

/// Groups the destination types into a single generic parameter. `Sheet` and
/// `FullScreen` default to ``NoModalDestination``, while `Root` defaults to
/// ``NoRootDestination`` for single-stack applications.
///
/// Conform an enum to this protocol to define all navigation destinations for your app:
/// ```swift
/// nonisolated enum AppScene: NavigationScene {
///   typealias Push = AppPush
///   typealias Sheet = AppSheet
///   typealias FullScreen = AppFullScreen
///   typealias Root = AppRoot
/// }
/// ```
public protocol NavigationScene: SendableMetatype {
  /// Values that can be pushed on this scene's navigation stacks.
  associatedtype Push: PushDestination

  /// Values that can be presented as sheets in this scene.
  associatedtype Sheet: SheetDestination = NoModalDestination

  /// Values that can be presented with full-screen intent in this scene.
  associatedtype FullScreen: FullScreenDestination = NoModalDestination

  /// Independently stateful top-level branches in this scene.
  associatedtype Root: RootDestination = NoRootDestination
}
