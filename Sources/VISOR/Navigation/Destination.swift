//
//  Destination.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

/// A unified destination for Router navigation and deep link dispatch.
public enum Destination<Scene: NavigationScene> {
  /// Select the specified top-level destination.
  case root(Scene.Root)
  /// Push a destination onto the navigation stack.
  case push(Scene.Push)
  /// Present a modal sheet.
  case sheet(Scene.Sheet)
  /// Present a destination with full-screen intent.
  case fullScreen(Scene.FullScreen)
}

nonisolated extension Destination: Equatable {}
nonisolated extension Destination: Hashable {}
nonisolated extension Destination: Sendable {}
