import Foundation
import Testing
import VISOR
import VISORObservation

private struct LeakSnapshot: Sendable {
  let count: Int
}

@MainActor
private final class LeakService {
  private let channel: ObservationChannel<LeakSnapshot>

  var source: ObservationSource<LeakSnapshot> {
    channel.source
  }

  var activeObservationCount: Int {
    source._visorActiveSubscriptionCount
  }

  init(count: Int = 0) {
    channel = ObservationChannel(LeakSnapshot(count: count))
  }

  func publish(count: Int) {
    channel.publish(LeakSnapshot(count: count))
  }
}

@MainActor
@Observable
@ViewModel
private final class LeakSourceViewModel {
  final class State {
    @Bound(
      source: \LeakSourceViewModel.service.source,
      selecting: \LeakSnapshot.count)
    private(set) var count = -1
  }

  let state = State()
  let service: LeakService

  init(service: LeakService) {
    self.service = service
  }
}

@MainActor
@Observable
@ViewModel
private final class LeakAsyncActionViewModel {
  final class State {
    private(set) var items: Loadable<[String]> = .loading
  }

  enum Action {
    case load
  }

  let state = State()

  func handle(_ action: Action) async {
    switch action {
    case .load:
      updateState(\.items, to: .loading)
      updateState(\.items, to: .loaded(["done"]))
    }
  }
}

@Suite("V11 memory ownership")
@MainActor
struct MemoryLeakTests {
  @Test(.timeLimit(.minutes(1)))
  func `A stopped observation session releases its ViewModel`() async throws {
    let service = LeakService()
    var viewModel: LeakSourceViewModel? = LeakSourceViewModel(service: service)
    weak let weakViewModel = viewModel
    let session = _ObservationSession(
      recipes: viewModel!._visorMakeObservationRecipes())

    try await session._visorStart()
    #expect(service.activeObservationCount == 1)

    await session._visorStop()
    viewModel = nil

    #expect(weakViewModel == nil)
    #expect(service.activeObservationCount == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func `Observation recipes do not retain their ViewModel`() async throws {
    let service = LeakService()
    var viewModel: LeakSourceViewModel? = LeakSourceViewModel(service: service)
    weak let weakViewModel = viewModel
    let session = _ObservationSession(
      recipes: viewModel!._visorMakeObservationRecipes())

    try await session._visorStart()
    viewModel = nil

    #expect(weakViewModel == nil)
    service.publish(count: 1)
    await session._visorStop()
  }

  @Test(.timeLimit(.minutes(1)))
  func `Two sessions sharing a source stop independently`() async throws {
    let service = LeakService()
    var firstViewModel: LeakSourceViewModel? = LeakSourceViewModel(service: service)
    var secondViewModel: LeakSourceViewModel? = LeakSourceViewModel(service: service)
    weak let weakFirst = firstViewModel
    weak let weakSecond = secondViewModel
    let firstSession = _ObservationSession(
      recipes: firstViewModel!._visorMakeObservationRecipes())
    let secondSession = _ObservationSession(
      recipes: secondViewModel!._visorMakeObservationRecipes())

    try await firstSession._visorStart()
    try await secondSession._visorStart()
    #expect(service.activeObservationCount == 2)

    await firstSession._visorStop()
    firstViewModel = nil
    #expect(weakFirst == nil)
    #expect(weakSecond != nil)
    #expect(service.activeObservationCount == 1)

    await secondSession._visorStop()
    secondViewModel = nil
    #expect(weakSecond == nil)
    #expect(service.activeObservationCount == 0)
  }

  @Test
  func `A completed async action does not retain its ViewModel`() async {
    var viewModel: LeakAsyncActionViewModel? = LeakAsyncActionViewModel()
    weak let weakViewModel = viewModel

    await viewModel!.handle(.load)
    #expect(viewModel!.state.items == .loaded(["done"]))

    viewModel = nil
    #expect(weakViewModel == nil)
  }

  @Test
  func `A child Router does not retain its parent`() {
    var root: Router<TestScene>? = Router<TestScene>()
    weak let weakRoot = root
    let child = root!.childRouter(for: .home)

    child.push(.detail(id: "1"))
    root = nil

    #expect(weakRoot == nil)
    #expect(child.navigationPath == [.detail(id: "1")])
  }
}
