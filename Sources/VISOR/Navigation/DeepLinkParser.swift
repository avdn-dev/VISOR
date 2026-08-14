//
//  DeepLinkParser.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

import Foundation

// MARK: - DeepLinkRequest

/// A URL and its route components after Router scheme validation.
///
/// Components contain the URL host followed by its path segments and preserve
/// percent encoding. Custom parsers are responsible for validating component
/// counts, decoding values exactly once, and rejecting malformed identifiers.
public struct DeepLinkRequest: Hashable, Sendable {
  /// Creates a request from an external URL without decoding its route values.
  public init(url: URL) {
    self.url = url

    let pathSegments = url.path().split(separator: "/")
    var components: [String] = []
    components.reserveCapacity(1 + pathSegments.count)
    if let host = url.host() {
      components.append(host)
    }
    for segment in pathSegments {
      components.append(String(segment))
    }
    self.components = components
  }

  /// The original URL. Validate expected hosts and query items before using them.
  public let url: URL

  /// The host and path segments used for ordered route matching.
  public let components: [String]
}

// MARK: - DeepLinkParseResult

/// The result of one parser examining a deep-link request.
public enum DeepLinkParseResult<Scene: NavigationScene> {
  /// This parser does not recognise the route; evaluation may continue.
  case noMatch

  /// This parser recognises the route but its inputs are invalid; evaluation stops.
  case invalid

  /// The validated route maps to a navigation destination.
  case destination(Destination<Scene>)
}

nonisolated extension DeepLinkParseResult: Equatable {}
nonisolated extension DeepLinkParseResult: Hashable {}
nonisolated extension DeepLinkParseResult: Sendable {}

// MARK: - DeepLinkParser

/// A composable URL-to-Destination parser.
///
/// Create parsers with factory methods and pass them to
/// `Router.configureDeepLinks(scheme:parsers:)`:
///
/// ```swift
/// router.configureDeepLinks(scheme: "myapp", parsers: [
///   .equal(to: ["profile"], destination: .tab(.profile)),
///   DeepLinkParser { request in
///     guard request.components.first == "item" else { return .noMatch }
///     guard request.components.count == 2,
///           let id = UUID(uuidString: request.components[1])
///     else { return .invalid }
///     return .destination(.push(.detail(id: id)))
///   }
/// ])
/// ```
public struct DeepLinkParser<Scene: NavigationScene>: Sendable {

  // MARK: Lifecycle

  /// Creates a parser that distinguishes an unrelated route from invalid input.
  ///
  /// - Parameter parse: Validates and maps one request.
  public init(
    _ parse: @escaping @Sendable (DeepLinkRequest) -> DeepLinkParseResult<Scene>
  ) {
    self.parseRequest = parse
  }

  // MARK: Public

  /// Validate and map one request.
  public func parse(_ request: DeepLinkRequest) -> DeepLinkParseResult<Scene> {
    parseRequest(request)
  }

  // MARK: Private

  private let parseRequest:
    @Sendable (DeepLinkRequest) -> DeepLinkParseResult<Scene>
}

// MARK: - Factory Methods

extension DeepLinkParser {

  /// Match URLs whose deep link components equal the given path exactly.
  ///
  /// ```swift
  /// // Matches "myapp://profile" or "myapp:///profile"
  /// .equal(to: ["profile"], destination: .tab(.profile))
  /// ```
  public static func equal(
    to components: [String],
    destination: Destination<Scene>)
    -> DeepLinkParser
  {
    DeepLinkParser { request in
      request.components == components ? .destination(destination) : .noMatch
    }
  }
}
