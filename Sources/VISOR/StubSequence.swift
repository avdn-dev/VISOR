public nonisolated struct StubSequence<Value> {
   private var values: [Value]

   public init(_ values: [Value]) {
      self.values = values
   }

   public init(_ first: Value, _ rest: Value...) {
      self.values = [first] + rest
   }

   public var isEmpty: Bool {
      values.isEmpty
   }

   public var remainingCount: Int {
      values.count
   }

   public mutating func next(
      file: StaticString = #filePath,
      line: UInt = #line)
      -> Value
   {
      guard !values.isEmpty else {
         fatalError("StubSequence exhausted", file: (file), line: line)
      }
      return values.removeFirst()
   }
}
