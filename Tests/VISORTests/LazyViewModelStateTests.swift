// These allocation guarantees belong to the State macro introduced with Xcode 27.
// Earlier supported toolchains use SwiftUI's eager State property wrapper.
#if os(macOS) && compiler(>=6.4)
import AppKit
import Observation
import SwiftUI
import Testing
@testable import VISOR

@MainActor
@Observable
private final class LazyStateValue: _LazyViewModelStateValue {

  // MARK: Lifecycle

  init() {
    Self.creations += 1
  }

  // MARK: Internal

  static var creations = 0

  var count = 0
}

@MainActor
private struct LazyStateProbe: NSViewRepresentable {
  let value: LazyStateValue
  let count: Int
  let report: (LazyStateValue, Int) -> Void

  func makeNSView(context _: Context) -> NSView {
    report(value, count)
    return NSView()
  }

  func updateNSView(_: NSView, context _: Context) {
    report(value, count)
  }
}

@MainActor
private struct LazyStateScreen: View {
  init(report: @escaping (LazyStateValue, Int) -> Void) {
    self.report = report
  }

  var body: some View {
    LazyStateProbe(value: storage, count: storage.count, report: report)
  }

  @_LazyViewModelState private var storage: LazyStateValue
  private let report: (LazyStateValue, Int) -> Void
}

@Suite("Lazy view state storage")
@MainActor
struct LazyViewModelStateTests {
  @Test
  func `Unmounted view construction does not evaluate the state initialiser`() {
    // Given
    LazyStateValue.creations = 0

    // When
    let screens = (0..<100).map { _ in
      LazyStateScreen(report: { _, _ in })
    }

    // Then
    #expect(screens.count == 100)
    #expect(LazyStateValue.creations == 0)
  }

  @Test
  func `Fresh view values share one lazy object until structural identity changes`() throws {
    // Given
    LazyStateValue.creations = 0
    var reportedValue: LazyStateValue?
    var reportedCount: Int?
    func makeScreen() -> some View {
      LazyStateScreen(report: { value, count in
        reportedValue = value
        reportedCount = count
      })
    }
    let view = NSHostingView(rootView: AnyView(makeScreen().id(0)))
    view.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    defer {
      view.rootView = AnyView(EmptyView())
      view.layoutSubtreeIfNeeded()
    }

    // When
    view.layoutSubtreeIfNeeded()

    // Then
    let firstValue = try #require(reportedValue)
    #expect(LazyStateValue.creations == 1)
    #expect(reportedCount == 0)

    // When
    firstValue.count = 7
    view.layoutSubtreeIfNeeded()

    // Then
    #expect(reportedCount == 7)

    // When
    for _ in 0..<100 {
      view.rootView = AnyView(makeScreen().id(0))
      view.layoutSubtreeIfNeeded()
    }

    // Then
    #expect(LazyStateValue.creations == 1)
    #expect(reportedValue === firstValue)
    #expect(reportedCount == 7)

    // When
    view.rootView = AnyView(makeScreen().id(1))
    view.layoutSubtreeIfNeeded()

    // Then
    #expect(LazyStateValue.creations == 2)
    #expect(reportedValue !== firstValue)
    #expect(reportedCount == 0)
  }
}
#endif
