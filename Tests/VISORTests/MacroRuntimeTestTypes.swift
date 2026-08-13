import Foundation
import VISORTestDoubles

// MARK: - Test-double macro runtime fixtures

@GenerateStub
protocol ItemService {
  var items: [String] { get }
  var count: Int { get }

  @DefaultReturn(["default"])
  func fetchItems() async throws -> [String]

  func save(_ item: String) async throws
}

@GenerateStub
protocol RuntimeStubWorkRunner {
  func run<T>(
    _ name: String,
    _ body: () async throws -> T
  ) async rethrows -> T where T: Sendable
}

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendableStubService: Sendable {
  var value: Int { get set }

  @DefaultReturn(0)
  func load() -> Int
}

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendableWorkRunner: Sendable {
  @concurrent
  func run<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async rethrows -> T
}

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendingReturnService: Sendable {
  func message() -> sending String
}

@GenerateSpy
protocol AnalyticsService {
  func trackEvent(_ name: String)
  func trackScreen(name: String, category: String)

  @DefaultReturn("default report")
  func fetchReport() async throws -> String
}

@GenerateSpy
protocol GreeterService {
  func greet(_ name: String) -> String
  func reset()
}

@GenerateSpy
protocol CallbackService {
  func register(_ callback: @escaping (String) -> Void)
}

@GenerateSpy
protocol InoutService {
  func update(value: inout Int)
}

@GenerateSpy
protocol MixedInoutService {
  func process(name: String, output: inout String)
}

@GenerateSpy
protocol RuntimeWorkRunner {
  func run<T>(
    _ name: String,
    _ body: () async throws -> T
  ) async rethrows -> T
}

@GenerateSpy
protocol RuntimeGenericSink {
  func consume<T>(_ value: T, tag: String)
}

@GenerateSpy(.sendable)
nonisolated protocol RuntimeSendableSpyService: Sendable {
  @DefaultReturn(0)
  @concurrent
  func record(_ value: Int) async -> Int
}

nonisolated final class RuntimeReentrantRetirementValue: Sendable {
  let onDeinit: @Sendable () -> Void

  init(onDeinit: @escaping @Sendable () -> Void) {
    self.onDeinit = onDeinit
  }

  deinit {
    onDeinit()
  }
}

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendableRetirementService: Sendable {
  var value: RuntimeReentrantRetirementValue? { get set }
}

@GenerateSpy(.sendable)
nonisolated protocol RuntimeSendableGenericSpyService: Sendable {
  func consume<T: Sendable & Equatable>(_ value: T, tag: String)
  func consumeWhere<T>(_ value: T) where T: Sendable
  func perform<T>(_ operation: () -> T)
}

@GenerateSpy(.sendable)
nonisolated protocol RuntimeOwnershipSpyService: Sendable {
  func receiveSending(_ value: sending String)
  func receiveConsuming(_ value: consuming String)
  func receiveBorrowing(_ value: borrowing String)
}

@GenerateSpy
protocol RuntimeVoidRunner {
  func run(_ body: () throws -> Void) rethrows
}

enum RuntimeOperationError: Error, Equatable {
  case failed
}

enum RuntimeFetchError: Error, Equatable {
  case failed
}

@GenerateStub
@GenerateSpy
protocol RuntimeTypedThrowingService {
  func perform() throws(RuntimeOperationError)

  @DefaultReturn("default value")
  func fetchValue() async throws(RuntimeFetchError) -> String
}
