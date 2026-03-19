//
//  RouterTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import VISOR
import Testing
import Foundation

// MARK: - Router Tests

@Suite("Router")
@MainActor
struct RouterTests {

  @Test
  func `Root router is active by default`() {
    let router = Router<TestScene>()
    #expect(router.isActive)
  }

  @Test
  func `Child router creation sets level and tab`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    #expect(child.level == 1)
    #expect(child.identifierTab == .home)
    #expect(child.parent === root)
  }

  @Test
  func `Child activate deactivates parent`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.activate()
    #expect(child.isActive)
    #expect(!root.isActive)
  }

  @Test
  func `push appends to navigation path`() {
    let router = Router<TestScene>()
    router.push(.detail(id: "1"))
    router.push(.nested)

    #expect(router.navigationPath.count == 2)
    #expect(router.navigationPath[0] == .detail(id: "1"))
    #expect(router.navigationPath[1] == .nested)
  }

  @Test
  func `present sheet sets presentingSheet`() {
    let router = Router<TestScene>()
    router.present(sheet: .preferences)

    #expect(router.presentingSheet == .preferences)
  }

  @Test
  func `present fullScreen sets presentingFullScreen`() {
    let router = Router<TestScene>()
    router.present(fullScreen: .onboarding)

    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `popToRoot clears navigation path`() {
    let router = Router<TestScene>()
    router.push(.detail(id: "1"))
    router.push(.nested)
    router.popToRoot()

    #expect(router.navigationPath.isEmpty)
  }

  @Test
  func `dismissSheet clears presentingSheet`() {
    let router = Router<TestScene>()
    router.present(sheet: .preferences)
    router.dismissSheet()

    #expect(router.presentingSheet == nil)
  }

  @Test
  func `dismissFullScreen clears presentingFullScreen`() {
    let router = Router<TestScene>()
    router.present(fullScreen: .onboarding)
    router.dismissFullScreen()

    #expect(router.presentingFullScreen == nil)
  }

  @Test
  func `select tab on root sets selectedTab directly`() {
    let root = Router<TestScene>()
    root.select(tab: .settings)
    #expect(root.selectedTab == .settings)
  }

  @Test
  func `select tab from child propagates to root`() {
    let root = Router<TestScene>()
    root.selectedTab = .home
    let child = root.childRouter(for: .home)

    child.select(tab: .settings)
    #expect(root.selectedTab == .settings)
  }

  @Test
  func `Deep link on inactive router ignores all destination types`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    child.activate() // root becomes inactive

    root.deepLinkOpen(to: .push(.detail(id: "deep")))
    root.deepLinkOpen(to: .sheet(.preferences))
    root.deepLinkOpen(to: .fullScreen(.onboarding))
    root.deepLinkOpen(to: .tab(.settings))

    #expect(root.navigationPath.isEmpty)
    #expect(root.presentingSheet == nil)
    #expect(root.presentingFullScreen == nil)
    #expect(root.selectedTab == nil)
  }

  @Test
  func `Preview router factory`() {
    let router = Router<TestScene>.preview(tab: .settings)
    #expect(router.selectedTab == .settings)
    #expect(router.level == 0)
  }

  @Test
  func `Modal child router has no tab`() {
    let root = Router<TestScene>()
    let modal = root.childRouter()

    #expect(modal.identifierTab == nil)
    #expect(modal.level == 1)
    #expect(modal.parent === root)
  }

  // MARK: - selectAndPush

  @Test
  func `selectAndPush pushes to child router not self`() {
    let root = Router<TestScene>()
    root.selectAndPush(tab: .settings, destination: .detail(id: "42"))

    #expect(root.navigationPath.isEmpty)
    let child = root.childRouter(for: .settings)
    #expect(child.navigationPath == [.detail(id: "42")])
    #expect(root.selectedTab == .settings)
  }

  @Test
  func `selectAndPush from child propagates tab to root`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.selectAndPush(tab: .settings, destination: .nested)

    #expect(root.selectedTab == .settings)
  }

  // MARK: - childRouter caching

  @Test
  func `childRouter for tab returns cached instance`() {
    let root = Router<TestScene>()
    let first = root.childRouter(for: .home)
    let second = root.childRouter(for: .home)

    #expect(first === second)
  }

  @Test
  func `childRouter for modal returns new instance each call`() {
    let root = Router<TestScene>()
    let first = root.childRouter()
    let second = root.childRouter()

    #expect(first !== second)
  }

  // MARK: - Deep linking

  @Test
  func `Deep link on active root handles all destination types`() {
    let router = Router<TestScene>()

    router.deepLinkOpen(to: .push(.detail(id: "deep")))
    #expect(router.navigationPath == [.detail(id: "deep")])

    router.deepLinkOpen(to: .tab(.settings))
    #expect(router.selectedTab == .settings)

    router.deepLinkOpen(to: .sheet(.preferences))
    #expect(router.presentingSheet == .preferences)

    router.deepLinkOpen(to: .fullScreen(.onboarding))
    #expect(router.presentingFullScreen == .onboarding)
  }

  // MARK: - Init

  @Test
  func `init with parent sets child inactive`() {
    let root = Router<TestScene>()
    let child = Router<TestScene>(level: 1, parent: root)

    #expect(!child.isActive)
  }

  // MARK: - configureDeepLinks

  @Test
  func `configureDeepLinks sets handler that scheme-gates`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    // Correct scheme
    let match = root.deepLinkHandler?(URL(string: "test://settings")!)
    #expect(match == .tab(.settings))

    // Wrong scheme
    let noMatch = root.deepLinkHandler?(URL(string: "other://settings")!)
    #expect(noMatch == nil)
  }

  @Test
  func `configureDeepLinks tries parsers in order`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
      .equal(to: ["settings"], destination: .tab(.home)), // second parser for same path
    ])

    let result = root.deepLinkHandler?(URL(string: "test://settings")!)
    #expect(result == .tab(.settings)) // first parser wins
  }

  @Test
  func `deepLinkHandler propagates to tab children`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .tab(.home)),
    ])

    let child = root.childRouter(for: .home)
    #expect(child.deepLinkHandler != nil)

    let result = child.deepLinkHandler?(URL(string: "test://home")!)
    #expect(result == .tab(.home))
  }

  @Test
  func `deepLinkHandler propagates to modal children`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .tab(.home)),
    ])

    let modal = root.childRouter()
    #expect(modal.deepLinkHandler != nil)
  }

  @Test
  func `Active router processes deep link URL end-to-end`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    if let destination = root.deepLinkHandler?(URL(string: "test://settings")!) {
      root.deepLinkOpen(to: destination)
    }

    #expect(root.selectedTab == .settings)
  }

  // MARK: - Case-insensitive scheme

  @Test
  func `configureDeepLinks is case-insensitive for scheme`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    let result = root.deepLinkHandler?(URL(string: "TEST://settings")!)
    #expect(result == .tab(.settings))
  }

  // MARK: - Empty parsers

  @Test
  func `configureDeepLinks with empty parsers returns nil`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [])

    let result = root.deepLinkHandler?(URL(string: "test://settings")!)
    #expect(result == nil)
  }

  // MARK: - No parser matches

  @Test
  func `configureDeepLinks when no parser matches returns nil`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    let result = root.deepLinkHandler?(URL(string: "test://unknown")!)
    #expect(result == nil)
  }

  // MARK: - configureDeepLinks handler

  @Test
  func `configureDeepLinks sets handler`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .tab(.home)),
    ])

    let result = root.deepLinkHandler?(URL(string: "test://home")!)
    #expect(result == .tab(.home))
  }

  // MARK: - activate idempotent

  @Test
  func `activate is idempotent`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.activate()
    child.activate()
    #expect(child.isActive)
    #expect(!root.isActive)
  }

  // MARK: - selectAndPush preserves existing path

  @Test
  func `selectAndPush on child with existing items preserves path`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .settings)
    child.push(.nested)

    root.selectAndPush(tab: .settings, destination: .detail(id: "new"))
    #expect(child.navigationPath == [.nested, .detail(id: "new")])
    #expect(root.selectedTab == .settings)
  }

  // MARK: - selectAndPush then popToRoot on child

  @Test
  func `selectAndPush then popToRoot on child clears only child`() {
    let root = Router<TestScene>()
    root.selectAndPush(tab: .settings, destination: .detail(id: "1"))
    let child = root.childRouter(for: .settings)

    child.popToRoot()
    #expect(child.navigationPath.isEmpty)
    #expect(root.selectedTab == .settings)
  }

}
