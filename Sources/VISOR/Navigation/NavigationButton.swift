//
//  NavigationButton.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftUI

/// A convenience button that reads the Router from the environment and performs a navigation action.
public struct NavigationButton<Scene: NavigationScene, Label: View>: View {

  // MARK: Lifecycle

  /// Create a button that pushes a destination.
  ///
  /// - Parameters:
  ///   - destination: The destination pushed by the button.
  ///   - label: The button's visual content.
  public init(
    push destination: Scene.Push,
    @ViewBuilder label: () -> Label)
  {
    action = { router in _ = router.push(destination) }
    self.label = label()
  }

  /// Create a button that presents a sheet.
  ///
  /// - Parameters:
  ///   - destination: The sheet destination presented by the button.
  ///   - label: The button's visual content.
  public init(
    sheet destination: Scene.Sheet,
    @ViewBuilder label: () -> Label)
  {
    action = { router in _ = router.present(sheet: destination) }
    self.label = label()
  }

  /// Create a button that presents a destination with full-screen intent.
  ///
  /// - Parameters:
  ///   - destination: The full-screen destination presented by the button.
  ///   - label: The button's visual content.
  public init(
    fullScreen destination: Scene.FullScreen,
    @ViewBuilder label: () -> Label)
  {
    action = { router in _ = router.present(fullScreen: destination) }
    self.label = label()
  }

  // MARK: Public

  public var body: some View {
    Button {
      action(router)
    } label: {
      label
    }
  }

  // MARK: Private

  @Environment(Router<Scene>.self) private var router
  private let action: (Router<Scene>) -> Void
  private let label: Label
}
