import Observation
import VISOR
import VISORObservation
import VISORTesting

struct TestingSnapshot: Equatable, Sendable {
  var value: Int
}

actor TestingService {
  private let channel: ObservationChannel<TestingSnapshot>

  nonisolated let source: ObservationSource<TestingSnapshot>

  nonisolated var activeObservationCount: Int {
    source._visorActiveSubscriptionCount
  }

  init(_ value: Int = 0) {
    let channel = ObservationChannel(TestingSnapshot(value: value))
    self.channel = channel
    source = channel.source
  }

  func publish(_ value: Int) {
    channel.publish(TestingSnapshot(value: value))
  }

  nonisolated func publishSynchronously(_ value: Int) {
    channel.publish(TestingSnapshot(value: value))
  }

  nonisolated func terminate() {
    channel._visorTerminate()
  }
}

@MainActor
final class TestingGate {
  private var hasStarted = false
  private var isOpen = false
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  deinit {}

  func suspend() async {
    hasStarted = true
    let started = startedWaiters
    startedWaiters.removeAll()
    for waiter in started {
      waiter.resume()
    }

    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      openWaiters.append(continuation)
    }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { continuation in
      startedWaiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let waiters = openWaiters
    openWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }
}

final class TestingReference {}

@MainActor
@Observable
@ViewModel
final class TestingViewModel {
  final class State {
    @Bound(
      source: \TestingViewModel.service.source,
      selecting: \TestingSnapshot.value)
    private(set) var sourceValue = -1

    private(set) var reactedValue = -1
    var count = 0
    var status = "idle"
    var reference = TestingReference()
    var anyValue: Any = 0
    var optionalReference: TestingReference?
    var referenceContainer: [TestingReference] = []
  }

  enum Action {
    case setCount(Int)
  }

  let state = State()
  let service: TestingService
  private let reactionGate: TestingGate?

  init(
    service: TestingService = TestingService(),
    reactionGate: TestingGate? = nil
  ) {
    self.service = service
    self.reactionGate = reactionGate
  }

  func handle(_ action: Action) async {
    switch action {
    case let .setCount(value):
      updateState(\.count, to: value)
    }
  }

  @Reaction(
    source: \TestingViewModel.service.source,
    selecting: \TestingSnapshot.value)
  private func sourceChanged(_ value: Int) async {
    if value == 10 {
      await reactionGate?.suspend()
    }
    updateState(\.reactedValue, to: value)
  }
}

final class WeakReference<Value: AnyObject> {
  weak var value: Value?

  init(_ value: Value?) {
    self.value = value
  }
}

/// An intentionally adversarial source-backed conformer used to verify the
/// runtime's identity guard. Production `@ViewModel` expansion requires a
/// stored `let state`; this manual test type can swap that identity without
/// weakening the generated contract.
@MainActor
@Observable
final class SwappableTestingViewModel: ViewModel {
  @MainActor
  @VISOR._ViewModelState
  final class State {
    private(set) var sourceValue = -1
  }

  var state = State()
  let _visorObservationOwnership = _ViewModelObservationOwnership()
  let service: TestingService

  init(service: TestingService) {
    self.service = service
  }

  deinit {}

  func replaceState() {
    state = State()
  }

  func _visorBuildObservationRecipe(
    into visitor: _ObservationRecipeVisitor
  ) {
    visitor.add(
      source: service.source,
      projections: [
        { [weak self] snapshot in
          guard let self else { return }
          self.updateState(\.sourceValue, to: snapshot.value)
        }
      ])
  }
}
