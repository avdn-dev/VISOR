//
//  RouterStackLifecycleTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 14/8/2026.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
import VISORTesting
@testable import VISOR

@MainActor
private final class NavigationLifecycleProbe {

  // MARK: Internal

  func record(_ event: NavigationLifecycleEvent) {
    counter(for: event).record()
  }

  func wait(for event: NavigationLifecycleEvent, count: Int = 1) async throws {
    try await counter(for: event).wait(for: count)
  }

  // MARK: Private

  private var counters = [NavigationLifecycleEvent: TestEventCounter]()

  private func counter(
    for event: NavigationLifecycleEvent
  ) -> TestEventCounter {
    if let counter = counters[event] {
      return counter
    }
    let counter = TestEventCounter()
    counters[event] = counter
    return counter
  }

}

private enum NavigationLifecycleEvent: Hashable {
  case detailAppeared
  case detailDisappeared
  case homeAppeared
  case homeDisappeared
  case settingsAppeared
  case sheetAppeared
  case sheetDisappeared
}

@MainActor
private struct NavigationLifecycleMarker: View {
  let appeared: NavigationLifecycleEvent
  let disappeared: NavigationLifecycleEvent?
  let probe: NavigationLifecycleProbe

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .onAppear { probe.record(appeared) }
      .onDisappear {
        if let disappeared {
          probe.record(disappeared)
        }
      }
  }
}

@MainActor
private struct NavigationTabLifecycleHost: View {
  @Bindable var router: Router<TestScene>

  let probe: NavigationLifecycleProbe

  var body: some View {
    RouterHost(
      router: router,
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
    ) {
      TabView(selection: $router.selectedRoot) {
        RouterStack(
          parentRouter: router,
          root: .home,
          pushContent: { _ in EmptyView() },
          sheetContent: { _ in EmptyView() },
          fullScreenContent: { _ in EmptyView() },
        ) {
          NavigationLifecycleMarker(
            appeared: .homeAppeared,
            disappeared: .homeDisappeared,
            probe: probe,
          )
        }
        .tabItem { Text("Home") }
        .tag(TestRoot.home as TestRoot?)

        RouterStack(
          parentRouter: router,
          root: .settings,
          pushContent: { _ in EmptyView() },
          sheetContent: { _ in EmptyView() },
          fullScreenContent: { _ in EmptyView() },
        ) {
          NavigationLifecycleMarker(
            appeared: .settingsAppeared,
            disappeared: nil,
            probe: probe,
          )
        }
        .tabItem { Text("Settings") }
        .tag(TestRoot.settings as TestRoot?)
      }
    }
  }
}

@MainActor
private struct NavigationSplitLifecycleHost: View {

  // MARK: Internal

  @Bindable var router: Router<TestScene>

  let probe: NavigationLifecycleProbe

  var body: some View {
    RouterHost(
      router: router,
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
    ) {
      NavigationSplitView {
        List(selection: $router.selectedRoot) {
          Text("Home").tag(TestRoot.home)
          Text("Settings").tag(TestRoot.settings)
        }
      } detail: {
        switch router.selectedRoot {
        case .home:
          rootStack(
            root: .home,
            appeared: .homeAppeared,
            disappeared: .homeDisappeared,
          )

        case .settings:
          rootStack(
            root: .settings,
            appeared: .settingsAppeared,
            disappeared: nil,
          )

        case nil:
          Text("Select a destination")
        }
      }
    }
  }

  // MARK: Private

  private func rootStack(
    root: TestRoot,
    appeared: NavigationLifecycleEvent,
    disappeared: NavigationLifecycleEvent?,
  ) -> some View {
    RouterStack(
      parentRouter: router,
      root: root,
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
    ) {
      NavigationLifecycleMarker(
        appeared: appeared,
        disappeared: disappeared,
        probe: probe,
      )
    }
  }
}

@MainActor
private final class NavigationViewHost {

  // MARK: Lifecycle

  init(rootView: AnyView) {
    _ = NSApplication.shared
    hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false,
    )
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.orderFront(nil)
    layout()
  }

  // MARK: Internal

  let hostingView: NSHostingView<AnyView>

  func layout() {
    hostingView.layoutSubtreeIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
  }

  func close() {
    hostingView.rootView = AnyView(EmptyView())
    layout()
    window.contentView = nil
    window.close()
  }

  // MARK: Private

  private let window: NSWindow

}

