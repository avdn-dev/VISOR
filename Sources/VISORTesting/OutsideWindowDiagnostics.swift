// MARK: - _OutsideWindowMutationForProof

package struct _OutsideWindowMutationForProof: Equatable {
  package enum Relation: Equatable {
    case beforeFirstAction
    case beforeAction(UInt64)
    case betweenActions(previous: UInt64, next: UInt64)
    case afterAction(UInt64)
  }

  package let order: UInt64
  package let fieldID: ObjectIdentifier
  package let fieldName: String
  package let relation: Relation
}

// MARK: - _OutsideWindowDiagnosticContextForProof

package struct _OutsideWindowDiagnosticContextForProof: Equatable {
  package let entries: [_OutsideWindowMutationForProof]
  package let omittedEntryCount: UInt64
}

// MARK: - OutsideWindowMutationEntry

struct OutsideWindowMutationEntry {
  let order: UInt64
  let fieldID: ObjectIdentifier
  let fieldName: String
  var relation: _OutsideWindowMutationForProof.Relation
}

// MARK: - OutsideWindowMutationRing

struct OutsideWindowMutationRing {

  // MARK: Lifecycle

  init(capacity: Int) {
    precondition(capacity > 0)
    storage = Array(repeating: nil, count: capacity)
  }

  // MARK: Internal

  private(set) var count = 0
  private(set) var omittedEntryCount: UInt64 = 0

  mutating func append(
    fieldID: ObjectIdentifier,
    fieldName: String,
    relation: _OutsideWindowMutationForProof.Relation,
  ) {
    let entry = OutsideWindowMutationEntry(
      order: nextOrder,
      fieldID: fieldID,
      fieldName: fieldName,
      relation: relation,
    )
    if nextOrder < .max {
      nextOrder += 1
    }

    if count < storage.count {
      let index = (oldestIndex + count) % storage.count
      storage[index] = entry
      count += 1
      return
    }

    storage[oldestIndex] = entry
    oldestIndex = (oldestIndex + 1) % storage.count
    if omittedEntryCount < .max {
      omittedEntryCount += 1
    }
  }

  mutating func reclassifyBeforeFirstAction(as action: UInt64) {
    for index in storage.indices {
      guard var entry = storage[index] else { continue }
      guard entry.relation == .beforeFirstAction else { continue }
      entry.relation = .beforeAction(action)
      storage[index] = entry
    }
  }

  mutating func reclassifyAfterAction(
    _ previous: UInt64,
    asBefore next: UInt64,
  ) {
    for index in storage.indices {
      guard var entry = storage[index] else { continue }
      guard entry.relation == .afterAction(previous) else { continue }
      entry.relation = .betweenActions(previous: previous, next: next)
      storage[index] = entry
    }
  }

  func snapshot() -> _OutsideWindowDiagnosticContextForProof {
    var entries = [_OutsideWindowMutationForProof]()
    entries.reserveCapacity(count)

    for offset in 0..<count {
      let index = (oldestIndex + offset) % storage.count
      guard let entry = storage[index] else { continue }
      entries.append(_OutsideWindowMutationForProof(
        order: entry.order,
        fieldID: entry.fieldID,
        fieldName: entry.fieldName,
        relation: entry.relation,
      ))
    }

    return _OutsideWindowDiagnosticContextForProof(
      entries: entries,
      omittedEntryCount: omittedEntryCount,
    )
  }

  mutating func removeAll() {
    for index in storage.indices {
      storage[index] = nil
    }
    oldestIndex = 0
    count = 0
    omittedEntryCount = 0
    nextOrder = 1
  }

  // MARK: Private

  private var storage: [OutsideWindowMutationEntry?]
  private var oldestIndex = 0
  private var nextOrder: UInt64 = 1

}
