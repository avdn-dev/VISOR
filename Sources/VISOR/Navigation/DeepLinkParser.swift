//
//  DeepLinkParser.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

import Foundation

// MARK: - DeepLinkParser

/// A composable URL-to-Destination parser.
///
/// Create parsers with factory methods and pass them to
/// `Router.configureDeepLinks(scheme:parsers:)`:
///
/// ```swift
/// router.configureDeepLinks(scheme: "myapp", parsers: [
///   .equal(to: ["settings"], destination: .tab(.settings)),
///   DeepLinkParser { url in
///     guard url.deepLinkComponents.first == "item",
///           let id = url.deepLinkComponents.dropFirst().first
///     else { return nil }
///     return .push(.detail(id: id))
///   }
/// ])
/// ```
public struct DeepLinkParser<Scene: NavigationScene>: Sendable {

  // MARK: Lifecycle

  public init(_ parse: @escaping @MainActor @Sendable (URL) -> Destination<Scene>?) {
    self.parse = parse
  }

  // MARK: Public

  /// The parsing closure. Returns a destination if the URL matches, nil otherwise.
  public let parse: @MainActor @Sendable (URL) -> Destination<Scene>?
}

// MARK: - Factory Methods

extension DeepLinkParser {

  /// Match URLs whose deep link components equal the given path exactly.
  ///
  /// ```swift
  /// // Matches "myapp://settings" or "myapp:///settings"
  /// .equal(to: ["settings"], destination: .tab(.settings))
  /// ```
  public static func equal(
    to components: [String],
    destination: Destination<Scene>)
    -> DeepLinkParser
  {
    DeepLinkParser { url in
      url.deepLinkComponents == components ? destination : nil
    }
  }
}

// MARK: - URL Extension

extension URL {

  /// Strips the scheme and splits the remaining path into components.
  ///
  /// - `myapp://valentine/accept` → `["valentine", "accept"]`
  /// - `myapp:///settings` → `["settings"]`
  /// - `myapp://home` → `["home"]`
  nonisolated public var deepLinkComponents: [String] {
    // host + path covers both "scheme://host/path" and "scheme:///path" forms.
    let pathSegments = path().split(separator: "/")
    var parts: [String] = []
    parts.reserveCapacity(1 + pathSegments.count)
    if let host = host() {
      parts.append(host)
    }
    for segment in pathSegments {
      parts.append(String(segment))
    }
    return parts
  }
}
