import Testing
import VISOR

extension ObservationTest {

  // MARK: Public

  /// Requires the complete distinct post-baseline trace to equal `expected`.
  public func expect<Value: Equatable>(
    _ selection: KeyPath<
      SUT.State._VISORSelectors,
      _StateField<SUT.State, Value>,
    >,
    hasExactChanges expected: [Value],
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    guard
      let journal = journalForExpectation(
        sourceLocation: sourceLocation
      )
    else { return }

    let field = SUT.State._visorSelectors[keyPath: selection]
    guard
      let history = strictHistory(
        for: field,
        in: journal,
        sourceLocation: sourceLocation,
      )
    else { return }

    guard !containsAdjacentDuplicate(in: expected) else {
      recordIssue(
        "hasExactChanges cannot contain adjacent duplicate values for '\(field.name)'",
        sourceLocation: sourceLocation,
      )
      return
    }

    var previous = history.baseline
    var actual = [Value]()

    for value in history.commits {
      if value != previous {
        actual.append(value)
        previous = value
      }
    }

    guard actual == expected else {
      recordIssue(
        journal.addingOutsideWindowDiagnosticContext(
          to: "Expected exact changes \(String(describing: expected)) for '\(field.name)', got \(String(describing: actual))"
        ),
        sourceLocation: sourceLocation,
      )
      return
    }
  }

  /// Requires the baseline and every completed commit to satisfy `predicate`.
  public func expect<Value>(
    _ selection: KeyPath<
      SUT.State._VISORSelectors,
      _StateField<SUT.State, Value>,
    >,
    alwaysSatisfies predicate: @MainActor (Value) -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    guard
      let journal = journalForExpectation(
        sourceLocation: sourceLocation
      )
    else { return }

    let field = SUT.State._visorSelectors[keyPath: selection]
    guard
      let history = strictHistory(
        for: field,
        in: journal,
        sourceLocation: sourceLocation,
      )
    else { return }

    guard predicate(history.baseline) else {
      recordIssue(
        journal.addingOutsideWindowDiagnosticContext(
          to: "The baseline for '\(field.name)' did not always satisfy the predicate"
        ),
        sourceLocation: sourceLocation,
      )
      return
    }

    for value in history.commits {
      guard predicate(value) else {
        recordIssue(
          journal.addingOutsideWindowDiagnosticContext(
            to: "A committed value for '\(field.name)' did not always satisfy the predicate"
          ),
          sourceLocation: sourceLocation,
        )
        return
      }
    }
  }

  // MARK: Private

  private func strictHistory<Value>(
    for field: _StateField<SUT.State, Value>,
    in journal: StateJournal,
    sourceLocation: SourceLocation,
  ) -> (baseline: Value, commits: [Value])? {
    guard let erasedBaseline = journal.baseline(for: field.identity) else {
      recordIssue(
        "VISOR could not recover the typed baseline for '\(field.name)'",
        sourceLocation: sourceLocation,
      )
      return nil
    }

    let fieldEntries = journal.entries(for: field.identity)
    guard
      !field.isDirectReference,
      !isOuterReference(erasedBaseline),
      !fieldEntries.contains(where: { isOuterReference($0.newValue) })
    else {
      recordIssue(
        "Strict State history does not support an outer reference value for field '\(field.name)'",
        sourceLocation: sourceLocation,
      )
      return nil
    }

    guard let baseline = erasedBaseline as? Value else {
      recordIssue(
        "VISOR could not recover the typed baseline for '\(field.name)'",
        sourceLocation: sourceLocation,
      )
      return nil
    }

    var commits = [Value]()
    commits.reserveCapacity(fieldEntries.count)

    for entry in fieldEntries {
      guard let value = entry.newValue as? Value else {
        recordIssue(
          "VISOR could not recover a typed commit for '\(field.name)'",
          sourceLocation: sourceLocation,
        )
        return nil
      }
      commits.append(value)
    }

    return (baseline, commits)
  }

  private func isOuterReference(_ value: Any) -> Bool {
    type(of: value) is AnyObject.Type
  }

  private func containsAdjacentDuplicate(
    in values: [some Equatable]
  ) -> Bool {
    zip(values, values.dropFirst()).contains { $0 == $1 }
  }
}
