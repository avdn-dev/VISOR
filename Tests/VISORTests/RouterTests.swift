//
//  RouterTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import VISOR
import Testing
import Foundation
import SwiftUI

// MARK: - Router Tests

@Suite("Router")
@MainActor
struct RouterTests {

  @Test
  func `Root router becomes active when its container mounts`() {
    let router = Router<TestScene>()
    #expect(!router.isActive)

    router.activate()

    #expect(router.isActive)
  }

  @Test
  func `Child router creation sets level and tab`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    #expect(child.level == 1)
    #expect(child.tab == .home)
    #expect(child.parent === root)
  }

  @Test
  func `Child activate deactivates parent`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    root.activate()
    child.activate()
    #expect(child.isActive)
    #expect(!root.isActive)
  }

  @Test
  func `push appends to navigation path`() {
    let router = Router<TestScene>()
    router.activate()
    router.push(.detail(id: "1"))
    router.push(.nested)

    #expect(router.navigationPath.count == 2)
    #expect(router.navigationPath[0] == .detail(id: "1"))
    #expect(router.navigationPath[1] == .nested)
  }

  @Test
  func `present sheet sets presentingSheet`() {
    let router = Router<TestScene>()
    router.activate()
    router.present(sheet: .preferences)

    #expect(router.presentingSheet == .preferences)
  }

  @Test
  func `present fullScreen sets presentingFullScreen`() {
    let router = Router<TestScene>()
    router.activate()
    router.present(fullScreen: .onboarding)

    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `popToRoot clears navigation path`() {
    let router = Router<TestScene>()
    router.activate()
    router.push(.detail(id: "1"))
    router.push(.nested)
    router.popToRoot()

    #expect(router.navigationPath.isEmpty)
  }

  @Test
  func `dismissSheet clears presentingSheet`() {
    let router = Router<TestScene>()
    router.activate()
    router.present(sheet: .preferences)
    router.dismissSheet()

    #expect(router.presentingSheet == nil)
  }

  @Test
  func `dismissFullScreen clears presentingFullScreen`() {
    let router = Router<TestScene>()
    router.activate()
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

    #expect(modal.tab == nil)
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
    router.activate()

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
  func `Configuring deep links through a child updates the entire router tree`() {
    let root = Router<TestScene>()
    let home = root.childRouter(for: .home)
    let settings = root.childRouter(for: .settings)
    let modal = home.childRouter()

    home.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    let url = URL(string: "test://settings")!
    #expect(root.deepLinkHandler?(url) == .tab(.settings))
    #expect(settings.deepLinkHandler?(url) == .tab(.settings))
    #expect(modal.deepLinkHandler?(url) == .tab(.settings))
  }

  @Test
  func `Separate router trees retain independent deep-link configurations`() {
    let firstRoot = Router<TestScene>()
    let secondRoot = Router<TestScene>()
    firstRoot.configureDeepLinks(scheme: "first", parsers: [
      .equal(to: ["home"], destination: .tab(.home)),
    ])
    secondRoot.configureDeepLinks(scheme: "second", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    #expect(
      firstRoot.deepLinkHandler?(URL(string: "first://home")!) == .tab(.home))
    #expect(firstRoot.deepLinkHandler?(URL(string: "second://settings")!) == nil)
    #expect(
      secondRoot.deepLinkHandler?(URL(string: "second://settings")!) == .tab(.settings))
    #expect(secondRoot.deepLinkHandler?(URL(string: "first://home")!) == nil)
  }

  @Test
  func `Active router processes deep link URL end-to-end`() {
    let root = Router<TestScene>()
    root.activate()
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

  // MARK: - present delegation to selected tab

  @Test
  func `present fullScreen from root with selectedTab delegates to tab child`() {
    let root = Router<TestScene>()
    root.selectedTab = .home
    let child = root.childRouter(for: .home)
    child.activate()

    root.present(fullScreen: .tutorial)

    // Root should NOT hold the presentation — tab child does.
    #expect(root.presentingFullScreen == nil)
    #expect(child.presentingFullScreen == .tutorial)
  }

  @Test
  func `present sheet from root with selectedTab delegates to tab child`() {
    let root = Router<TestScene>()
    root.selectedTab = .settings
    let child = root.childRouter(for: .settings)
    child.activate()

    root.present(sheet: .preferences)

    #expect(root.presentingSheet == nil)
    #expect(child.presentingSheet == .preferences)
  }

  @Test
  func `present fullScreen from child without tab presents on self`() {
    let root = Router<TestScene>()
    let modal = root.childRouter()

    modal.present(fullScreen: .onboarding)

    #expect(modal.presentingFullScreen == .onboarding)
  }

  // MARK: - dismiss walking up parent chain

  @Test
  func `dismissFullScreen walks up from deep child to clear presentation`() {
    let root = Router<TestScene>()
    root.selectedTab = .home
    let tabChild = root.childRouter(for: .home)
    tabChild.present(fullScreen: .tutorial)
    let fullScreenChild = tabChild.childRouter()

    // fullScreenChild doesn't hold the presentation — tabChild does.
    fullScreenChild.dismissFullScreen()

    #expect(tabChild.presentingFullScreen == nil)
  }

  @Test
  func `dismissSheet walks up from deep child to clear presentation`() {
    let root = Router<TestScene>()
    root.selectedTab = .home
    let tabChild = root.childRouter(for: .home)
    tabChild.present(sheet: .profile)
    let sheetChild = tabChild.childRouter()

    sheetChild.dismissSheet()

    #expect(tabChild.presentingSheet == nil)
  }

  @Test
  func `dismissFullScreen is no-op when no ancestor holds presentation`() {
    let root = Router<TestScene>()
    root.activate()

    root.dismissFullScreen()

    #expect(root.presentingFullScreen == nil)
  }

  @Test
  func `navigate fullScreen from root delegates to selected tab child`() {
    let root = Router<TestScene>()
    root.selectedTab = .home
    let child = root.childRouter(for: .home)
    child.activate()

    root.navigate(to: .fullScreen(.tutorial))

    #expect(root.presentingFullScreen == nil)
    #expect(child.presentingFullScreen == .tutorial)
  }

  @Test
  func `navigate sheet from root delegates to selected tab child`() {
    let root = Router<TestScene>()
    root.selectedTab = .settings
    let child = root.childRouter(for: .settings)
    child.activate()

    root.navigate(to: .sheet(.profile))

    #expect(root.presentingSheet == nil)
    #expect(child.presentingSheet == .profile)
  }

  // MARK: - Active visible routing

  @Test
  func `Root actions are rejected until a navigation container mounts`() {
    let root = Router<TestScene>()

    root.push(.nested)
    root.present(sheet: .preferences)
    root.present(fullScreen: .onboarding)

    #expect(root.navigationPath.isEmpty)
    #expect(root.presentingSheet == nil)
    #expect(root.presentingFullScreen == nil)
  }

  @Test
  func `Root actions target the active modal leaf`() {
    let root = Router<TestScene>()
    let tab = root.childRouter(for: .home)
    let modal = tab.childRouter()
    tab.activate()
    modal.activate()

    root.push(.nested)
    root.present(sheet: .profile)

    #expect(root.navigationPath.isEmpty)
    #expect(tab.navigationPath.isEmpty)
    #expect(modal.navigationPath == [.nested])
    #expect(modal.presentingSheet == .profile)
  }

  @Test
  func `Modal disappearance restores its mounted parent`() {
    let root = Router<TestScene>()
    let tab = root.childRouter(for: .home)
    let modal = tab.childRouter()
    tab.activate()
    modal.activate()

    modal.deactivate()

    #expect(!modal.isActive)
    #expect(tab.isActive)

    root.push(.nested)
    #expect(tab.navigationPath == [.nested])
  }

  @Test
  func `Late disappearance cannot deactivate a newer active tab`() {
    let root = Router<TestScene>()
    let home = root.childRouter(for: .home)
    let settings = root.childRouter(for: .settings)
    home.activate()
    settings.activate()

    home.deactivate()

    #expect(!home.isActive)
    #expect(settings.isActive)

    root.push(.detail(id: "current"))
    #expect(settings.navigationPath == [.detail(id: "current")])
  }

  @Test
  func `Single-stack scene and root container require no tab destination`() {
    let root = Router<SingleStackTestScene>()

    let container = NavigationContainer(
      router: root,
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() }
    ) {
      EmptyView()
    }

    _ = container
    #expect(root.level == 0)
  }

}
