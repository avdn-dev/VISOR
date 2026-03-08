//
//  RouterEdgeCaseTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import VISOR
import Testing
import Foundation

// MARK: - Router Edge Case Tests

@Suite("Router Edge Cases")
@MainActor
struct RouterEdgeCaseTests {

  @Test
  func `weak parent does not crash when parent deallocated`() {
    var parent: Router<TestScene>? = Router<TestScene>(level: 0)
    let child = Router<TestScene>(level: 1, parent: parent)
    parent = nil

    child.select(tab: .settings)
    #expect(child.selectedTab == .settings)
  }

  @Test
  func `Deep hierarchy grandchild tab propagates to root`() {
    let root = Router<TestScene>(level: 0)
    let child = root.childRouter(for: .home)
    let grandchild = child.childRouter(for: .home)

    grandchild.select(tab: .settings)
    #expect(root.selectedTab == .settings)
  }

  @Test
  func `setActive then resignActive roundtrip`() {
    let root = Router<TestScene>(level: 0)
    let child = root.childRouter(for: .home)

    child.setActive()
    #expect(child.isActive)
    #expect(!root.isActive)

    child.resignActive()
    #expect(!child.isActive)

    root.setActive()
    #expect(root.isActive)
  }

  @Test
  func `Multiple children for different tabs are independent`() {
    let root = Router<TestScene>(level: 0)
    let homeChild = root.childRouter(for: .home)
    let settingsChild = root.childRouter(for: .settings)

    homeChild.push(.detail(id: "home-1"))
    #expect(homeChild.navigationPath == [.detail(id: "home-1")])
    #expect(settingsChild.navigationPath.isEmpty)
  }

  @Test
  func `Rapid push then popToRoot leaves empty path`() {
    let router = Router<TestScene>(level: 0)
    for i in 0..<10 {
      router.push(.detail(id: "\(i)"))
    }
    #expect(router.navigationPath.count == 10)

    router.popToRoot()
    #expect(router.navigationPath.isEmpty)
  }

  // MARK: - Different sheet overwrites previous

  @Test
  func `Presenting different sheet overwrites previous`() {
    let router = Router<TestScene>(level: 0)
    router.present(sheet: .preferences)
    router.present(sheet: .profile)
    #expect(router.presentingSheet == .profile)
  }

  // MARK: - Different fullScreen overwrites previous

  @Test
  func `Presenting different fullScreen overwrites previous`() {
    let router = Router<TestScene>(level: 0)
    router.present(fullScreen: .onboarding)
    router.present(fullScreen: .tutorial)
    #expect(router.presentingFullScreen == .tutorial)
  }

  // MARK: - Grandchild setActive

  @Test
  func `Grandchild setActive deactivates direct parent`() {
    let root = Router<TestScene>(level: 0)
    let child = root.childRouter(for: .home)
    let grandchild = child.childRouter(for: .home)

    // setActive only resignActive on direct parent, not grandparent
    child.setActive()
    grandchild.setActive()
    #expect(grandchild.isActive)
    #expect(!child.isActive)
    // root was already deactivated when child.setActive() was called
    #expect(!root.isActive)
  }

  // MARK: - resignActive on root then setActive restores

  @Test
  func `resignActive on root then setActive restores`() {
    let root = Router<TestScene>(level: 0)
    #expect(root.isActive)

    root.resignActive()
    #expect(!root.isActive)

    root.setActive()
    #expect(root.isActive)
  }

  // MARK: - Child state preserved across tab switches

  @Test
  func `childRouter state preserved across tab switches`() {
    let root = Router<TestScene>(level: 0)
    let homeChild = root.childRouter(for: .home)
    let settingsChild = root.childRouter(for: .settings)

    homeChild.push(.detail(id: "home-1"))
    settingsChild.push(.detail(id: "settings-1"))

    root.select(tab: .settings)
    root.select(tab: .home)

    #expect(homeChild.navigationPath == [.detail(id: "home-1")])
    #expect(settingsChild.navigationPath == [.detail(id: "settings-1")])
  }