@Suite("Router host and stack lifecycle", .serialized)
@MainActor
struct RouterStackLifecycleTests {
  @Test(.timeLimit(.minutes(1)))
  func `Mounted RouterHost without a selected root activates the root Router`() async throws {
    let router = Router<TestScene>()
    let probe = NavigationLifecycleProbe()
    let root = AnyView(RouterHost(
      router: router,
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
    ) {
      NavigationLifecycleMarker(
        appeared: .homeAppeared,
        disappeared: nil,
        probe: probe,
      )
    })
    let host = NavigationViewHost(rootView: root)
    defer { host.close() }
    try await probe.wait(for: .homeAppeared)

    #expect(router.isActive)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Mounted stack follows Router push and pop`() async throws {
    let router = Router<TestScene>()
    let probe = NavigationLifecycleProbe()
    let root = AnyView(RouterStack(
      router: router,
      pushContent: { _ in
        NavigationLifecycleMarker(
          appeared: .detailAppeared,
          disappeared: .detailDisappeared,
          probe: probe,
        )
      },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() },
    ) {
      EmptyView()
    })
    let host = NavigationViewHost(rootView: root)
    defer { host.close() }

    router.push(.nested)
    host.layout()
    try await probe.wait(for: .detailAppeared)

    #expect(router.navigationPath == [.nested])

    router.popToRoot()
    host.layout()
    try await probe.wait(for: .detailDisappeared)

    #expect(router.navigationPath.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Mounted TabView activates the selected tab Router`() async throws {
    let router = Router<TestScene>()
    let home = router.childRouter(for: .home)
    let settings = router.childRouter(for: .settings)
    let probe = NavigationLifecycleProbe()
    router.selectedRoot = .home

    let host = NavigationViewHost(rootView: AnyView(
      NavigationTabLifecycleHost(router: router, probe: probe)
    ))
    defer { host.close() }
    try await probe.wait(for: .homeAppeared)

    #expect(home.isActive)
    #expect(!settings.isActive)

    router.select(root: .settings)
    host.layout()
    try await probe.wait(for: .settingsAppeared)
    try await probe.wait(for: .homeDisappeared)

    #expect(!home.isActive)
    #expect(settings.isActive)

    router.push(.detail(id: "selected"))
    #expect(home.navigationPath.isEmpty)
    #expect(settings.navigationPath == [.detail(id: "selected")])
  }

  @Test(.timeLimit(.minutes(1)))
  func `Mounted NavigationSplitView activates the selected root Router`() async throws {
    let router = Router<TestScene>()
    let home = router.childRouter(for: .home)
    let settings = router.childRouter(for: .settings)
    let probe = NavigationLifecycleProbe()
    router.selectedRoot = .home

    let host = NavigationViewHost(rootView: AnyView(
      NavigationSplitLifecycleHost(router: router, probe: probe)
    ))
    defer { host.close() }
    try await probe.wait(for: .homeAppeared)

    #expect(home.isActive)
    #expect(!settings.isActive)

    router.select(root: .settings)
    host.layout()
    try await probe.wait(for: .settingsAppeared)
    try await probe.wait(for: .homeDisappeared)

    #expect(!home.isActive)
    #expect(settings.isActive)

    router.present(sheet: .preferences)
    #expect(home.presentingSheet == nil)
    #expect(settings.presentingSheet == .preferences)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Mounted sheet restores its presenting Router on dismissal`() async throws {
    let router = Router<TestScene>()
    let probe = NavigationLifecycleProbe()
    let root = AnyView(RouterStack(
      router: router,
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in
        NavigationLifecycleMarker(
          appeared: .sheetAppeared,
          disappeared: .sheetDisappeared,
          probe: probe,
        )
      },
      fullScreenContent: { _ in EmptyView() },
    ) {
      EmptyView()
    })
    let host = NavigationViewHost(rootView: root)
    defer { host.close() }
    #expect(router.isActive)

    router.present(sheet: .preferences)
    let presentedRouter = try #require(router.sheetPresentation?.router)
    host.layout()
    try await probe.wait(for: .sheetAppeared)

    #expect(!router.isActive)
    #expect(presentedRouter.isActive)

    router.dismissSheet()
    host.layout()
    try await probe.wait(for: .sheetDisappeared)

    #expect(router.presentingSheet == nil)
    #expect(!presentedRouter.isActive)
    #expect(router.isActive)
  }
}
#endif
