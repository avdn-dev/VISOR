package nonisolated enum StubSequenceDiagnostics {
  package static func exhaustedMessage<Value>(for valueType: Value.Type) -> String {
    "StubSequence<\(String(reflecting: valueType))> exhausted. Add another value before calling next()."
  }
}

public nonisolated struct StubSequence<Value> {
  private var values: [Value]

  public init(_ values: [Value]) {
    self.values = values
  }

  public init(_ first: Value, _ rest: Value...) {
    values = [first] + rest
  }

  public var isEmpty: Bool {
    values.isEmpty
  }

  public var remainingCount: Int {
    values.count
  }

  public mutating func next(
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> Value {
    guard !values.isEmpty else {
      fatalError(
        StubSequenceDiagnostics.exhaustedMessage(for: Value.self),
        file: (file),
        line: line)
    }
    return values.removeFirst()
  }
}
