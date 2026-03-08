//
//  NavigationContainer.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftUI

// MARK: - NavigationContainer

/// A container that wires a Router to NavigationStack, sheet, and fullScreenCover.
///
/// Each NavigationContainer creates a child Router from the parent. Sheets and
/// full-screen covers get their own child NavigationContainer, enabling push
/// navigation within modals.
///
/// The container manages the child router's lifecycle automatically:
/// - `onAppear` marks the router as active (enabling deep link dispatch).
/// - `onDisappear` resigns active status (pausing deep link handling).
/// - `onOpenURL` routes incoming URLs through the router's deep link handler.
public struct NavigationContainer<Scene: NavigationScene, Content: View>: View {

  // MARK: Lifecycle

  /// Create a NavigationContainer for a tab.
  public init(
    parentRouter: Router<Scene>,
    tab: Scene.Tab,
    @ViewBuilder content: () -> Content)
  {
    self._router = State(initialValue: parentRouter.childRouter(for: tab))
    self.content = content()
  }

  /// Create a NavigationContainer for a modal (sheet or full-screen cover).
  public init(
    parentRouter: Router<Scene>,
    @ViewBuilder content: () -> Content)
  {
    self._router = State(initialValue: parentRouter.childRouter())
    self.content = content()
  }

  // MARK: Public

  public var body: some View {
    InnerContainer(router: router, content: content)
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
}

// MARK: - InnerContainer

/// Inner container that uses `@Bindable` for SwiftUI bindings to the router.
/// Separated from NavigationContainer because `@State` and `@Bindable` can't
/// be applied to the same property.
private struct InnerContainer<Scene: NavigationScene, Content: View>: View {

  @Bindable var router: Router<Scene>
  let content: Content

  var body: some View {
    NavigationStack(path: $router.navigationPath) {
      content
        .navigationDestination(for: Scene.Push.self) { destination in
          destination.destinationView
        }
    }
    .sheet(item: $router.presentingSheet) { sheet in
      NavigationContainer<Scene, _>(parentRouter: router) {
        sheet.destinationView
      }
    }
    #if os(iOS)
    .fullScreenCover(item: $router.presentingFullScreen) { fullScreen in
      NavigationContainer<Scene, _>(parentRouter: router) {
        fullScreen.destinationView
      }
    }
    #endif
  }
}