  // MARK: - deepLinkHandler set after child creation

  @Test
  func `Child created before configureDeepLinks does not get handler`() {
    let root = Router<TestScene>(level: 0)
    let child = root.childRouter(for: .home)

    // Configure AFTER child creation
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    // Child was created before handler was set — should NOT have the handler
    #expect(child.deepLinkHandler == nil)
  }

  @Test
  func `Child created after configureDeepLinks inherits handler`() {
    let root = Router<TestScene>(level: 0)
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    // Child created AFTER handler was set — should inherit it
    let child = root.childRouter(for: .settings)
    #expect(child.deepLinkHandler != nil)

    let result = child.deepLinkHandler?(URL(string: "test://settings")!)
    #expect(result == .tab(.settings))
  }

  // MARK: - Simultaneous sheet and fullScreen

  @Test
  func `Simultaneous sheet and fullScreen are independently managed`() {
    let router = Router<TestScene>(level: 0)

    router.present(sheet: .preferences)
    router.present(fullScreen: .onboarding)

    #expect(router.presentingSheet == .preferences)
    #expect(router.presentingFullScreen == .onboarding)

    router.dismissSheet()
    #expect(router.presentingSheet == nil)
    #expect(router.presentingFullScreen == .onboarding)

    router.dismissFullScreen()
    #expect(router.presentingFullScreen == nil)
  }

  // MARK: - popToRoot preserves presented modals

  @Test
  func `popToRoot preserves presented sheet`() {
    let router = Router<TestScene>(level: 0)
    router.push(.detail(id: "1"))
    router.present(sheet: .preferences)

    router.popToRoot()
    #expect(router.navigationPath.isEmpty)
    #expect(router.presentingSheet == .preferences)
  }

  // MARK: - navigate(to:) covers all destination types

  @Test
  func `navigate(to: .push) appends to navigation path`() {
    let router = Router<TestScene>(level: 0)
    router.navigate(to: .push(.detail(id: "nav")))
    #expect(router.navigationPath == [.detail(id: "nav")])
  }

  @Test
  func `navigate(to: .sheet) presents sheet`() {
    let router = Router<TestScene>(level: 0)
    router.navigate(to: .sheet(.preferences))
    #expect(router.presentingSheet == .preferences)
  }

  @Test
  func `navigate(to: .fullScreen) presents fullScreen`() {
    let router = Router<TestScene>(level: 0)
    router.navigate(to: .fullScreen(.onboarding))
    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `navigate(to: .tab) on child propagates to root`() {
    let root = Router<TestScene>(level: 0)
    let child = root.childRouter(for: .home)
    child.setActive()

    child.navigate(to: .tab(.settings))
    #expect(root.selectedTab == .settings)
  }

  // MARK: - Multiple configureDeepLinks calls overwrite handler

  @Test
  func `Multiple configureDeepLinks calls overwrite handler`() {
    let root = Router<TestScene>(level: 0)

    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .tab(.home)),
    ])

    // Second call overwrites
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .tab(.settings)),
    ])

    let homeResult = root.deepLinkHandler?(URL(string: "test://home")!)
    #expect(homeResult == nil, "First parser should be overwritten")

    let settingsResult = root.deepLinkHandler?(URL(string: "test://settings")!)
    #expect(settingsResult == .tab(.settings))
  }

  // MARK: - selectAndPush from deep hierarchy

  @Test
  func `selectAndPush from child creates grandchild push`() {
    let root = Router<TestScene>(level: 0)
    let child = root.childRouter(for: .home)

    child.selectAndPush(tab: .settings, destination: .detail(id: "deep"))

    let grandchild = child.childRouter(for: .settings)
    #expect(grandchild.navigationPath == [.detail(id: "deep")])
    #expect(root.selectedTab == .settings)
  }
}
