import Foundation
import Testing
import VISOR
import VISORObservation

private struct IntegrationSnapshot: Sendable {
  let count: Int
}

private actor IntegrationService {
  private let channel: ObservationChannel<IntegrationSnapshot>
  nonisolated let source: ObservationSource<IntegrationSnapshot>

  init(count: Int = 0) {
    let channel = ObservationChannel(IntegrationSnapshot(count: count))
    self.channel = channel
    source = channel.source
  }

  func publish(count: Int) {
    channel.publish(IntegrationSnapshot(count: count))
  }
}

@MainActor
private final class IntegrationEvent {
  private struct Waiter {
    let value: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private(set) var values: [Int] = []
  private var waiters: [Waiter] = []

  func record(_ value: Int) {
    values.append(value)
    let completed = waiters.filter { $0.value == value }
    waiters.removeAll { $0.value == value }
    for waiter in completed {
      waiter.continuation.resume()
    }
  }

  func wait(for value: Int) async {
    guard !values.contains(value) else { return }
    await withCheckedContinuation { continuation in
      waiters.append(Waiter(value: value, continuation: continuation))
    }
  }
}

@MainActor
@Observable
@ViewModel
private final class IntegrationViewModel {
  final class State {
    @Bound(
      source: \IntegrationViewModel.service.source,
      selecting: \IntegrationSnapshot.count)
    private(set) var count = -1
  }

  let state = State()
  let service: IntegrationService
  private let event: IntegrationEvent

  init(service: IntegrationService, event: IntegrationEvent) {
    self.service = service
    self.event = event
  }

  @Reaction(
    source: \IntegrationViewModel.service.source,
    selecting: \IntegrationSnapshot.count)
  private func countChanged(_ count: Int) {
    event.record(count)
  }
}

@Suite("V11 integration")
@MainActor
struct IntegrationTests {
  @Test(.timeLimit(.minutes(1)))
  func `A factory-created ViewModel projects its source snapshot`() async throws {
    let service = IntegrationService()
    let event = IntegrationEvent()
    let factory = ViewModelFactory {
      IntegrationViewModel(service: service, event: event)
    }
    let viewModel = factory.makeViewModel()
    let session = _ObservationSession(
      recipes: viewModel._visorMakeObservationRecipes())

    try await session._visorStart()
    #expect(viewModel.state.count == 0)

    await service.publish(count: 42)
    await event.wait(for: 42)
    #expect(viewModel.state.count == 42)

    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1)))
  func `Two ViewModels can independently consume one source`() async throws {
    let service = IntegrationService()
    let firstEvent = IntegrationEvent()
    let secondEvent = IntegrationEvent()
    let first = IntegrationViewModel(service: service, event: firstEvent)
    let second = IntegrationViewModel(service: service, event: secondEvent)
    let firstSession = _ObservationSession(
      recipes: first._visorMakeObservationRecipes())
    let secondSession = _ObservationSession(
      recipes: second._visorMakeObservationRecipes())

    try await firstSession._visorStart()
    try await secondSession._visorStart()

    await service.publish(count: 7)
    await firstEvent.wait(for: 7)
    await secondEvent.wait(for: 7)

    #expect(first.state.count == 7)
    #expect(second.state.count == 7)

    await firstSession._visorStop()
    await secondSession._visorStop()
  }

  @Test(.timeLimit(.minutes(1)))
  func `Navigation and source observation remain independent`() async throws {
    let service = IntegrationService()
    let event = IntegrationEvent()
    let viewModel = IntegrationViewModel(service: service, event: event)
    let router = Router<TestScene>()
    let session = _ObservationSession(
      recipes: viewModel._visorMakeObservationRecipes())

    try await session._visorStart()
    router.activate()
    router.push(.detail(id: "1"))
    router.present(sheet: .preferences)

    await service.publish(count: 10)
    await event.wait(for: 10)

    #expect(viewModel.state.count == 10)
    #expect(router.navigationPath == [.detail(id: "1")])
    #expect(router.presentingSheet == .preferences)

    await session._visorStop()
  }

  @Test
  func `A deep link opened by a child router reaches its push destination`() {
    let root = Router<TestScene>()
    let child = root.childRouter(for: .home)
    root.configureDeepLinks(scheme: "test", parsers: [
      .equal(to: ["home"], destination: .root(.home)),
      .equal(
        to: ["settings", "detail"],
        destination: .push(.detail(id: "deep"))),
    ])
    child.activate()

    let outcome = child.openDeepLink(URL(string: "test://settings/detail")!)

    #expect(outcome == .handled(.push(.detail(id: "deep"))))
    #expect(child.navigationPath == [.detail(id: "deep")])
  }

  @Test
  func `A routed factory receives the concrete Router`() {
    let router = Router<TestScene>()
    let factory: ViewModelFactory<RoutedTestVM> = .routed {
      (router: Router<TestScene>) in
      RoutedTestVM(routerID: ObjectIdentifier(router))
    }

    let viewModel = factory.makeViewModel(router: router)
    #expect(viewModel.routerID == ObjectIdentifier(router))
  }
}
