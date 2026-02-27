//
//  NavigationScene.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftUI

// MARK: - Destination Protocols

/// A destination that can be pushed onto a NavigationStack.
public protocol PushDestination: Hashable {
  associatedtype Body: View
  @ViewBuilder var destinationView: Body { get }
}

/// A destination that can be presented as a sheet.
/// Identifiable conformance is required by SwiftUI's `.sheet(item:)`.
public protocol SheetDestination: Hashable, Identifiable {
  associatedtype Body: View
  @ViewBuilder var destinationView: Body { get }
}

/// A destination that can be presented as a full-screen cover.
/// Identifiable conformance is required by SwiftUI's `.fullScreenCover(item:)`.
public protocol FullScreenDestination: Hashable, Identifiable {
  associatedtype Body: View
  @ViewBuilder var destinationView: Body { get }
}

/// A tab identifier. Tabs define their views in the consumer's TabView, so no view is required here.
public protocol TabDestination: Hashable {}

// MARK: - NavigationScene

/// Groups the four destination types into a single generic parameter.
///
/// Conform an enum to this protocol to define all navigation destinations for your app:
/// ```swift
/// enum AppScene: NavigationScene {
///   typealias Push = AppPush
///   typealias Sheet = AppSheet
///   typealias FullScreen = AppFullScreen
///   typealias Tab = AppTab
/// }
/// ```
public protocol NavigationScene {
  associatedtype Push: PushDestination
  associatedtype Sheet: SheetDestination
  associatedtype FullScreen: FullScreenDestination
  associatedtype Tab: TabDestination
}
