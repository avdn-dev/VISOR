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
  func `custom parser extracts dynamic values`() {
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
  func `custom parser returns nil for non-matching URL`() {
    let parser = DeepLinkParser<TestScene> { url in
      let parts = url.deepLinkComponents
      guard parts.first == "detail", parts.count == 2 else { return nil }
      return .push(.detail(id: parts[1]))
    }

    let url = URL(string: "myapp://settings")!
    let result = parser.parse(url)
    #expect(result == nil)
  }
}
