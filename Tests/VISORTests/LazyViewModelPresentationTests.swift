import Observation
import SwiftUI
import Testing
import VISORObservation
import VISORTesting
@testable import VISOR

// MARK: - PresentationModel

@MainActor
@Observable
@ViewModel
private final class PresentationModel {

  // MARK: Internal

  final class State {
    private(set) var enabled = false
    @Bound(source: \PresentationModel.source)
    private(set) var title = "Unprepared"
  }

  enum Action {
    @StateBinding(\State.enabled)
    case enabledChanged(Bool)
  }

  let source: ObservationSource<String>
  let preparation: ControllableOperation<Void, Never>

  func handle(_ action: Action) -> ActionCompletion {
    switch action {
    case .enabledChanged(let enabled): updateState(\.enabled, to: enabled)
    }
    return .completed
  }

  // MARK: Private

  @Reaction(source: \PresentationModel.source)
  private func prepare(_: String) async {
    await preparation.run(preparation.prepare())
  }
}

// MARK: - LazyViewModelPresentationTests

@Suite("Lazy view presentation")
@MainActor
struct LazyViewModelPresentationTests {

  @Test
  func `Retaining an action sender does not retain its presentation`() {
    // Given
    var presentation: _LazyViewModelPresentation<PresentationModel>? = _LazyViewModelPresentation()
    let retainedPresentation = { [weak presentation] in presentation }
    let sender = presentation?._visorSender(observationPolicy: .alwaysObserving, scenePhase: .active)

    // When
    presentation = nil
    let completion = sender?(.enabledChanged(true))

    // Then
    #expect(retainedPresentation() == nil)
    #expect(completion == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func `State and actions become available together and are withdrawn before pause teardown`() async throws {
    // Given
    let channel = ObservationChannel("Library")
    let preparation = ControllableOperation<Void, Never>()
    let model = PresentationModel(source: channel.source, preparation: preparation)
    let presentation = _LazyViewModelPresentation<PresentationModel>()
    var creations = 0
    let factory = PresentationModel.Factory { creations += 1
      return model
    }
    let ready = TestEventCounter()
    let stopped = TestEventCounter()
    let owner = _ViewModelObservationOwner<PresentationModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidStopGeneration: { stopped.record() },
    )

    // When
    let initialState = presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active)
    let initialAction = presentation._visorSend(.enabledChanged(true), observationPolicy: .alwaysObserving, scenePhase: .active)

    // Then
    #expect(initialState == nil)
    #expect(initialAction == nil)
    #expect(creations == 0)

    // When
    _ = presentation.prepare(factory: factory, router: nil)
    _ = presentation.prepare(factory: factory, router: nil)
    presentation.owner = owner
    let root = Task { await owner._visorRun(viewModel: model) }
    defer { root.cancel() }
    try await preparation.waitUntilStarted()

    // Then
    #expect(creations == 1)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
    #expect(presentation._visorSend(.enabledChanged(true), observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
    #expect(!model.state.enabled)

    // When
    preparation.resolveAllInvocations(with: .success(()))
    try await ready.wait()
    let completion = presentation._visorSend(.enabledChanged(true), observationPolicy: .alwaysObserving, scenePhase: .active)
    await completion?.wait()
    let oldBindings = presentation.readyBindings(for: model)

    // Then
    #expect(completion != nil)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active)?.title == "Library")
    #expect(model.state.enabled)
    #expect(presentation._visorState(observationPolicy: .pauseWhenInactive, scenePhase: .inactive) == nil)

    // When
    owner._visorSetEnabled(false)
    oldBindings.enabled.wrappedValue = false
    let pausedAction = presentation._visorSend(.enabledChanged(false), observationPolicy: .alwaysObserving, scenePhase: .active)

    // Then
    #expect(pausedAction == nil)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
    #expect(model.state.enabled)

    // When
    try await stopped.wait()
    owner._visorSetEnabled(true)
    try await preparation.waitUntilStarted(count: 2)
    preparation.resolveAllInvocations(with: .success(()))
    try await ready.wait(untilEventCount: 2)
    oldBindings.enabled.wrappedValue = false

    // Then
    #expect(model.state.enabled)

    // When
    presentation.readyBindings(for: model).enabled.wrappedValue = false
    root.cancel()
    await root.value

    // Then
    #expect(!model.state.enabled)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
    #expect(presentation._visorSend(.enabledChanged(true), observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Infrastructure failure withdraws presentation state and action admission`() async throws {
    // Given
    let channel = ObservationChannel("Library")
    let preparation = ControllableOperation<Void, Never>()
    let model = PresentationModel(source: channel.source, preparation: preparation)
    let presentation = _LazyViewModelPresentation<PresentationModel>()
    _ = presentation.prepare(factory: PresentationModel.Factory { model }, router: nil)
    let failed = TestEventCounter()
    let ready = TestEventCounter()
    let owner = _ViewModelObservationOwner<PresentationModel>(
      _visorDidBecomeReady: { ready.record() },
      _visorDidFail: { _ in failed.record() },
    )
    presentation.owner = owner
    let root = Task { await owner._visorRun(viewModel: model) }
    defer { root.cancel() }
    try await preparation.waitUntilStarted()
    preparation.resolveAllInvocations(with: .success(()))
    try await ready.wait()
    let bindings = presentation.readyBindings(for: model)

    // When
    channel._visorTerminate()
    try await failed.wait()
    bindings.enabled.wrappedValue = true

    // Then
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
    #expect(presentation._visorSend(.enabledChanged(true), observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
    #expect(!model.state.enabled)
    #expect(owner._visorFailure != nil)
    root.cancel()
    await root.value
  }
}

