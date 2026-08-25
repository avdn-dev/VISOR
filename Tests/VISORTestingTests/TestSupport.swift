import Observation
import VISOR
import VISORObservation
import VISORTesting

// MARK: - TestingSnapshot

struct TestingSnapshot: Equatable, Sendable {
  var value: Int
}

// MARK: - TestingService

actor TestingService {

  // MARK: Lifecycle

  init(_ value: Int = 0) {
    let channel = ObservationChannel(TestingSnapshot(value: value))
    self.channel = channel
    source = channel.source
  }

  // MARK: Internal

  nonisolated let source: ObservationSource<TestingSnapshot>

  nonisolated var activeObservationCount: Int {
    source._visorActiveSubscriptionCount
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

  // MARK: Private

  private let channel: ObservationChannel<TestingSnapshot>

}

// MARK: - TestingReference

final class TestingReference { }

// MARK: - TestingViewModel

@MainActor
@Observable
@ViewModel
final class TestingViewModel {

  // MARK: Lifecycle

  init(
    service: TestingService = TestingService(),
    reactionGate: ControllableOperation<Void, Never>? = nil,
  ) {
    self.service = service
    self.reactionGate = reactionGate
  }

  // MARK: Internal

  final class State {
    @Bound(
      source: \TestingViewModel.service.source,
      selecting: \TestingSnapshot.value,
    )
    private(set) var sourceValue = -1

    private(set) var reactedValue = -1
    var count = 0
    var status = "idle"
    var reference = TestingReference()
    var anyValue: Any = 0
    var optionalReference: TestingReference?
    var referenceContainer = [TestingReference]()
  }

  enum Action {
    case setCount(Int)
  }

  let state = State()
  let service: TestingService

  func handle(_ action: Action) async {
    switch action {
    case .setCount(let value):
      updateState(\.count, to: value)
    }
  }

  // MARK: Private

  private let reactionGate: ControllableOperation<Void, Never>?

  @Reaction(
    source: \TestingViewModel.service.source,
    selecting: \TestingSnapshot.value,
  )
  private func sourceChanged(_ value: Int) async {
    if value == 10 {
      await reactionGate?.run()
    }
    updateState(\.reactedValue, to: value)
  }
}

// MARK: - WeakReference

final class WeakReference<Value: AnyObject> {

  // MARK: Lifecycle

  init(_ value: Value?) {
    self.value = value
  }

  // MARK: Internal

  weak var value: Value?

}

// MARK: - SwappableTestingViewModel

/// An intentionally adversarial source-backed conformer used to verify the
/// runtime's identity guard. Production `@ViewModel` expansion requires a
/// stored `let state`; this manual test type can swap that identity without
/// weakening the generated contract.
@MainActor
@Observable
final class SwappableTestingViewModel: ViewModel {

  // MARK: Lifecycle

  init(service: TestingService) {
    self.service = service
  }

  deinit { }

  // MARK: Internal

  @MainActor
  @VISOR._ViewModelState
  final class State {
    private(set) var sourceValue = -1
  }

  var state = State()
  let _visorObservationOwnership = _ViewModelObservationOwnership()
  let service: TestingService

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
          updateState(\.sourceValue, to: snapshot.value)
        }
      ],
    )
  }
}
