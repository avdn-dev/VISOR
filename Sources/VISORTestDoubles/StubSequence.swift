package nonisolated enum StubSequenceDiagnostics {
  package static func exhaustedMessage<Value>(for valueType: Value.Type) -> String {
    "StubSequence<\(String(reflecting: valueType))> exhausted. Add another value before calling next()."
  }
}

/// A value-semantic queue of deterministic return values for a generated stub.
///
/// Values are stored in reverse order once and removed with `popLast()`, so
/// each call to ``next(file:line:)`` is amortised O(1).
public nonisolated struct StubSequence<Value> {
  private var remainingValues: [Value]

  /// Creates a sequence from values returned in array order.
  ///
  /// - Parameter values: The complete ordered set of stub return values.
  public init(_ values: [Value]) {
    remainingValues = Array(values.reversed())
  }

  /// Creates a non-empty sequence from variadic values.
  ///
  /// - Parameters:
  ///   - first: The first value returned.
  ///   - rest: The remaining values, in return order.
  public init(_ first: Value, _ rest: Value...) {
    remainingValues = Array(rest.reversed())
    remainingValues.append(first)
  }

  /// Whether every configured value has been consumed.
  public var isEmpty: Bool {
    remainingValues.isEmpty
  }

  /// The number of values that have not yet been consumed.
  public var remainingCount: Int {
    remainingValues.count
  }

  /// Removes and returns the next configured value.
  ///
  /// Exhaustion is a test-configuration error and fails immediately with a
  /// diagnostic naming `Value` and the call site.
  ///
  /// - Parameters:
  ///   - file: The source file reported if the sequence is exhausted.
  ///   - line: The source line reported if the sequence is exhausted.
  /// - Returns: The next configured value.
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
