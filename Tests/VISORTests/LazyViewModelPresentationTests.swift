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
    // A paused owner retains its lease even though it cannot expose content.
    let unrelatedOwner = _ViewModelObservationOwner<PresentationModel>()
    presentation.owner = unrelatedOwner
    presentation.restoreOwner(owner, isEnabled: true)

    // Then
    #expect(presentation.owner === owner)
    #expect(!owner._visorIsReady)

    // When
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

    // When - reappearance must preserve a terminal failure in the current epoch.
    let failure = owner._visorFailure
    presentation.owner = nil
    presentation.restoreOwner(owner, isEnabled: true)

    // Then
    #expect(presentation.owner === owner)
    #expect(owner._visorFailure == failure)
    #expect(owner._visorGenerationCount == 1)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active) == nil)
    root.cancel()
    await root.value
  }

  @Test(.timeLimit(.minutes(1)))
  func `Releasing and released owners cannot displace the current presentation`() async throws {
    // Given
    let channel = ObservationChannel("Tracking")
    let preparation = ControllableOperation<Void, Never>()
    let model = PresentationModel(source: channel.source, preparation: preparation)
    let presentation = _LazyViewModelPresentation<PresentationModel>()
    _ = presentation.prepare(factory: PresentationModel.Factory { model }, router: nil)
    let ready = TestEventCounter()
    let originalOwner = _ViewModelObservationOwner<PresentationModel>(
      _visorDidBecomeReady: ready.record
    )
    presentation.owner = originalOwner
    let originalRoot = Task { await originalOwner._visorRun(viewModel: model) }
    defer { originalRoot.cancel() }
    try await preparation.waitUntilStarted()
    preparation.resolveAllInvocations(with: .success(()))
    try await ready.wait()
    let replacementOwner = _ViewModelObservationOwner<PresentationModel>(
      _visorDidBecomeReady: ready.record
    )

    // When - cancellation revokes the lease before MainActor teardown can run.
    originalRoot.cancel()
    presentation.owner = replacementOwner
    presentation.restoreOwner(originalOwner, isEnabled: true)

    // Then
    #expect(presentation.owner === replacementOwner)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active) == nil)

    // When - a replacement becomes ready after the old root has joined.
    await originalRoot.value
    let replacementRoot = Task { await replacementOwner._visorRun(viewModel: model) }
    defer { replacementRoot.cancel() }
    try await preparation.waitUntilStarted(count: 2)
    preparation.resolveAllInvocations(with: .success(()))
    try await ready.wait(untilEventCount: 2)
    presentation.restoreOwner(originalOwner, isEnabled: false)

    // Then
    #expect(presentation.owner === replacementOwner)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active)?.title == "Tracking")
    #expect(presentation._visorSend(.enabledChanged(true), observationPolicy: .alwaysObserving, scenePhase: .active) != nil)
    #expect(model.state.enabled)
    #expect(originalOwner._visorGenerationCount == 1)
    #expect(replacementOwner._visorGenerationCount == 1)

    // When
    replacementRoot.cancel()
    await replacementRoot.value

    // Then
    #expect(!model._visorObservationOwnership._visorIsActionable(ownerID: ObjectIdentifier(replacementOwner)))
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

#if os(macOS)
extension LazyViewModelPresentationTests {
  @Test(.timeLimit(.minutes(1)))
  func `Reappearing content restores only the current observation owner`() async throws {
    // Given
    let channel = ObservationChannel("Tracking")
    let preparation = ControllableOperation<Void, Never>()
    let model = PresentationModel(source: channel.source, preparation: preparation)
    let presentation = _LazyViewModelPresentation<PresentationModel>()
    let appeared = TestEventCounter()
    let disappeared = TestEventCounter()
    let failed = TestEventCounter()
    let transientAppeared = TestEventCounter()
    var creations = 0
    let content = _visorLazyViewModelContent(
      presentation: presentation,
      observationPolicy: .alwaysObserving,
      pending: { Text("Preparing") },
      failure: { Text("Unavailable").onAppear(perform: failed.record) },
      ready: { model, _ in
        Text(model.state.title)
          .onAppear(perform: appeared.record)
          .onDisappear(perform: disappeared.record)
      },
    )
    .environment(PresentationModel.Factory {
      creations += 1
      return model
    })
    let retained = NSHostingView(rootView: AnyView(content))
    retained.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    let window = NSWindow(
      contentRect: retained.frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false,
    )
    window.isReleasedWhenClosed = false
    window.contentView = retained
    window.orderFront(nil)
    defer {
      retained.rootView = AnyView(EmptyView())
      retained.layoutSubtreeIfNeeded()
      window.contentView = nil
      window.close()
    }
    retained.layoutSubtreeIfNeeded()
    try await preparation.waitUntilStarted()
    preparation.resolveAllInvocations(with: .success(()))
    try await appeared.wait()
    let originalOwner = try #require(presentation.owner)

    // When - a transient descendant mounts while the original tab remains retained.
    window.contentView = nil
    try await disappeared.wait()
    let transient = NSHostingView(rootView: AnyView(
      content.onAppear(perform: transientAppeared.record)
    ))
    transient.frame = retained.frame
    window.contentView = transient
    transient.layoutSubtreeIfNeeded()
    try await failed.wait()
    let rejectedOwner = try #require(presentation.owner)

    // Then
    #expect(presentation.owner !== originalOwner)
    #expect(originalOwner._visorIsReady)

    // When - returning to the original structural identity must restore its owner.
    window.contentView = retained
    retained.layoutSubtreeIfNeeded()
    try await appeared.wait(untilEventCount: 2)

    // Then
    #expect(presentation.owner === originalOwner)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active)?.title == "Tracking")
    #expect(presentation._visorSend(.enabledChanged(true), observationPolicy: .alwaysObserving, scenePhase: .active) != nil)
    #expect(model.state.enabled)
    #expect(presentation.model === model)
    #expect(creations == 1)
    #expect(originalOwner._visorGenerationCount == 1)

    // When - a rejected host returns after the legitimate owner has recovered.
    window.contentView = transient
    transient.layoutSubtreeIfNeeded()
    try await transientAppeared.wait(untilEventCount: 2)

    // Then
    #expect(rejectedOwner._visorFailure == .duplicateOwner)
    #expect(presentation.owner === originalOwner)
    #expect(presentation._visorState(observationPolicy: .alwaysObserving, scenePhase: .active)?.title == "Tracking")
    #expect(presentation._visorSend(.enabledChanged(false), observationPolicy: .alwaysObserving, scenePhase: .active) != nil)
    #expect(!model.state.enabled)
    #expect(creations == 1)
    #expect(originalOwner._visorGenerationCount == 1)
  }
}
#endif
