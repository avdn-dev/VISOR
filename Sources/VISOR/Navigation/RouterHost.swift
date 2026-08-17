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
/// Use ``RouterStack`` when the hosted layout is a single `NavigationStack`.
public struct RouterHost<
  Scene: NavigationScene,
  Content: View,
  PushView: View,
  SheetView: View,
  FullScreenView: View
>: View {

  // MARK: Lifecycle

  /// Creates a host for an existing Router.
  public init(
    router: Router<Scene>,
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
  }

  /// Creates a host for a cached top-level destination Router.
  public init(
    parentRouter: Router<Scene>,
    root: Scene.Root,
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      router: parentRouter.childRouter(for: root),
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent,
      content: content)
  }

  // MARK: Public

  public var body: some View {
    RouterHostContent(
      router: router,
      content: content,
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent)
      .environment(router)
      .environment(\.router, router)
      .onAppear(perform: router.activate)
      .onDisappear(perform: router.deactivate)
      .onOpenURL { url in
        guard router.receivesDeepLinks else { return }
        router.openDeepLink(url)
      }
      .id(ObjectIdentifier(router))
  }

  // MARK: Private

  private let router: Router<Scene>
  private let content: Content
  private let pushContent: (Scene.Push) -> PushView
  private let sheetContent: (Scene.Sheet) -> SheetView
  private let fullScreenContent: (Scene.FullScreen) -> FullScreenView
}

// MARK: - RouterHostContent

/// Uses `@Bindable` to bridge Router presentation state to SwiftUI.
private struct RouterHostContent<
  Scene: NavigationScene,
  Content: View,
  PushView: View,
  SheetView: View,
  FullScreenView: View
>: View {

  @Bindable var router: Router<Scene>
  let content: Content
  let pushContent: (Scene.Push) -> PushView
  let sheetContent: (Scene.Sheet) -> SheetView
  let fullScreenContent: (Scene.FullScreen) -> FullScreenView

  var body: some View {
    content
      .sheet(item: $router.sheetPresentation) { presentation in
        RouterStack(
          presentedRouter: presentation.router,
          pushContent: pushContent,
          sheetContent: sheetContent,
          fullScreenContent: fullScreenContent
        ) {
          sheetContent(presentation.destination)
        }
      }
      .adaptiveFullScreenPresentation(item: $router.fullScreenPresentation) { presentation in
        RouterStack(
          presentedRouter: presentation.router,
          pushContent: pushContent,
          sheetContent: sheetContent,
          fullScreenContent: fullScreenContent
        ) {
          fullScreenContent(presentation.destination)
        }
      }
  }
}

// MARK: - Platform-Adaptive Presentation

private extension View {
  @ViewBuilder
  func adaptiveFullScreenPresentation<Item: Identifiable, PresentedContent: View>(
    item: Binding<Item?>,
    @ViewBuilder content: @escaping (Item) -> PresentedContent
  ) -> some View {
    #if os(macOS)
    sheet(item: item) { content($0) }
    #else
    fullScreenCover(item: item) { content($0) }
    #endif
  }
}
