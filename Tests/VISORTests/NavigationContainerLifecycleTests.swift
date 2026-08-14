//
//  NavigationContainerLifecycleTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 14/8/2026.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import VISOR

@MainActor
private final class NavigationLifecycleProbe {
  private struct Waiter {
    let count: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private var counts: [NavigationLifecycleEvent: Int] = [:]
  private var waiters: [NavigationLifecycleEvent: [Waiter]] = [:]

  func record(_ event: NavigationLifecycleEvent) {
    let count = counts[event, default: 0] + 1
    counts[event] = count

    let waiting = waiters.removeValue(forKey: event) ?? []
    var remaining: [Waiter] = []
    for waiter in waiting {
      if count >= waiter.count {
        waiter.continuation.resume()
      } else {
        remaining.append(waiter)
      }
    }
    if !remaining.isEmpty {
      waiters[event] = remaining
    }
  }

  func wait(for event: NavigationLifecycleEvent, count: Int = 1) async {
    guard counts[event, default: 0] < count else { return }
    await withCheckedContinuation { continuation in
      waiters[event, default: []].append(Waiter(
        count: count,
        continuation: continuation))
    }
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
    TabView(selection: $router.selectedTab) {
      NavigationContainer(
        parentRouter: router,
        tab: .home,
        pushContent: { _ in EmptyView() },
        sheetContent: { _ in EmptyView() },
        fullScreenContent: { _ in EmptyView() }
      ) {
        NavigationLifecycleMarker(
          appeared: .homeAppeared,
          disappeared: .homeDisappeared,
          probe: probe)
      }
      .tabItem { Text("Home") }
      .tag(TestTab.home as TestTab?)

      NavigationContainer(
        parentRouter: router,
        tab: .settings,
        pushContent: { _ in EmptyView() },
        sheetContent: { _ in EmptyView() },
        fullScreenContent: { _ in EmptyView() }
      ) {
        NavigationLifecycleMarker(
          appeared: .settingsAppeared,
          disappeared: nil,
          probe: probe)
      }
      .tabItem { Text("Settings") }
      .tag(TestTab.settings as TestTab?)
    }
  }
}

@MainActor
private final class NavigationViewHost {
  let hostingView: NSHostingView<AnyView>
  private let window: NSWindow

  init(rootView: AnyView) {
    _ = NSApplication.shared
    hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled],
      backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.orderFront(nil)
    layout()
  }

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
}

@Suite("NavigationContainer lifecycle", .serialized)
@MainActor
struct NavigationContainerLifecycleTests {
  @Test(.timeLimit(.minutes(1)))
  func `Mounted stack follows Router push and pop`() async {
    let router = Router<TestScene>()
    let probe = NavigationLifecycleProbe()
    let root = AnyView(NavigationContainer(
      router: router,
      pushContent: { _ in
        NavigationLifecycleMarker(
          appeared: .detailAppeared,
          disappeared: .detailDisappeared,
          probe: probe)
      },
      sheetContent: { _ in EmptyView() },
      fullScreenContent: { _ in EmptyView() }
    ) {
      EmptyView()
    })
    let host = NavigationViewHost(rootView: root)
    defer { host.close() }

    router.push(.nested)
    host.layout()
    await probe.wait(for: .detailAppeared)

    #expect(router.navigationPath == [.nested])

    router.popToRoot()
    host.layout()
    await probe.wait(for: .detailDisappeared)

    #expect(router.navigationPath.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Mounted TabView activates the selected tab Router`() async {
    let router = Router<TestScene>()
    let home = router.childRouter(for: .home)
    let settings = router.childRouter(for: .settings)
    let probe = NavigationLifecycleProbe()
    router.selectedTab = .home

    let host = NavigationViewHost(rootView: AnyView(
      NavigationTabLifecycleHost(router: router, probe: probe)))
    defer { host.close() }
    await probe.wait(for: .homeAppeared)

    #expect(home.isActive)
    #expect(!settings.isActive)

    router.select(tab: .settings)
    host.layout()
    await probe.wait(for: .settingsAppeared)
    await probe.wait(for: .homeDisappeared)

    #expect(!home.isActive)
    #expect(settings.isActive)

    router.push(.detail(id: "selected"))
    #expect(home.navigationPath.isEmpty)
    #expect(settings.navigationPath == [.detail(id: "selected")])
  }

  @Test(.timeLimit(.minutes(1)))
  func `Mounted sheet restores its presenting Router on dismissal`() async throws {
    let router = Router<TestScene>()
    let probe = NavigationLifecycleProbe()
    let root = AnyView(NavigationContainer(
      router: router,
      pushContent: { _ in EmptyView() },
      sheetContent: { _ in
        NavigationLifecycleMarker(
          appeared: .sheetAppeared,
          disappeared: .sheetDisappeared,
          probe: probe)
      },
      fullScreenContent: { _ in EmptyView() }
    ) {
      EmptyView()
    })
    let host = NavigationViewHost(rootView: root)
    defer { host.close() }
    #expect(router.isActive)

    router.present(sheet: .preferences)
    let presentedRouter = try #require(router.sheetPresentation?.router)
    host.layout()
    await probe.wait(for: .sheetAppeared)

    #expect(!router.isActive)
    #expect(presentedRouter.isActive)

    router.dismissSheet()
    host.layout()
    await probe.wait(for: .sheetDisappeared)

    #expect(router.presentingSheet == nil)
    #expect(!presentedRouter.isActive)
    #expect(router.isActive)
  }
}
#endif
