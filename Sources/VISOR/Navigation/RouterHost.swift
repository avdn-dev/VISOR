//
//  RouterHost.swift
//  VISOR
//
//  Created by Anh Nguyen on 16/8/2026.
//

import SwiftUI

// MARK: - RouterHost

/// Mounts a Router without imposing a particular SwiftUI navigation container.
///
/// Use `RouterHost` around a `NavigationSplitView`, a sidebar-adaptable
/// `TabView`, or another application-owned navigation layout. The host injects
/// the Router into the environment, coordinates the active Router tree, handles
/// deep links, and renders Router-owned modal presentations.
///
/// Pass `onDeepLinkOutcome` to react to URLs delivered automatically to the
/// active host. Calling ``Router/openDeepLink(_:)`` directly only returns its
/// outcome and does not invoke this host callback.
///
/// Use ``RouterStack`` when the hosted layout is a single `NavigationStack`.
public struct RouterHost<
  Scene: NavigationScene,
  Content: View,
  PushView: View,
  SheetView: View,
  FullScreenView: View,
>: View {

  // MARK: Lifecycle

  /// Creates a host for an existing Router and an optional automatic URL outcome callback.
  public init(
    router: Router<Scene>,
    onDeepLinkOutcome: @escaping @MainActor (DeepLinkOutcome<Scene>) -> Void = { _ in },
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content,
  ) {
    self.router = router
    self.content = content()
    self.pushContent = pushContent
    self.sheetContent = sheetContent
    self.fullScreenContent = fullScreenContent
    self.onDeepLinkOutcome = onDeepLinkOutcome
  }

  /// Creates a host for a cached top-level destination Router.
  public init(
    parentRouter: Router<Scene>,
    root: Scene.Root,
    onDeepLinkOutcome: @escaping @MainActor (DeepLinkOutcome<Scene>) -> Void = { _ in },
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content,
  ) {
    self.init(
      router: parentRouter.childRouter(for: root),
      onDeepLinkOutcome: onDeepLinkOutcome,
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent,
      content: content,
    )
  }

  // MARK: Public

  public var body: some View {
    RouterHostContent(
      router: router,
      content: content,
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent,
      onDeepLinkOutcome: onDeepLinkOutcome,
    )
    .environment(router)
    .environment(\._visorRouter, router)
    .onAppear(perform: router.activate)
    .onDisappear(perform: router.deactivate)
    .onOpenURL { url in
      router.receiveDeepLink(url, onOutcome: onDeepLinkOutcome)
    }
    .id(ObjectIdentifier(router))
  }

  // MARK: Private

  private let router: Router<Scene>
  private let content: Content
  private let pushContent: (Scene.Push) -> PushView
  private let sheetContent: (Scene.Sheet) -> SheetView
  private let fullScreenContent: (Scene.FullScreen) -> FullScreenView
  private let onDeepLinkOutcome: @MainActor (DeepLinkOutcome<Scene>) -> Void
}

// MARK: - RouterHostContent

/// Uses `@Bindable` to bridge Router presentation state to SwiftUI.
private struct RouterHostContent<
  Scene: NavigationScene,
  Content: View,
  PushView: View,
  SheetView: View,
  FullScreenView: View,
>: View {

  @Bindable var router: Router<Scene>

  let content: Content
  let pushContent: (Scene.Push) -> PushView
  let sheetContent: (Scene.Sheet) -> SheetView
  let fullScreenContent: (Scene.FullScreen) -> FullScreenView
  let onDeepLinkOutcome: @MainActor (DeepLinkOutcome<Scene>) -> Void

  var body: some View {
    content
      .sheet(item: $router.sheetPresentation) { presentation in
        RouterStack(
          presentedRouter: presentation.router,
          onDeepLinkOutcome: onDeepLinkOutcome,
          pushContent: pushContent,
          sheetContent: sheetContent,
          fullScreenContent: fullScreenContent,
        ) {
          sheetContent(presentation.destination)
        }
      }
      .adaptiveFullScreenPresentation(item: $router.fullScreenPresentation) { presentation in
        RouterStack(
          presentedRouter: presentation.router,
          onDeepLinkOutcome: onDeepLinkOutcome,
          pushContent: pushContent,
          sheetContent: sheetContent,
          fullScreenContent: fullScreenContent,
        ) {
          fullScreenContent(presentation.destination)
        }
      }
  }
}

// MARK: - Platform-Adaptive Presentation

extension View {
  @ViewBuilder
  fileprivate func adaptiveFullScreenPresentation<Item: Identifiable>(
    item: Binding<Item?>,
    @ViewBuilder content: @escaping (Item) -> some View,
  ) -> some View {
    #if os(macOS)
    sheet(item: item) { content($0) }
    #else
    fullScreenCover(item: item) { content($0) }
    #endif
  }
}
