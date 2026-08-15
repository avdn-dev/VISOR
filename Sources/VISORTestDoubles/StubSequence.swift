package nonisolated enum StubSequenceDiagnostics {
  package static func exhaustedMessage<Value>(for valueType: Value.Type) -> String {
    "StubSequence<\(String(reflecting: valueType))> exhausted. Add another value before calling next()."
  }
}

public nonisolated struct StubSequence<Value> {
  private var remainingValues: [Value]

  public init(_ values: [Value]) {
    remainingValues = Array(values.reversed())
  }

  public init(_ first: Value, _ rest: Value...) {
    remainingValues = Array(rest.reversed())
    remainingValues.append(first)
  }

  public var isEmpty: Bool {
    remainingValues.isEmpty
  }

  public var remainingCount: Int {
    remainingValues.count
  }

  public mutating func next(
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> Value {
    guard let value = remainingValues.popLast() else {
      fatalError(
        StubSequenceDiagnostics.exhaustedMessage(for: Value.self),
        file: (file),
        line: line)
    }
    return value
  }
}
