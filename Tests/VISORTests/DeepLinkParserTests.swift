//
//  DeepLinkParserTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

import Foundation
import Testing
import VISOR

nonisolated private func parseDeepLink(
  _ parser: DeepLinkParser<TestScene>,
  url: URL,
) -> DeepLinkParseResult<TestScene> {
  parser.parse(DeepLinkRequest(url: url))
}

// MARK: - DeepLinkParserTests

@Suite("DeepLinkParser")
@MainActor
struct DeepLinkParserTests {

  @Test
  func `Request strips scheme and splits path`() throws {
    let url = try #require(URL(string: "myapp://valentine/accept"))
    let request = DeepLinkRequest(url: url)

    #expect(request.routeComponents == ["valentine", "accept"])
    #expect(request.isStructurallyValid)
  }

  @Test
  func `Request handles triple-slash`() throws {
    let url = try #require(URL(string: "myapp:///settings"))
    let request = DeepLinkRequest(url: url)

    #expect(request.routeComponents == ["settings"])
    #expect(request.isStructurallyValid)
  }

  @Test
  func `Request handles single component`() throws {
    let url = try #require(URL(string: "myapp://home"))
    #expect(DeepLinkRequest(url: url).routeComponents == ["home"])
  }

  @Test
  func `Request handles trailing slash`() throws {
    let url = try #require(URL(string: "myapp://settings/"))
    let request = DeepLinkRequest(url: url)

    #expect(request.routeComponents == ["settings"])
    #expect(request.isStructurallyValid)
  }

  @Test
  func `Request preserves an empty interior segment as invalid structure`() throws {
    let url = try #require(URL(string: "myapp://item//42"))
    let request = DeepLinkRequest(url: url)

    #expect(request.routeComponents == ["item", "", "42"])
    #expect(!request.isStructurallyValid)
  }

  @Test
  func `Request rejects more than one trailing separator`() throws {
    let url = try #require(URL(string: "myapp://item//"))
    let request = DeepLinkRequest(url: url)

    #expect(request.routeComponents == ["item", ""])
    #expect(!request.isStructurallyValid)
  }

  @Test
  func `Request handles host with multi-segment path`() throws {
    let url = try #require(URL(string: "myapp://item/42/detail"))
    #expect(DeepLinkRequest(url: url).routeComponents == ["item", "42", "detail"])
  }

  @Test
  func `Matching parser matches exact components`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: ["settings"],
      destination: .root(.settings),
    )

    let url = try #require(URL(string: "myapp://settings"))
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.root(.settings)))
  }

  @Test
  func `Parser can be called from a nonisolated context`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: ["settings"],
      destination: .root(.settings),
    )

    let result = parseDeepLink(parser, url: try #require(URL(string: "myapp://settings")))

    #expect(result == .destination(.root(.settings)))
  }

  @Test
  func `Matching parser rejects non-matching components`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: ["settings"],
      destination: .root(.settings),
    )

    let url = try #require(URL(string: "myapp://home"))
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .noMatch)
  }

  @Test
  func `Matching parser matches multi-component path`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: ["valentine", "accept"],
      destination: .fullScreen(.onboarding),
    )

    let url = try #require(URL(string: "myapp://valentine/accept"))
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.fullScreen(.onboarding)))
  }

  @Test
  func `Custom parser extracts dynamic values`() throws {
    let parser = DeepLinkParser<TestScene> { request in
      let parts = request.routeComponents
      guard parts.first == "detail" else { return .noMatch }
      guard parts.count == 2 else { return .invalid }
      return .destination(.push(.detail(id: parts[1])))
    }

    let url = try #require(URL(string: "myapp://detail/42"))
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.push(.detail(id: "42"))))
  }

  @Test
  func `Custom parser distinguishes unrelated and invalid routes`() throws {
    let parser = DeepLinkParser<TestScene> { request in
      let parts = request.routeComponents
      guard parts.first == "detail" else { return .noMatch }
      guard parts.count == 2 else { return .invalid }
      return .destination(.push(.detail(id: parts[1])))
    }

    let unrelated = try #require(URL(string: "myapp://settings"))
    #expect(parser.parse(DeepLinkRequest(url: unrelated)) == .noMatch)

    let invalid = try #require(URL(string: "myapp://detail/42/extra"))
    #expect(parser.parse(DeepLinkRequest(url: invalid)) == .invalid)
  }

  @Test
  func `Request for scheme-only URL has no route components`() throws {
    let url = try #require(URL(string: "myapp://"))
    #expect(DeepLinkRequest(url: url).routeComponents.isEmpty)
  }

  @Test
  func `Request route components ignore query parameters`() throws {
    let url = try #require(URL(string: "myapp://settings?tab=1"))
    #expect(DeepLinkRequest(url: url).routeComponents == ["settings"])
  }

  @Test
  func `Request route components ignore fragment`() throws {
    let url = try #require(URL(string: "myapp://settings#section"))
    #expect(DeepLinkRequest(url: url).routeComponents == ["settings"])
  }

  @Test
  func `Matching parser with empty components`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: [],
      destination: .root(.home),
    )

    let url = try #require(URL(string: "myapp://"))
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.root(.home)))
  }

  @Test
  func `Request route components ignore combined query and fragment`() throws {
    let url = try #require(URL(string: "myapp://item/42?a=1#top"))
    #expect(DeepLinkRequest(url: url).routeComponents == ["item", "42"])
  }

  @Test
  func `Request route components preserve percent-encoded characters`() throws {
    let spaceURL = try #require(URL(string: "myapp://item/hello%20world"))
    let slashURL = try #require(URL(string: "myapp://item/a%2Fb"))

    #expect(DeepLinkRequest(url: spaceURL).routeComponents == ["item", "hello%20world"])
    #expect(DeepLinkRequest(url: slashURL).routeComponents == ["item", "a%2Fb"])
    #expect(DeepLinkRequest(url: slashURL).isStructurallyValid)
  }

  @Test
  func `Matching parser rejects URL with fewer components than expected`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: ["settings", "detail"],
      destination: .root(.settings),
    )

    let url = try #require(URL(string: "myapp://settings"))
    #expect(parser.parse(DeepLinkRequest(url: url)) == .noMatch)
  }

  @Test
  func `Matching parser rejects URL with more components than expected`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: ["settings"],
      destination: .root(.settings),
    )

    let url = try #require(URL(string: "myapp://settings/extra"))
    #expect(parser.parse(DeepLinkRequest(url: url)) == .noMatch)
  }

  @Test
  func `Matching parser is case-sensitive for path components`() throws {
    let parser = DeepLinkParser<TestScene>.matching(
      components: ["settings"],
      destination: .root(.settings),
    )

    let lowercase = try #require(URL(string: "myapp://settings"))
    #expect(
      parser.parse(DeepLinkRequest(url: lowercase)) == .destination(.root(.settings))
    )

    let uppercase = try #require(URL(string: "myapp://Settings"))
    #expect(
      parser.parse(DeepLinkRequest(url: uppercase)) == .noMatch,
      "Path matching should be case-sensitive",
    )
  }
}