#if os(macOS)
import AppKit

@MainActor
private struct PresentationProbe: NSViewRepresentable {
  let title: String?
  let report: (String?) -> Void

  func makeNSView(context _: Context) -> NSView {
    report(title)
    return NSView()
  }

  func updateNSView(_: NSView, context _: Context) {
    report(title)
  }
}

@MainActor
@LazyViewModel(PresentationModel.self)
private struct PresentationScreen: View {
  let shell: (String?) -> Void
  let pending: () -> Void
  let ready: () -> Void
  let failed: () -> Void

  var body: some View {
    content
      .navigationTitle(state?.title ?? "Library")
      .toolbar {
        Button("Enable") { send(.enabledChanged(true)) }
          .disabled(state == nil)
      }
      .background(PresentationProbe(title: state?.title, report: shell))
  }

  var pendingContent: some View {
    Text("Preparing")
      .background(PresentationProbe(title: nil, report: { _ in pending() }))
  }

  var failureContent: some View {
    Text("Unavailable")
      .onAppear(perform: failed)
  }

  func readyContent(viewModel: PresentationModel) -> some View {
    Text(viewModel.state.title)
      .onAppear(perform: ready)
  }
}

extension LazyViewModelPresentationTests {
  @Test(.timeLimit(.minutes(1)))
  func `Authored presentation and pending content exist before model construction and survive failure`() async throws {
    // Given
    let channel = ObservationChannel("Prepared library")
    let preparation = ControllableOperation<Void, Never>()
    var creations = 0
    var firstRenderCreations: Int?
    var titles = [String?]()
    var pendingRendered = false
    let ready = TestEventCounter()
    let failed = TestEventCounter()
    var screenCreations = 0
    func makeScreen() -> some View {
      screenCreations += 1
      return PresentationScreen(
        shell: { title in
          if firstRenderCreations == nil { firstRenderCreations = creations }
          titles.append(title)
        },
        pending: { pendingRendered = true },
        ready: ready.record,
        failed: failed.record,
      )
      .environment(PresentationModel.Factory {
        creations += 1
        return PresentationModel(source: channel.source, preparation: preparation)
      })
    }
    let view = NSHostingView(rootView: AnyView(makeScreen()))
    view.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    defer {
      view.rootView = AnyView(EmptyView())
      view.layoutSubtreeIfNeeded()
    }

    // When
    view.layoutSubtreeIfNeeded()
    try await preparation.waitUntilStarted()

    // Then
    #expect(firstRenderCreations == 0)
    #expect(creations == 1)
    #expect(pendingRendered)
    #expect(!titles.isEmpty)
    #expect(titles.allSatisfy { $0 == nil })
    #expect(ready.count == 0)

    // When
    preparation.resolveAllInvocations(with: .success(()))
    try await ready.wait()
    view.layoutSubtreeIfNeeded()

    // Then
    #expect(titles.last == "Prepared library")
    #expect(creations == 1)

    // When - fresh view values keep the installed State storage
    for _ in 0..<10 {
      view.rootView = AnyView(makeScreen())
      view.layoutSubtreeIfNeeded()
    }

    // Then
    #expect(screenCreations == 11)
    #expect(titles.last == "Prepared library")
    #expect(creations == 1)

    // When
    channel._visorTerminate()
    try await failed.wait()
    view.layoutSubtreeIfNeeded()

    // Then
    #expect(titles.last.map { $0 == nil } == true)
    #expect(creations == 1)
  }
}
#endif
