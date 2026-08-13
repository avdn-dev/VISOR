import Observation
import VISOR

@MainActor
@Observable
@ViewModel
public final class CompileProofViewModel {
  public struct NonEquatableValue {
    public var rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
  }

  public struct Settings: Equatable {
    public var revision: Int

    public init(revision: Int) {
      self.revision = revision
    }

    public mutating func incrementThenThrow() throws {
      revision += 1
      throw MutationError.expected
    }

    public mutating func throwWithoutChanging() throws {
      throw MutationError.expected
    }
  }

  public enum MutationError: Error {
    case expected
  }

  public final class ReferenceValue: Equatable {
    public var rawValue: Int
    private let onDeinitialise: (@MainActor () -> Void)?

    public init(
      rawValue: Int,
      onDeinitialise: (@MainActor () -> Void)? = nil
    ) {
      self.rawValue = rawValue
      self.onDeinitialise = onDeinitialise
    }

    deinit {
      guard let onDeinitialise else { return }
      // This proof-only hook is installed only where the test deliberately
      // releases the value from VISORTesting's MainActor journal.
      MainActor.assumeIsolated {
        onDeinitialise()
      }
    }

    public static func == (
      lhs: ReferenceValue,
      rhs: ReferenceValue
    ) -> Bool {
      lhs.rawValue == rhs.rawValue
    }
  }

  public enum Phase: Equatable {
    case idle
    case loading
    case loaded
  }

  public enum Action {
    case refresh
    case clear
  }

  public final class State {
    public private(set) var phase: Phase = .idle
    public private(set) var count = 0
    public private(set) var error: String?
    public private(set) var nonEquatableValue = NonEquatableValue(rawValue: 0)
    public private(set) var settings = Settings(revision: 0)
    public private(set) var items: [Int] = []
    public private(set) var reference = ReferenceValue(rawValue: 0)
    public private(set) var identifier: String
    package private(set) var packageRevision = 0
    private(set) var internalRevision = 0
    fileprivate private(set) var fileRevision = 0
    private var privateRevision = 0

    public init(identifier: String = "initial") {
      self.identifier = identifier
    }

    public func setCountDirectly(_ value: Int) {
      count = value
    }

    public func incrementSettingsDirectly() {
      settings.revision += 1
    }

    public func incrementSettingsThenThrow() throws {
      try settings.incrementThenThrow()
    }

    public func leaveSettingsThenThrow() throws {
      try settings.throwWithoutChanging()
    }

    public func appendItemDirectly(_ item: Int) {
      items.append(item)
    }

    public func mutateReferenceInterior() {
      reference.rawValue += 1
    }

    public func setErrorDirectly(_ value: String?) {
      error = value
    }

    package func incrementPackageRevision() {
      self[\.packageRevision] += 1
    }

    func incrementInternalRevision() {
      self[\.internalRevision] += 1
    }

    fileprivate func incrementFileRevision() {
      self[\.fileRevision] += 1
    }

    public func incrementHiddenRevisions() {
      incrementInternalRevision()
      incrementFileRevision()
      privateRevision += 1
    }
  }

  public let state: State

  public init(state: State = State()) {
    self.state = state
  }

  public func handle(_ action: Action) async {
    switch action {
    case .refresh:
      updateState(\.phase, to: .loading)
      updateState(\.count, to: state.count + 1)
      updateState(\.phase, to: .loaded)
    case .clear:
      updateState(\.phase, to: .idle)
    }
  }
}
