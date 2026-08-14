//
//  NavigationContainer.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftUI

// MARK: - NavigationContainer

/// A container that wires a Router to a NavigationStack and modal presentation.
///
/// A root container may bind a Router directly for a single stack. Tab and modal
/// containers create child Routers with isolated navigation state. Sheets and
/// full-screen presentations get their own child NavigationContainer, enabling push
/// navigation within modals. Content closures propagate automatically to nested
/// modal containers.
///
/// Full-screen destinations use SwiftUI's native full-screen cover where it is
/// available and adapt to a sheet on macOS.
///
/// The container manages the child router's lifecycle automatically:
/// - `onAppear` marks the router as active (enabling deep link dispatch).
/// - `onDisappear` resigns active status (pausing deep link handling).
/// - `onOpenURL` routes incoming URLs through the router's deep link handler.
///
/// - Parameters:
///   - pushContent: Maps a `Scene.Push` value to its view. Called by `navigationDestination(for:)`.
///   - sheetContent: Maps a `Scene.Sheet` value to its view. Called by `.sheet(item:)`.
///   - fullScreenContent: Maps a `Scene.FullScreen` value to its adaptively presented view.
public struct NavigationContainer<
  Scene: NavigationScene,
  Content: View,
  PushView: View,
  SheetView: View,
  FullScreenView: View
>: View {

  // MARK: Lifecycle

  /// Create a root NavigationContainer for a single navigation stack.
  public init(
    router: Router<Scene>,
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content)
  {
    _router = State(initialValue: router)
    self.content = content()
    self.pushContent = pushContent
    self.sheetContent = sheetContent
    self.fullScreenContent = fullScreenContent
  }

  /// Create a NavigationContainer for a tab.
  public init(
    parentRouter: Router<Scene>,
    tab: Scene.Tab,
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content)
  {
    _router = State(initialValue: parentRouter.childRouter(for: tab))
    self.content = content()
    self.pushContent = pushContent
    self.sheetContent = sheetContent
    self.fullScreenContent = fullScreenContent
  }

  /// Create a NavigationContainer for a modal presentation.
  public init(
    parentRouter: Router<Scene>,
    @ViewBuilder pushContent: @escaping (Scene.Push) -> PushView,
    @ViewBuilder sheetContent: @escaping (Scene.Sheet) -> SheetView,
    @ViewBuilder fullScreenContent: @escaping (Scene.FullScreen) -> FullScreenView,
    @ViewBuilder content: () -> Content)
  {
    _router = State(initialValue: parentRouter.childRouter())
    self.content = content()
    self.pushContent = pushContent
    self.sheetContent = sheetContent
    self.fullScreenContent = fullScreenContent
  }

  // MARK: Public

  public var body: some View {
    InnerContainer(
      router: router,
      content: content,
      pushContent: pushContent,
      sheetContent: sheetContent,
      fullScreenContent: fullScreenContent)
      .environment(router)
      .environment(\.router, router)
      .onAppear { router.activate() }
      .onDisappear { router.deactivate() }
      .onOpenURL { url in
        if let destination = router.deepLinkHandler?(url) {
          router.deepLinkOpen(to: destination)
        }
      }
  }

  // MARK: Private

  @State private var router: Router<Scene>
  private let content: Content
  private let pushContent: (Scene.Push) -> PushView
  private let sheetContent: (Scene.Sheet) -> SheetView
  private let fullScreenContent: (Scene.FullScreen) -> FullScreenView
}

// MARK: - InnerContainer

/// Inner container that uses `@Bindable` for SwiftUI bindings to the router.
/// Separated from NavigationContainer because `@State` and `@Bindable` can't
/// be applied to the same property.
private struct InnerContainer<
  Scene: NavigationScene, Content: View,
  PushView: View, SheetView: View, FullScreenView: View
>: View {

  @Bindable var router: Router<Scene>
  let content: Content
  let pushContent: (Scene.Push) -> PushView
  let sheetContent: (Scene.Sheet) -> SheetView
  let fullScreenContent: (Scene.FullScreen) -> FullScreenView

  var body: some View {
    NavigationStack(path: $router.navigationPath) {
      content
        .navigationDestination(for: Scene.Push.self) { destination in
          pushContent(destination)
        }
    }
    .sheet(item: $router.presentingSheet) { sheet in
      NavigationContainer(
        parentRouter: router,
        pushContent: pushContent,
        sheetContent: sheetContent,
        fullScreenContent: fullScreenContent
      ) {
        sheetContent(sheet)
      }
    }
    .adaptiveFullScreenPresentation(item: $router.presentingFullScreen) { fullScreen in
      NavigationContainer(
        parentRouter: router,
        pushContent: pushContent,
        sheetContent: sheetContent,
        fullScreenContent: fullScreenContent
      ) {
        fullScreenContent(fullScreen)
      }
    }
  }
}

// MARK: - Platform-Adaptive Presentation

private extension View {
  @ViewBuilder
  func adaptiveFullScreenPresentation<Item: Identifiable, PresentedContent: View>(
    item: Binding<Item?>,
    @ViewBuilder content: @escaping (Item) -> PresentedContent)
    -> some View
  {
    #if os(macOS)
    sheet(item: item) { content($0) }
    #else
    fullScreenCover(item: item) { content($0) }
    #endif
  }
}
