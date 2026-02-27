//
//  RouterEdgeCaseTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import VISOR
import Testing

// MARK: - Router Edge Case Tests

@Suite("Router Edge Cases")
@MainActor
struct RouterEdgeCaseTests {

  @Test
  func `popToRoot on empty path is safe no-op`() {
    let router = Router<TestScene>(level: 0)
    router.popToRoot()

    #expect(router.navigationPath.isEmpty)
  }

  @Test
  func `dismissSheet when none presented is safe no-op`() {
    let router = Router<TestScene>(level: 0)
    router.dismissSheet()

    #expect(router.presentingSheet == nil)
  }

  @Test
  func `dismissFullScreen when none presented is safe no-op`() {
    let router = Router<TestScene>(level: 0)
    router.dismissFullScreen()

    #expect(router.presentingFullScreen == nil)
  }

  @Test
  func `presenting sheet overwrites existing sheet`() {
    let router = Router<TestScene>(level: 0)
    router.present(sheet: .preferences)
    router.present(sheet: .preferences)

    #expect(router.presentingSheet == .preferences)
  }

  @Test
  func `presenting fullScreen overwrites existing fullScreen`() {
    let router = Router<TestScene>(level: 0)
    router.present(fullScreen: .onboarding)
    router.present(fullScreen: .onboarding)

    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `weak parent does not crash when parent deallocated`() {
    var parent: Router<TestScene>? = Router<TestScene>(level: 0)
    let child = Router<TestScene>(level: 1, parent: parent)
    parent = nil

    child.select(tab: .settings)
    #expect(child.selectedTab == .settings)
  }

  @Test
  func `deep hierarchy grandchild tab propagates to root`() {
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
  func `multiple children for different tabs are independent`() {
    let root = Router<TestScene>(level: 0)
    let homeChild = root.childRouter(for: .home)
    let settingsChild = root.childRouter(for: .settings)

    homeChild.push(.detail(id: "home-1"))
    #expect(homeChild.navigationPath == [.detail(id: "home-1")])
    #expect(settingsChild.navigationPath.isEmpty)
  }

  @Test
  func `rapid push then popToRoot leaves empty path`() {
    let router = Router<TestScene>(level: 0)
    for i in 0..<10 {
      router.push(.detail(id: "\(i)"))
    }
    #expect(router.navigationPath.count == 10)

    router.popToRoot()
    #expect(router.navigationPath.isEmpty)
  }
}
