import Testing
import VISOR

@MainActor
struct JournalEntry {
  let fieldID: ObjectIdentifier
  let fieldName: String
  let oldValue: Any
  let newValue: Any
}

enum JournalWindowState: Equatable {
  case outside
  case opening(UInt64)
  case active
  case invalidated
  case ended
}

enum StateJournalFailure: Error, CustomStringConvertible {
  case maximumCommitCountPerActionExceeded(limit: Int)

  var description: String {
    switch self {
    case .maximumCommitCountPerActionExceeded(let limit):
      "the action window exceeded the configured maximumCommitCountPerAction of \(limit) raw State commits"
    }
  }
}

@MainActor
final class StateJournal: _StateMutationRecorder {
  // The accepted fixture's scalar, growing-collection and repeated
  // copy-on-write stress window retains 4,352 raw commits. This limit leaves
  // headroom for ordinary tests while still bounding runaway cheap-value
  // mutation storms.
  static let defaultMaximumCommitCountPerAction = 8_000
  static let defaultOutsideWindowCapacity = 32

  private(set) var entries: [JournalEntry] = []
  private var baselines: [ObjectIdentifier: Any] = [:]
  private(set) var hasClosedWindow = false
  private let maximumCommitCountPerAction: Int
  private var outsideWindowRing: OutsideWindowMutationRing
  private var windowState = JournalWindowState.outside
  private var nextActionOrdinal: UInt64 = 1
  private var currentActionOrdinal: UInt64?
  private var lastCompletedActionOrdinal: UInt64?
  private var activeSourceLocation: SourceLocation?
  private let issueRecorder: ObservationTestIssueRecorder
  private var failureHandler:
    (@MainActor (any Error, SourceLocation) -> Void)?

  init(
    maximumCommitCountPerAction: Int,
    outsideWindowCapacity: Int = defaultOutsideWindowCapacity,
    issueRecorder: @escaping ObservationTestIssueRecorder
  ) {
    precondition(maximumCommitCountPerAction > 0)
    self.maximumCommitCountPerAction = maximumCommitCountPerAction
    self.issueRecorder = issueRecorder
    outsideWindowRing = OutsideWindowMutationRing(
      capacity: outsideWindowCapacity)
  }

  // Work around a Swift 6.2.4 release optimiser crash for explicitly
  // MainActor-isolated classes.
  deinit {}

  func installFailureHandler(
    _ handler: @escaping @MainActor (any Error, SourceLocation) -> Void
  ) {
    failureHandler = handler
  }

  func begin<State: _ViewModelState>(
    state: State,
    sourceLocation: SourceLocation
  ) -> Bool {
    guard windowState == .outside else {
      issueRecorder(
        "A perform window is already active for this State",
        sourceLocation)
      return false
    }

    let actionOrdinal = nextActionOrdinal
    if nextActionOrdinal < .max {
      nextActionOrdinal += 1
    }
    windowState = .opening(actionOrdinal)

    // Releasing the previous typed window may synchronously run a retained
    // value's deinitialiser. Its routed writes still precede this action's
    // baseline and are classified through the explicit opening phase below.
    entries.removeAll(keepingCapacity: true)
    baselines.removeAll(keepingCapacity: true)

    if let previous = lastCompletedActionOrdinal {
      outsideWindowRing.reclassifyAfterAction(
        previous,
        asBefore: actionOrdinal)
    } else {
      outsideWindowRing.reclassifyBeforeFirstAction(as: actionOrdinal)
    }

    for field in State._visorAllFields {
      baselines[field.identity] = field.read(from: state)
    }
    activeSourceLocation = sourceLocation
    hasClosedWindow = false
    currentActionOrdinal = actionOrdinal
    windowState = .active
    return true
  }

  func close() {
    guard windowState == .active else { return }
    windowState = .outside
    hasClosedWindow = true
    activeSourceLocation = nil
    lastCompletedActionOrdinal = currentActionOrdinal
    currentActionOrdinal = nil
  }

  func abandon() {
    windowState = .invalidated
    hasClosedWindow = false
    activeSourceLocation = nil
    currentActionOrdinal = nil
    entries.removeAll(keepingCapacity: false)
    baselines.removeAll(keepingCapacity: false)
  }

  func finish() {
    windowState = .ended
    hasClosedWindow = false
    activeSourceLocation = nil
    currentActionOrdinal = nil
    lastCompletedActionOrdinal = nil
    entries.removeAll(keepingCapacity: false)
    baselines.removeAll(keepingCapacity: false)
    outsideWindowRing.removeAll()
  }

  func record(
    fieldID: ObjectIdentifier,
    fieldName: String,
    oldValue: Any,
    newValue: Any
  ) {
    switch windowState {
    case .outside:
      let relation = lastCompletedActionOrdinal.map {
        _OutsideWindowMutationForProof.Relation.afterAction($0)
      } ?? .beforeFirstAction
      outsideWindowRing.append(
        fieldID: fieldID,
        fieldName: fieldName,
        relation: relation)
      return
    case let .opening(action):
      let relation = lastCompletedActionOrdinal.map {
        _OutsideWindowMutationForProof.Relation.betweenActions(
          previous: $0,
          next: action)
      } ?? .beforeAction(action)
      outsideWindowRing.append(
        fieldID: fieldID,
        fieldName: fieldName,
        relation: relation)
      return
    case .invalidated, .ended:
      return
    case .active:
      break
    }

    guard entries.count < maximumCommitCountPerAction else {
      let sourceLocation = activeSourceLocation
      abandon()
      if let sourceLocation {
        failureHandler?(
          StateJournalFailure.maximumCommitCountPerActionExceeded(
            limit: maximumCommitCountPerAction),
          sourceLocation)
      }
      return
    }

    entries.append(JournalEntry(
      fieldID: fieldID,
      fieldName: fieldName,
      oldValue: oldValue,
      newValue: newValue))
  }

  func entries(for fieldID: ObjectIdentifier) -> [JournalEntry] {
    entries.filter { $0.fieldID == fieldID }
  }

  func baseline(for fieldID: ObjectIdentifier) -> Any? {
    baselines[fieldID]
  }

  func outsideWindowDiagnosticContext()
    -> _OutsideWindowDiagnosticContextForProof
  {
    outsideWindowRing.snapshot()
  }

  func addingOutsideWindowDiagnosticContext(to message: String) -> String {
    let context = outsideWindowRing.snapshot()
    guard !context.entries.isEmpty || context.omittedEntryCount > 0 else {
      return message
    }

    let entries = context.entries.map { entry in
      "#\(entry.order) \(entry.fieldName) \(describe(entry.relation))"
    }
    let entryList = entries.joined(separator: "; ")
    return "\(message)\nOutside-window context (\(context.omittedEntryCount) omitted): \(entryList)"
  }

  private func describe(
    _ relation: _OutsideWindowMutationForProof.Relation
  ) -> String {
    switch relation {
    case .beforeFirstAction:
      "before the first action"
    case let .beforeAction(action):
      "before action \(action)"
    case let .betweenActions(previous, next):
      "between actions \(previous) and \(next)"
    case let .afterAction(action):
      "after action \(action)"
    }
  }
}
