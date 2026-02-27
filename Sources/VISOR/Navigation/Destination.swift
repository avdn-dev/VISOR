//
//  Destination.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

/// A unified destination for Router navigation and deep link dispatch.
public enum Destination<Scene: NavigationScene> {
  /// Switch to the specified tab.
  case tab(Scene.Tab)
  /// Push a destination onto the navigation stack.
  case push(Scene.Push)
  /// Present a modal sheet.
  case sheet(Scene.Sheet)
  /// Present a full-screen cover.
  case fullScreen(Scene.FullScreen)
}

nonisolated extension Destination: Equatable {}
nonisolated extension Destination: Hashable {}
nonisolated extension Destination: Sendable {}
