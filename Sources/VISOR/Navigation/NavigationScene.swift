//
//  NavigationScene.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftUI

// MARK: - Destination Protocols

/// A destination that can be pushed onto a NavigationStack.
///
/// Conforming types serve as identity-only route markers — they carry enough information
/// to identify the destination (typically an enum case with associated data) but do not
/// create the view themselves. View creation is handled by the content closures
/// passed to ``NavigationContainer``.
public protocol PushDestination: Hashable, Sendable {}

/// Shared requirements for modal destinations (sheets, full-screen covers).
///
/// Conforming types serve as identity-only route markers. `Identifiable` is required
/// by SwiftUI's `.sheet(item:)` and `.fullScreenCover(item:)`. View resolution is
/// handled by the content closures passed to ``NavigationContainer``.
public protocol PresentableDestination: Hashable, Identifiable, Sendable {}

/// A destination that can be presented as a sheet.
public protocol SheetDestination: PresentableDestination {}

/// A destination that can be presented as a full-screen cover.
public protocol FullScreenDestination: PresentableDestination {}

/// A tab identifier. Tabs define their views in the consumer's TabView, so no view is required here.
public protocol TabDestination: Hashable, Sendable {}

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
