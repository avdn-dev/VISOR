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
  func `select root falls back to self when parent deallocated`() {
    var parent: Router<TestScene>? = Router<TestScene>()
    let child = Router<TestScene>(level: 1, parent: parent)
    parent = nil

    child.select(root: .settings)
    #expect(child.selectedRoot == .settings)
  }

  @Test
  func `Deep hierarchy grandchild root selection propagates to root`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    let grandchild = child.childRouter(for: .home)

    grandchild.select(root: .settings)
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `activate then deactivate roundtrip`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.activate()
    #expect(child.isActive)
    #expect(!root.isActive)

    child.deactivate()
    #expect(!child.isActive)

    root.activate()
    #expect(root.isActive)
  }

  @Test
  func `Multiple children for different roots are independent`() {
    let root = Router<TestScene>()
    let homeChild = root.childRouter(for: .home)
    let settingsChild = root.childRouter(for: .settings)

    homeChild.push(.detail(id: "home-1"))
    #expect(homeChild.navigationPath == [.detail(id: "home-1")])
    #expect(settingsChild.navigationPath.isEmpty)
  }

  @Test
  func `Rapid push then popToRoot leaves empty path`() {
    let router = Router<TestScene>()
    router.activate()
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
    let router = Router<TestScene>()
    router.activate()
    router.present(sheet: .preferences)
    router.present(sheet: .profile)
    #expect(router.presentingSheet == .profile)
  }

  // MARK: - Different fullScreen overwrites previous

  @Test
  func `Presenting different fullScreen overwrites previous`() {
    let router = Router<TestScene>()
    router.activate()
    router.present(fullScreen: .onboarding)
    router.present(fullScreen: .tutorial)
    #expect(router.presentingFullScreen == .tutorial)
  }

  // MARK: - Grandchild activate

  @Test
  func `Grandchild activate deactivates direct parent`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    let grandchild = child.childRouter(for: .home)

    child.activate()
    grandchild.activate()
    #expect(grandchild.isActive)
    #expect(!child.isActive)
    #expect(!root.isActive)
  }

  // MARK: - deactivate on root then activate restores

  @Test
  func `deactivate on root then activate restores`() {
    let root = Router<TestScene>()
    root.activate()
    #expect(root.isActive)

    root.deactivate()
    #expect(!root.isActive)

    root.activate()
    #expect(root.isActive)
  }

  // MARK: - Child state preserved across root switches

  @Test
  func `childRouter state preserved across root switches`() {
    let root = Router<TestScene>()
    let homeChild = root.childRouter(for: .home)
    let settingsChild = root.childRouter(for: .settings)

    homeChild.push(.detail(id: "home-1"))
    settingsChild.push(.detail(id: "settings-1"))

    root.select(root: .settings)
    root.select(root: .home)

    #expect(homeChild.navigationPath == [.detail(id: "home-1")])
    #expect(settingsChild.navigationPath == [.detail(id: "settings-1")])
  }

  // MARK: - Tree-wide deep-link configuration

  @Test
  func `Existing root and modal routers receive later configuration`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    let modal = child.childRouter()

    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings)),
    ])

    let url = URL(string: "test://settings")!
    child.activate()
    #expect(child.openDeepLink(url) == .handled(.root(.settings)))
    modal.activate()
    #expect(modal.openDeepLink(url) == .handled(.root(.settings)))
  }

  @Test
  func `Child created after configureDeepLinks inherits configuration`() {
    let root = Router<TestScene>()
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings)),
    ])

    // Child created after configuration should read the shared tree context.
    let child = root.childRouter(for: .settings)
    child.activate()

    let result = child.openDeepLink(URL(string: "test://settings")!)
    #expect(result == .handled(.root(.settings)))
  }

  // MARK: - Exclusive modal presentation

  @Test
  func `Full-screen presentation replaces a sheet on the same Router`() {
    let router = Router<TestScene>()
    router.activate()

    router.present(sheet: .preferences)
    router.present(fullScreen: .onboarding)

    #expect(router.presentingSheet == nil)
    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `Sheet presentation replaces full screen on the same Router`() {
    let router = Router<TestScene>()
    router.activate()

    router.present(fullScreen: .onboarding)
    router.present(sheet: .preferences)

    #expect(router.presentingSheet == .preferences)
    #expect(router.presentingFullScreen == nil)
  }

  @Test
  func `Stale sheet dismissal does not clear its full-screen replacement`() {
    let router = Router<TestScene>()
    router.activate()

    router.present(sheet: .preferences)
    router.present(fullScreen: .onboarding)
    router.sheetPresentation = nil

    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `Same presentation ID updates payload and preserves modal child`() throws {
    let router = Router<IdentifiedPresentationTestScene>()
    router.activate()

    router.present(sheet: .editor(documentID: "document", revision: 1))
    let firstChild = try #require(router.sheetPresentation?.router)

    router.present(sheet: .editor(documentID: "document", revision: 2))

    #expect(
      router.presentingSheet == .editor(documentID: "document", revision: 2))
    #expect(router.sheetPresentation?.router === firstChild)
    #expect(router.sheetPresentation?.id == "document")
  }

  @Test
  func `Different presentation ID creates a fresh modal child`() throws {
    let router = Router<IdentifiedPresentationTestScene>()
    router.activate()

    router.present(sheet: .editor(documentID: "first", revision: 1))
    let firstChild = try #require(router.sheetPresentation?.router)

    router.present(sheet: .editor(documentID: "second", revision: 1))

    let secondChild = try #require(router.sheetPresentation?.router)
    #expect(secondChild !== firstChild)
  }

  @Test
  func `Changing presentation style creates a fresh modal child`() throws {
    let router = Router<IdentifiedPresentationTestScene>()
    router.activate()

    router.present(sheet: .editor(documentID: "document", revision: 1))
    let sheetChild = try #require(router.sheetPresentation?.router)

    router.present(fullScreen: .reader(documentID: "document", revision: 1))

    let fullScreenChild = try #require(router.fullScreenPresentation?.router)
    #expect(fullScreenChild !== sheetChild)
  }

  @Test
  func `Modal child can present a nested modal`() throws {
    let root = Router<TestScene>()
    root.activate()
    root.present(sheet: .preferences)
    let modal = try #require(root.sheetPresentation?.router)
    modal.activate()

    modal.present(fullScreen: .onboarding)

    #expect(root.presentingSheet == .preferences)
    #expect(modal.presentingFullScreen == .onboarding)
  }

  @Test
  func `Push permits repeated equal destinations`() {
    let router = Router<TestScene>()
    router.activate()

    router.push(.detail(id: "same"))
    router.push(.detail(id: "same"))

    #expect(router.navigationPath == [.detail(id: "same"), .detail(id: "same")])
  }

  // MARK: - popToRoot preserves presented modals

  @Test
  func `popToRoot preserves presented sheet`() {
    let router = Router<TestScene>()
    router.activate()
    router.push(.detail(id: "1"))
    router.present(sheet: .preferences)

    router.popToRoot()
    #expect(router.navigationPath.isEmpty)
    #expect(router.presentingSheet == .preferences)
  }

  // MARK: - navigate(to:) covers all destination types

  @Test
  func `navigate(to: .push) appends to navigation path`() {
    let router = Router<TestScene>()
    router.activate()
    router.navigate(to: .push(.detail(id: "nav")))
    #expect(router.navigationPath == [.detail(id: "nav")])
  }

  @Test
  func `navigate(to: .sheet) presents sheet`() {
    let router = Router<TestScene>()
    router.activate()
    router.navigate(to: .sheet(.preferences))
    #expect(router.presentingSheet == .preferences)
  }

  @Test
  func `navigate(to: .fullScreen) presents fullScreen`() {
    let router = Router<TestScene>()
    router.activate()
    router.navigate(to: .fullScreen(.onboarding))
    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `navigate(to: .root) on child propagates to root`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    child.activate()

    child.navigate(to: .root(.settings))
    #expect(root.selectedRoot == .settings)
  }

  // MARK: - Multiple configureDeepLinks calls overwrite configuration

  @Test
  func `Multiple configureDeepLinks calls overwrite configuration`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    let modal = child.childRouter()

    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .root(.home)),
    ])

    // Second call overwrites
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings)),
    ])

    let homeURL = URL(string: "test://home")!
    let settingsURL = URL(string: "test://settings")!
    for router in [root, child, modal] {
      router.activate()
      #expect(
        router.openDeepLink(homeURL) == .unmatched,
        "First parser should be overwritten for every existing Router")
      #expect(router.openDeepLink(settingsURL) == .handled(.root(.settings)))
    }
  }

  // MARK: - selectAndPush from deep hierarchy

  // MARK: - No-op safety

  @Test
  func `popToRoot on empty path is no-op`() {
    let router = Router<TestScene>()
    router.activate()
    router.popToRoot()
    #expect(router.navigationPath.isEmpty)
  }

  @Test
  func `dismissSheet when no sheet presented is no-op`() {
    let router = Router<TestScene>()
    router.activate()
    router.dismissSheet()
    #expect(router.presentingSheet == nil)
  }

  @Test
  func `dismissFullScreen when no fullScreen presented is no-op`() {
    let router = Router<TestScene>()
    router.activate()
    router.dismissFullScreen()
    #expect(router.presentingFullScreen == nil)
  }

  // MARK: - selectAndPush from deep hierarchy

  @Test
  func `selectAndPush from child targets the root destination Router`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.selectAndPush(root: .settings, destination: .detail(id: "deep"))

    let settings = root.childRouter(for: .settings)
    #expect(settings.navigationPath == [.detail(id: "deep")])
    #expect(root.selectedRoot == .settings)
  }
}
