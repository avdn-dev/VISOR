//
//  RouterTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import Foundation
import SwiftUI
import Testing
import VISOR
import VISORTesting

#if os(macOS)
@MainActor
private final class RouterInputProbe {

  // MARK: Internal

  private(set) var routerIDs = [ObjectIdentifier]()

  func record(_ routerID: ObjectIdentifier) {
    routerIDs.append(routerID)
    recorded.record()
  }

  func wait(for count: Int) async throws {
    try await recorded.wait(for: count)
  }

  // MARK: Private

  private let recorded = TestEventCounter()

}

@MainActor
private struct RouterInputReporter: View {
  let probe: RouterInputProbe

  var body: some View {
    Color.clear
      .onChange(of: ObjectIdentifier(router), initial: true) { _, routerID in
        probe.record(routerID)
      }
  }

  @Environment(Router<TestScene>.self) private var router

}
#endif

// MARK: - RouterTests

@Suite("Router")
@MainActor
struct RouterTests {

  @Test
  func `Root router becomes active when its host mounts`() {
    let router = Router<TestScene>()
    #expect(!router.isActive)

    router.activate()

    #expect(router.isActive)
  }

  @Test
  func `Child router creation sets level and root destination`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    #expect(child.level == 1)
    #expect(child.rootDestination == .home)
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
  func `Mounted ancestor cannot replace its active descendant`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.activate()
    root.activate()

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
  func `select root on root sets selectedRoot directly`() {
    let root = Router<TestScene>()
    root.select(root: .settings)
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `select root from child propagates to root`() {
    let root = Router<TestScene>()
    root.selectedRoot = .home
    let child = root.childRouter(for: .home)

    child.select(root: .settings)
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `Deep link without a mounted host reports inactive`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["detail"], destination: .push(.detail(id: "deep")))
    ])

    let outcome = root.openDeepLink(try #require(URL(string: "test://detail")))

    #expect(outcome == .inactive)
    #expect(root.navigationPath.isEmpty)
  }

  @Test
  func `Root navigation actions report rejection without a mounted host`() {
    let root = Router<TestScene>()

    #expect(!root.push(.nested))
    #expect(!root.present(sheet: .preferences))
    #expect(!root.present(fullScreen: .onboarding))
    #expect(!root.navigate(to: .push(.nested)))
    #expect(!root.popToRoot())
    #expect(!root.dismissSheet())
    #expect(!root.dismissFullScreen())

    #expect(root.navigate(to: .root(.settings)))
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `Dismissal reports whether a presentation was removed`() {
    let router = Router<TestScene>()
    router.activate()

    #expect(!router.dismissSheet())
    #expect(router.present(sheet: .preferences))
    #expect(router.dismissSheet())
    #expect(!router.dismissSheet())

    #expect(!router.dismissFullScreen())
    #expect(router.present(fullScreen: .onboarding))
    #expect(router.dismissFullScreen())
    #expect(!router.dismissFullScreen())
  }

  @Test
  func `Preview router factory`() {
    let router = Router<TestScene>.preview(root: .settings)
    #expect(router.selectedRoot == .settings)
    #expect(router.level == 0)
  }

  @Test
  func `Modal child router has no root destination`() {
    let root = Router<TestScene>()
    let modal = root.childRouter()

    #expect(modal.rootDestination == nil)
    #expect(modal.level == 1)
    #expect(modal.parent === root)
  }

  @Test
  func `selectAndPush pushes to child router not self`() {
    let root = Router<TestScene>()
    root.selectAndPush(root: .settings, destination: .detail(id: "42"))

    #expect(root.navigationPath.isEmpty)
    let child = root.childRouter(for: .settings)
    #expect(child.navigationPath == [.detail(id: "42")])
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `selectAndPush from child propagates root selection`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.selectAndPush(root: .settings, destination: .nested)

    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `Root destination set snapshots the declared finite value space`() {
    let roots = RouterRootDestinationSet<ManuallyEnumeratedTestRoot>()
    let singleStackRoots = RouterRootDestinationSet<NoRootDestination>()

    #expect(roots.values.count == 2)
    #expect(roots.contains(ManuallyEnumeratedTestRoot(rawValue: 0)))
    #expect(roots.contains(ManuallyEnumeratedTestRoot(rawValue: 1)))
    #expect(!roots.contains(ManuallyEnumeratedTestRoot(rawValue: 2)))
    #expect(singleStackRoots.values.isEmpty)
  }

  @Test
  func `childRouter for root destination returns cached instance`() {
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

  @Test
  func `Deep link on active root handles all destination types`() throws {
    let router = Router<TestScene>()
    try router.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["detail"], destination: .push(.detail(id: "deep"))),
      .equal(to: ["settings"], destination: .root(.settings)),
      .equal(to: ["preferences"], destination: .sheet(.preferences)),
      .equal(to: ["onboarding"], destination: .fullScreen(.onboarding)),
    ])
    router.activate()

    #expect(
      router.openDeepLink(try #require(URL(string: "test://detail")))
        == .handled(.push(.detail(id: "deep")))
    )
    #expect(router.navigationPath == [.detail(id: "deep")])

    #expect(
      router.openDeepLink(try #require(URL(string: "test://settings")))
        == .handled(.root(.settings))
    )
    #expect(router.selectedRoot == .settings)

    #expect(
      router.openDeepLink(try #require(URL(string: "test://preferences")))
        == .handled(.sheet(.preferences))
    )
    #expect(router.presentingSheet == .preferences)

    #expect(
      router.openDeepLink(try #require(URL(string: "test://onboarding")))
        == .handled(.fullScreen(.onboarding))
    )
    #expect(router.presentingFullScreen == .onboarding)
  }

  @Test
  func `Root deep link targets the active child once`() throws {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["detail"], destination: .push(.detail(id: "deep")))
    ])
    root.activate()
    child.activate()

    #expect(!root.receivesDeepLinks)
    #expect(child.receivesDeepLinks)

    let outcome = root.openDeepLink(try #require(URL(string: "test://detail")))

    #expect(outcome == .handled(.push(.detail(id: "deep"))))
    #expect(root.navigationPath.isEmpty)
    #expect(child.navigationPath == [.detail(id: "deep")])
  }

  @Test
  func `init with parent sets child inactive`() {
    let root = Router<TestScene>()
    let child = Router<TestScene>(level: 1, parent: root)

    #expect(!child.isActive)
  }

  @Test
  func `openDeepLink reports unconfigured and scheme mismatch outcomes`() throws {
    let root = Router<TestScene>()

    #expect(root.openDeepLink(try #require(URL(string: "test://settings"))) == .unconfigured)

    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])
    root.activate()

    #expect(
      root.openDeepLink(try #require(URL(string: "other://settings"))) == .schemeMismatch
    )
  }

  @Test
  func `configureDeepLinks tries parsers in order`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings)),
      .equal(to: ["settings"], destination: .root(.home)), // second parser for same path
    ])
    root.activate()

    let result = root.openDeepLink(try #require(URL(string: "test://settings")))
    #expect(result == .handled(.root(.settings))) // first parser wins
  }

  @Test
  func `Deep-link configuration propagates to root children`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .root(.home))
    ])

    let child = root.childRouter(for: .home)
    child.activate()

    let result = child.openDeepLink(try #require(URL(string: "test://home")))
    #expect(result == .handled(.root(.home)))
  }

  @Test
  func `Deep-link configuration propagates to modal children`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .root(.home))
    ])

    let modal = root.childRouter()
    modal.activate()

    let result = modal.openDeepLink(try #require(URL(string: "test://home")))
    #expect(result == .handled(.root(.home)))
  }

  @Test
  func `Configuring deep links through a child updates the entire router tree`() throws {
    let root = Router<TestScene>()
    let home = root.childRouter(for: .home)
    let settings = root.childRouter(for: .settings)
    let modal = home.childRouter()

    try home.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])

    let url = try #require(URL(string: "test://settings"))
    home.activate()
    #expect(root.openDeepLink(url) == .handled(.root(.settings)))
    settings.activate()
    #expect(settings.openDeepLink(url) == .handled(.root(.settings)))
    modal.activate()
    #expect(modal.openDeepLink(url) == .handled(.root(.settings)))
  }

  @Test
  func `Separate router trees retain independent deep-link configurations`() throws {
    let firstRoot = Router<TestScene>()
    let secondRoot = Router<TestScene>()
    try firstRoot.configureDeepLinks(scheme: "first", parsers: [
      .equal(to: ["home"], destination: .root(.home))
    ])
    try secondRoot.configureDeepLinks(scheme: "second", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])
    firstRoot.activate()
    secondRoot.activate()

    #expect(
      firstRoot.openDeepLink(try #require(URL(string: "first://home"))) == .handled(.root(.home))
    )
    #expect(
      firstRoot.openDeepLink(try #require(URL(string: "second://settings"))) == .schemeMismatch
    )
    #expect(
      secondRoot.openDeepLink(try #require(URL(string: "second://settings")))
        == .handled(.root(.settings))
    )
    #expect(secondRoot.openDeepLink(try #require(URL(string: "first://home"))) == .schemeMismatch)
  }

  @Test
  func `Active router processes deep link URL end-to-end`() throws {
    let root = Router<TestScene>()
    root.activate()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])

    let outcome = root.openDeepLink(try #require(URL(string: "test://settings")))

    #expect(outcome == .handled(.root(.settings)))
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `configureDeepLinks is case-insensitive for scheme`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])
    root.activate()

    let result = root.openDeepLink(try #require(URL(string: "TEST://settings")))
    #expect(result == .handled(.root(.settings)))
  }

  @Test(arguments: [
    "",
    "1test",
    "test scheme",
    "test://",
    "tést",
  ])
  func `configureDeepLinks rejects invalid URL schemes`(_ scheme: String) throws {
    let root = Router<TestScene>()

    #expect {
      try root.configureDeepLinks(scheme: scheme, parsers: [])
    } throws: { error in
      error as? DeepLinkConfigurationError == .invalidScheme(scheme)
    }
    #expect(root.openDeepLink(try #require(URL(string: "test://settings"))) == .unconfigured)
  }

  @Test
  func `configureDeepLinks accepts every URL scheme punctuation character`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test+beta-1.0", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])
    root.activate()

    let result = root.openDeepLink(try #require(URL(string: "test+beta-1.0://settings")))
    #expect(result == .handled(.root(.settings)))
  }

  @Test
  func `configureDeepLinks with empty parsers reports unmatched`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [])
    root.activate()

    let result = root.openDeepLink(try #require(URL(string: "test://settings")))
    #expect(result == .unmatched)
  }

  @Test
  func `configureDeepLinks reports unmatched when no parser recognises the route`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])
    root.activate()

    let result = root.openDeepLink(try #require(URL(string: "test://unknown")))
    #expect(result == .unmatched)
  }

  @Test
  func `Invalid route stops parser evaluation`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      DeepLinkParser { request in
        guard request.components.first == "detail" else { return .noMatch }
        return .invalid
      },
      .equal(to: ["detail"], destination: .root(.settings)),
    ])
    root.activate()

    let result = root.openDeepLink(try #require(URL(string: "test://detail")))
    #expect(result == .invalid)
    #expect(root.selectedRoot == nil)
  }

  @Test
  func `Malformed path returns invalid before parser dispatch`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      DeepLinkParser { _ in .destination(.root(.settings)) }
    ])
    root.activate()

    let result = root.openDeepLink(try #require(URL(string: "test://detail//42")))

    #expect(result == .invalid)
    #expect(root.selectedRoot == nil)
  }

  @Test
  func `Automatic receiver reports every reachable deep-link outcome`() throws {
    let root = Router<TestScene>()
    root.activate()
    var outcomes = [DeepLinkOutcome<TestScene>]()
    let record: @MainActor (DeepLinkOutcome<TestScene>) -> Void = {
      outcomes.append($0)
    }

    root.receiveDeepLink(
      try #require(URL(string: "test://settings")),
      onOutcome: record,
    )

    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])
    root.receiveDeepLink(
      try #require(URL(string: "other://settings")),
      onOutcome: record,
    )
    root.receiveDeepLink(
      try #require(URL(string: "test://unknown")),
      onOutcome: record,
    )
    root.receiveDeepLink(
      try #require(URL(string: "test://detail//42")),
      onOutcome: record,
    )
    root.receiveDeepLink(
      try #require(URL(string: "test://settings")),
      onOutcome: record,
    )

    #expect(outcomes == [
      .unconfigured,
      .schemeMismatch,
      .unmatched,
      .invalid,
      .handled(.root(.settings)),
    ])
  }

  @Test
  func `Inactive automatic receiver ignores delivery without hiding direct outcome`() throws {
    let root = Router<TestScene>()
    try root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["settings"], destination: .root(.settings))
    ])
    var outcomes = [DeepLinkOutcome<TestScene>]()
    let url = try #require(URL(string: "test://settings"))

    root.receiveDeepLink(url) { outcomes.append($0) }

    #expect(outcomes.isEmpty)
    #expect(root.openDeepLink(url) == .inactive)
  }

  @Test
  func `activate is idempotent`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)

    child.activate()
    child.activate()
    #expect(child.isActive)
    #expect(!root.isActive)
  }

  @Test
  func `selectAndPush on child with existing items preserves path`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .settings)
    child.push(.nested)

    root.selectAndPush(root: .settings, destination: .detail(id: "new"))
    #expect(child.navigationPath == [.nested, .detail(id: "new")])
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `selectAndPush then popToRoot on child clears only child`() {
    let root = Router<TestScene>()
    root.selectAndPush(root: .settings, destination: .detail(id: "1"))
    let child = root.childRouter(for: .settings)

    child.popToRoot()
    #expect(child.navigationPath.isEmpty)
    #expect(root.selectedRoot == .settings)
  }

  @Test
  func `present fullScreen from root with selectedRoot delegates to root child`() {
    let root = Router<TestScene>()
    root.selectedRoot = .home
    let child = root.childRouter(for: .home)
    child.activate()

    root.present(fullScreen: .tutorial)

    // Root should NOT hold the presentation — root child does.
    #expect(root.presentingFullScreen == nil)
    #expect(child.presentingFullScreen == .tutorial)
  }

  @Test
  func `present sheet from root with selectedRoot delegates to root child`() {
    let root = Router<TestScene>()
    root.selectedRoot = .settings
    let child = root.childRouter(for: .settings)
    child.activate()

    root.present(sheet: .preferences)

    #expect(root.presentingSheet == nil)
    #expect(child.presentingSheet == .preferences)
  }

  @Test
  func `present fullScreen from child without a root destination presents on self`() {
    let root = Router<TestScene>()
    let modal = root.childRouter()

    modal.present(fullScreen: .onboarding)

    #expect(modal.presentingFullScreen == .onboarding)
  }

  @Test
  func `dismissFullScreen walks up from deep child to clear presentation`() {
    let root = Router<TestScene>()
    root.selectedRoot = .home
    let rootChild = root.childRouter(for: .home)
    rootChild.present(fullScreen: .tutorial)
    let fullScreenChild = rootChild.childRouter()

    // fullScreenChild doesn't hold the presentation — rootChild does.
    fullScreenChild.dismissFullScreen()

    #expect(rootChild.presentingFullScreen == nil)
  }

  @Test
  func `dismissSheet walks up from deep child to clear presentation`() {
    let root = Router<TestScene>()
    root.selectedRoot = .home
    let rootChild = root.childRouter(for: .home)
    rootChild.present(sheet: .profile)
    let sheetChild = rootChild.childRouter()

    sheetChild.dismissSheet()

    #expect(rootChild.presentingSheet == nil)
  }

  @Test
  func `dismissFullScreen is no-op when no ancestor holds presentation`() {
    let root = Router<TestScene>()
    root.activate()

    root.dismissFullScreen()

    #expect(root.presentingFullScreen == nil)
  }

  @Test
  func `navigate fullScreen from root delegates to selected root child`() {
    let root = Router<TestScene>()
    root.selectedRoot = .home
    let child = root.childRouter(for: .home)
    child.activate()

    root.navigate(to: .fullScreen(.tutorial))

    #expect(root.presentingFullScreen == nil)
    #expect(child.presentingFullScreen == .tutorial)
  }

  @Test
  func `navigate sheet from root delegates to selected root child`() {
    let root = Router<TestScene>()
    root.selectedRoot = .settings
    let child = root.childRouter(for: .settings)
    child.activate()

    root.navigate(to: .sheet(.profile))

    #expect(root.presentingSheet == nil)
    #expect(child.presentingSheet == .profile)
  }

  @Test
  func `Root actions are rejected until a RouterHost mounts`() {
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
    let rootChild = root.childRouter(for: .home)
    let modal = rootChild.childRouter()
    rootChild.activate()
    modal.activate()

    root.push(.nested)
    root.present(sheet: .profile)

    #expect(root.navigationPath.isEmpty)
    #expect(rootChild.navigationPath.isEmpty)
    #expect(modal.navigationPath == [.nested])
    #expect(modal.presentingSheet == .profile)
  }

  @Test
  func `Modal disappearance restores its mounted parent`() {
    let root = Router<TestScene>()
    let rootChild = root.childRouter(for: .home)
    let modal = rootChild.childRouter()
    rootChild.activate()
    modal.activate()

    modal.deactivate()

    #expect(!modal.isActive)
    #expect(rootChild.isActive)

    root.push(.nested)
    #expect(rootChild.navigationPath == [.nested])
  }

  @Test
  func `Late disappearance cannot deactivate a newer active root destination`() {
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
  func `Single-stack scene and root stack require no root destination`() {
    let root = Router<SingleStackTestScene>()

    let stack = RouterStack(
      router: root,
      onDeepLinkOutcome: { _ in },
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
    ) {
      EmptyView()
    }

    _ = stack
    #expect(root.level == 0)
  }

  @Test
  func `Push-only scene and stack require no modal destinations`() {
    let root = Router<PushOnlyTestScene>()

    let stack = RouterStack(
      router: root,
      pushContent: { _ in EmptyView() },
    ) {
      EmptyView()
    }

    _ = stack
    #expect(root.level == 0)
  }

  @Test
  func `RouterHost can mount a cached root destination without a stack`() {
    let root = Router<TestScene>()

    let host = RouterHost(
      parentRouter: root,
      root: .home,
      onDeepLinkOutcome: { _ in },
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
    ) {
      EmptyView()
    }

    _ = host
    #expect(root.childRouter(for: .home).rootDestination == .home)
  }

  #if os(macOS)
  @Test(.timeLimit(.minutes(1)))
  func `Mounted root stack follows a replacement Router input`() async throws {
    let first = Router<TestScene>()
    let second = Router<TestScene>()
    let probe = RouterInputProbe()

    func root(router: Router<TestScene>) -> AnyView {
      AnyView(RouterStack(
        router: router,
        pushContent: { _ in EmptyView() },
        sheetContent: { _ in EmptyView() },
        fullScreenContent: { _ in EmptyView() },
      ) {
        RouterInputReporter(probe: probe)
      })
    }

    let hostingView = NSHostingView(rootView: root(router: first))
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
    hostingView.layoutSubtreeIfNeeded()
    try await probe.wait(for: 1)

    #expect(probe.routerIDs.last == ObjectIdentifier(first))
    #expect(first.isActive)

    hostingView.rootView = root(router: second)
    hostingView.layoutSubtreeIfNeeded()
    try await probe.wait(for: 2)

    #expect(probe.routerIDs.last == ObjectIdentifier(second))
    #expect(!first.isActive)
    #expect(second.isActive)

    hostingView.rootView = AnyView(EmptyView())
    hostingView.layoutSubtreeIfNeeded()
    #expect(!second.isActive)
  }
  #endif

}
