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
  url: URL)
  -> DeepLinkParseResult<TestScene>
{
  parser.parse(DeepLinkRequest(url: url))
}

// MARK: - DeepLinkParser Tests

@Suite("DeepLinkParser")
@MainActor
struct DeepLinkParserTests {

  // MARK: - DeepLinkRequest

  @Test
  func `Request strips scheme and splits path`() {
    let url = URL(string: "myapp://valentine/accept")!
    let request = DeepLinkRequest(url: url)

    #expect(request.components == ["valentine", "accept"])
    #expect(request.isStructurallyValid)
  }

  @Test
  func `Request handles triple-slash`() {
    let url = URL(string: "myapp:///settings")!
    let request = DeepLinkRequest(url: url)

    #expect(request.components == ["settings"])
    #expect(request.isStructurallyValid)
  }

  @Test
  func `Request handles single component`() {
    let url = URL(string: "myapp://home")!
    #expect(DeepLinkRequest(url: url).components == ["home"])
  }

  @Test
  func `Request handles trailing slash`() {
    let url = URL(string: "myapp://settings/")!
    let request = DeepLinkRequest(url: url)

    #expect(request.components == ["settings"])
    #expect(request.isStructurallyValid)
  }

  @Test
  func `Request preserves an empty interior segment as invalid structure`() {
    let url = URL(string: "myapp://item//42")!
    let request = DeepLinkRequest(url: url)

    #expect(request.components == ["item", "", "42"])
    #expect(!request.isStructurallyValid)
  }

  @Test
  func `Request rejects more than one trailing separator`() {
    let url = URL(string: "myapp://item//")!
    let request = DeepLinkRequest(url: url)

    #expect(request.components == ["item", ""])
    #expect(!request.isStructurallyValid)
  }

  @Test
  func `Request handles host with multi-segment path`() {
    let url = URL(string: "myapp://item/42/detail")!
    #expect(DeepLinkRequest(url: url).components == ["item", "42", "detail"])
  }

  // MARK: - equal parser

  @Test
  func `equal parser matches exact components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .root(.settings))

    let url = URL(string: "myapp://settings")!
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.root(.settings)))
  }

  @Test
  func `Parser can be called from a nonisolated context`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .root(.settings))

    let result = parseDeepLink(parser, url: URL(string: "myapp://settings")!)

    #expect(result == .destination(.root(.settings)))
  }

  @Test
  func `equal parser rejects non-matching components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .root(.settings))

    let url = URL(string: "myapp://home")!
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .noMatch)
  }

  @Test
  func `equal parser matches multi-component path`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["valentine", "accept"],
      destination: .fullScreen(.onboarding))

    let url = URL(string: "myapp://valentine/accept")!
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.fullScreen(.onboarding)))
  }

  // MARK: - Custom parser

  @Test
  func `Custom parser extracts dynamic values`() {
    let parser = DeepLinkParser<TestScene> { request in
      let parts = request.components
      guard parts.first == "detail" else { return .noMatch }
      guard parts.count == 2 else { return .invalid }
      return .destination(.push(.detail(id: parts[1])))
    }

    let url = URL(string: "myapp://detail/42")!
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.push(.detail(id: "42"))))
  }

  @Test
  func `Custom parser distinguishes unrelated and invalid routes`() {
    let parser = DeepLinkParser<TestScene> { request in
      let parts = request.components
      guard parts.first == "detail" else { return .noMatch }
      guard parts.count == 2 else { return .invalid }
      return .destination(.push(.detail(id: parts[1])))
    }

    let unrelated = URL(string: "myapp://settings")!
    #expect(parser.parse(DeepLinkRequest(url: unrelated)) == .noMatch)

    let invalid = URL(string: "myapp://detail/42/extra")!
    #expect(parser.parse(DeepLinkRequest(url: invalid)) == .invalid)
  }

  // MARK: - Scheme-only URL

  @Test
  func `Request for scheme-only URL has no components`() {
    let url = URL(string: "myapp://")!
    #expect(DeepLinkRequest(url: url).components.isEmpty)
  }

  // MARK: - Query Parameters Ignored

  @Test
  func `Request components ignore query parameters`() {
    let url = URL(string: "myapp://settings?tab=1")!
    #expect(DeepLinkRequest(url: url).components == ["settings"])
  }

  // MARK: - Fragment Ignored

  @Test
  func `Request components ignore fragment`() {
    let url = URL(string: "myapp://settings#section")!
    #expect(DeepLinkRequest(url: url).components == ["settings"])
  }

  // MARK: - Equal Parser with Empty Components

  @Test
  func `equal parser with empty components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: [],
      destination: .root(.home))

    let url = URL(string: "myapp://")!
    let result = parser.parse(DeepLinkRequest(url: url))
    #expect(result == .destination(.root(.home)))
  }

  // MARK: - Query and Fragment Combined

  @Test
  func `Request components ignore combined query and fragment`() {
    let url = URL(string: "myapp://item/42?a=1#top")!
    #expect(DeepLinkRequest(url: url).components == ["item", "42"])
  }

  // MARK: - Percent-Encoded Components

  @Test
  func `Request components preserve percent-encoded characters`() {
    let spaceURL = URL(string: "myapp://item/hello%20world")!
    let slashURL = URL(string: "myapp://item/a%2Fb")!

    #expect(DeepLinkRequest(url: spaceURL).components == ["item", "hello%20world"])
    #expect(DeepLinkRequest(url: slashURL).components == ["item", "a%2Fb"])
    #expect(DeepLinkRequest(url: slashURL).isStructurallyValid)
  }

  // MARK: - Case-Sensitive Path Components

  // MARK: - Component Count Mismatches

  @Test
  func `equal parser rejects URL with fewer components than expected`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings", "detail"],
      destination: .root(.settings))

    let url = URL(string: "myapp://settings")!
    #expect(parser.parse(DeepLinkRequest(url: url)) == .noMatch)
  }

  @Test
  func `equal parser rejects URL with more components than expected`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .root(.settings))

    let url = URL(string: "myapp://settings/extra")!
    #expect(parser.parse(DeepLinkRequest(url: url)) == .noMatch)
  }

  @Test
  func `equal parser is case-sensitive for path components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .root(.settings))

    let lowercase = URL(string: "myapp://settings")!
    #expect(
      parser.parse(DeepLinkRequest(url: lowercase)) == .destination(.root(.settings)))

    let uppercase = URL(string: "myapp://Settings")!
    #expect(
      parser.parse(DeepLinkRequest(url: uppercase)) == .noMatch,
      "Path matching should be case-sensitive")
  }
}
