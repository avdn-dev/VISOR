//
//  RouterStack.swift
//  VISOR
//
//  Created by Anh Nguyen on 16/8/2026.
//

import SwiftUI

// MARK: - RouterStack

/// A Router host whose application-owned navigation layout is one `NavigationStack`.
///
/// `RouterStack` binds the Router's path, resolves push destinations, and uses
/// ``RouterHost`` for lifecycle, deep-link, environment, and modal presentation
/// handling. Use `RouterHost` directly when the application needs a split view
/// or another native navigation container.
///
/// Pass `onDeepLinkOutcome` to react to URLs delivered automatically to the
/// active stack. Router-owned modal stacks inherit the callback.
public struct RouterStack<
  Scene: NavigationScene,
  Content: View,
  PushView: View,
  SheetView: View,
  FullScreenView: View
>: View {

  // MARK: Lifecycle

  /// Creates a stack for an existing Router and an optional automatic URL outcome callback.
  public init(
    router: Router<Scene>,
    onDeepLinkOutcome: @escaping @MainActor (DeepLinkOutcome<Scene>) -> Void = { _ in },
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content
  ) {
    self.router = router
    self.content = content()
    self.pushContent = pushContent
    self.sheetContent = sheetContent
    self.fullScreenContent = fullScreenContent
    self.onDeepLinkOutcome = onDeepLinkOutcome
  }

  /// Creates a stack for a cached top-level destination Router.
  public init(
    parentRouter: Router<Scene>,
    root: Scene.Root,
    onDeepLinkOutcome: @escaping @MainActor (DeepLinkOutcome<Scene>) -> Void = { _ in },
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      router: parentRouter.childRouter(for: root),
      onDeepLinkOutcome: onDeepLinkOutcome,
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent,
      content: content)
  }

  init(
    presentedRouter: Router<Scene>,
    onDeepLinkOutcome: @escaping @MainActor (DeepLinkOutcome<Scene>) -> Void,
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      router: presentedRouter,
      onDeepLinkOutcome: onDeepLinkOutcome,
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent,
      content: content)
  }

  // MARK: Public

  public var body: some View {
    RouterHost(
      router: router,
      onDeepLinkOutcome: onDeepLinkOutcome,
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent
    ) {
      RouterStackContent(
        router: router,
        content: content,
        pushContent: pushContent)
    }
  }

  // MARK: Private

  private let router: Router<Scene>
  private let content: Content
  private let pushContent: (Scene.Push) -> PushView
  private let sheetContent: (Scene.Sheet) -> SheetView
  private let fullScreenContent: (Scene.FullScreen) -> FullScreenView
  private let onDeepLinkOutcome: @MainActor (DeepLinkOutcome<Scene>) -> Void
}

// MARK: - Push-Only RouterStack

public extension RouterStack where
  Scene.Sheet == NoModalDestination,
  Scene.FullScreen == NoModalDestination,
  SheetView == EmptyView,
  FullScreenView == EmptyView
{
  /// Creates a push-only stack for an existing Router.
  init(
    router: Router<Scene>,
    onDeepLinkOutcome: @escaping @MainActor (DeepLinkOutcome<Scene>) -> Void = { _ in },
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      router: router,
      onDeepLinkOutcome: onDeepLinkOutcome,
      pushContent: pushContent,
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
      content: content)
  }

  /// Creates a push-only stack for a cached top-level destination Router.
  init(
    parentRouter: Router<Scene>,
    root: Scene.Root,
    onDeepLinkOutcome: @escaping @MainActor (DeepLinkOutcome<Scene>) -> Void = { _ in },
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      router: parentRouter.childRouter(for: root),
      onDeepLinkOutcome: onDeepLinkOutcome,
      pushContent: pushContent,
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
      content: content)
  }
}

// MARK: - RouterStackContent

private struct RouterStackContent<
  Scene: NavigationScene,
  Content: View,
  PushView: View
>: View {

  @Bindable var router: Router<Scene>
  let content: Content
  let pushContent: (Scene.Push) -> PushView

  var body: some View {
    NavigationStack(path: $router.navigationPath) {
      content
        .navigationDestination(for: Scene.Push.self) { destination in
          pushContent(destination)
        }
    }
  }
}
