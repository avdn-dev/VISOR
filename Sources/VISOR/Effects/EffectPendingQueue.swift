import Foundation

/// Keeps FIFO order while removing started and cancelled entries immediately.
/// Links use IDs so the queue has no reference cycles or retired entry prefix.
struct _EffectPendingQueue {

  // MARK: Internal

  var count: Int {
    entries.count
  }

  mutating func append(_ id: UUID) {
    precondition(entries[id] == nil, "An effect can only be queued once")
    entries[id] = Links(previous: lastID, next: nil)
    if let lastID {
      entries[lastID]?.next = id
    } else {
      firstID = id
    }
    lastID = id
  }

  mutating func popFirst() -> UUID? {
    guard let firstID else { return nil }
    remove(firstID)
    return firstID
  }

  mutating func remove(_ id: UUID) {
    guard let links = entries.removeValue(forKey: id) else { return }
    if let previous = links.previous {
      entries[previous]?.next = links.next
    } else {
      firstID = links.next
    }
    if let next = links.next {
      entries[next]?.previous = links.previous
    } else {
      lastID = links.previous
    }
  }

  // MARK: Private

  private struct Links {
    var previous: UUID?
    var next: UUID?
  }

  private var entries = [UUID: Links]()
  private var firstID: UUID?
  private var lastID: UUID?
}
