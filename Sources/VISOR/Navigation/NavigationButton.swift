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
  public init(
    push destination: Scene.Push,
    @ViewBuilder label: @escaping () -> Label)
  {
    action = { router in router.push(destination) }
    self.label = label
  }

  /// Create a button that presents a sheet.
  public init(
    sheet destination: Scene.Sheet,
    @ViewBuilder label: @escaping () -> Label)
  {
    action = { router in router.present(sheet: destination) }
    self.label = label
  }

  /// Create a button that presents a full-screen cover.
  public init(
    fullScreen destination: Scene.FullScreen,
    @ViewBuilder label: @escaping () -> Label)
  {
    action = { router in router.present(fullScreen: destination) }
    self.label = label
  }

  // MARK: Public

  public var body: some View {
    Button {
      action(router)
    } label: {
      label()
    }
  }

  // MARK: Private

  @Environment(Router<Scene>.self) private var router
  private let action: (Router<Scene>) -> Void
  private let label: () -> Label
}
