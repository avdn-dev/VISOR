//
//  DeepLinkParserTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 26/2/2026.
//

import VISOR
import Testing
import Foundation

// MARK: - DeepLinkParser Tests

@Suite("DeepLinkParser")
@MainActor
struct DeepLinkParserTests {

  // MARK: - URL.deepLinkComponents

  @Test
  func `deepLinkComponents strips scheme and splits path`() {
    let url = URL(string: "myapp://valentine/accept")!
    #expect(url.deepLinkComponents == ["valentine", "accept"])
  }

  @Test
  func `deepLinkComponents handles triple-slash`() {
    let url = URL(string: "myapp:///settings")!
    #expect(url.deepLinkComponents == ["settings"])
  }

  @Test
  func `deepLinkComponents handles single component`() {
    let url = URL(string: "myapp://home")!
    #expect(url.deepLinkComponents == ["home"])
  }

  @Test
  func `deepLinkComponents handles trailing slash`() {
    let url = URL(string: "myapp://settings/")!
    #expect(url.deepLinkComponents == ["settings"])
  }

  @Test
  func `deepLinkComponents handles host with multi-segment path`() {
    let url = URL(string: "myapp://item/42/detail")!
    #expect(url.deepLinkComponents == ["item", "42", "detail"])
  }

  // MARK: - equal parser

  @Test
  func `equal parser matches exact components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .tab(.settings))

    let url = URL(string: "myapp://settings")!
    let result = parser.parse(url)
    #expect(result == .tab(.settings))
  }

  @Test
  func `equal parser rejects non-matching components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .tab(.settings))

    let url = URL(string: "myapp://home")!
    let result = parser.parse(url)
    #expect(result == nil)
  }

  @Test
  func `equal parser matches multi-component path`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["valentine", "accept"],
      destination: .fullScreen(.onboarding))

    let url = URL(string: "myapp://valentine/accept")!
    let result = parser.parse(url)
    #expect(result == .fullScreen(.onboarding))
  }

  // MARK: - Custom parser

  @Test
  func `Custom parser extracts dynamic values`() {
    let parser = DeepLinkParser<TestScene> { url in
      let parts = url.deepLinkComponents
      guard parts.first == "detail", parts.count == 2 else { return nil }
      return .push(.detail(id: parts[1]))
    }

    let url = URL(string: "myapp://detail/42")!
    let result = parser.parse(url)
    #expect(result == .push(.detail(id: "42")))
  }

  @Test
  func `Custom parser returns nil for non-matching URL`() {
    let parser = DeepLinkParser<TestScene> { url in
      let parts = url.deepLinkComponents
      guard parts.first == "detail", parts.count == 2 else { return nil }
      return .push(.detail(id: parts[1]))
    }

    let url = URL(string: "myapp://settings")!
    let result = parser.parse(url)
    #expect(result == nil)
  }

  // MARK: - Scheme-only URL

  @Test
  func `deepLinkComponents for scheme-only URL`() {
    let url = URL(string: "myapp://")!
    #expect(url.deepLinkComponents.isEmpty)
  }

  // MARK: - Query Parameters Ignored

  @Test
  func `deepLinkComponents ignores query parameters`() {
    let url = URL(string: "myapp://settings?tab=1")!
    #expect(url.deepLinkComponents == ["settings"])
  }

  // MARK: - Fragment Ignored

  @Test
  func `deepLinkComponents ignores fragment`() {
    let url = URL(string: "myapp://settings#section")!
    #expect(url.deepLinkComponents == ["settings"])
  }

  // MARK: - Equal Parser with Empty Components

  @Test
  func `equal parser with empty components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: [],
      destination: .tab(.home))

    let url = URL(string: "myapp://")!
    let result = parser.parse(url)
    #expect(result == .tab(.home))
  }

  // MARK: - Query and Fragment Combined

  @Test
  func `deepLinkComponents with query and fragment combined`() {
    let url = URL(string: "myapp://item/42?a=1#top")!
    #expect(url.deepLinkComponents == ["item", "42"])
  }

  // MARK: - Percent-Encoded Components

  @Test
  func `deepLinkComponents preserves percent-encoded characters`() {
    let url = URL(string: "myapp://item/hello%20world")!
    // Custom scheme URLs preserve percent-encoding in path components
    #expect(url.deepLinkComponents == ["item", "hello%20world"])
  }

  // MARK: - Case-Sensitive Path Components

  @Test
  func `equal parser is case-sensitive for path components`() {
    let parser = DeepLinkParser<TestScene>.equal(
      to: ["settings"],
      destination: .tab(.settings))

    let lowercase = URL(string: "myapp://settings")!
    #expect(parser.parse(lowercase) == .tab(.settings))

    let uppercase = URL(string: "myapp://Settings")!
    #expect(parser.parse(uppercase) == nil, "Path matching should be case-sensitive")
  }
}
