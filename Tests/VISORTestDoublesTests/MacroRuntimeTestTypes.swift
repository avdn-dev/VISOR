import Foundation
import VISORTestDoubles

// MARK: - ItemService

@GenerateStub
protocol ItemService {
  var items: [String] { get }
  var count: Int { get }

  @DefaultReturn(["default"])
  func fetchItems() async throws -> [String]

  func save(_ item: String) async throws
}

// MARK: - RuntimeStubWorkRunner

@GenerateStub
protocol RuntimeStubWorkRunner {
  func run<T: Sendable>(
    _ name: String,
    _ body: () async throws -> T,
  ) async rethrows -> T
}

// MARK: - RuntimeSendableStubService

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendableStubService: Sendable {
  var value: Int { get set }

  @DefaultReturn(0)
  func load() -> Int
}

// MARK: - RuntimeSendableWorkRunner

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendableWorkRunner: Sendable {
  @concurrent
  func run<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async rethrows -> T
}

// MARK: - RuntimeSendingReturnService

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendingReturnService: Sendable {
  func message() -> sending String
}

// MARK: - AnalyticsService

@GenerateSpy
protocol AnalyticsService {
  func trackEvent(_ name: String)
  func trackScreen(name: String, category: String)

  @DefaultReturn("default report")
  func fetchReport() async throws -> String
}

// MARK: - GreeterService

@GenerateSpy
protocol GreeterService {
  func greet(_ name: String) -> String
  func reset()
}

// MARK: - CallbackService

@GenerateSpy
protocol CallbackService {
  func register(_ callback: @escaping (String) -> Void)
}

// MARK: - InoutService

@GenerateSpy
protocol InoutService {
  func update(value: inout Int)
}

// MARK: - MixedInoutService

@GenerateSpy
protocol MixedInoutService {
  func process(name: String, output: inout String)
}

// MARK: - RuntimeWorkRunner

@GenerateSpy
protocol RuntimeWorkRunner {
  func run<T>(
    _ name: String,
    _ body: () async throws -> T,
  ) async rethrows -> T
}

// MARK: - RuntimeGenericSink

@GenerateSpy
protocol RuntimeGenericSink {
  func consume<T>(_ value: T, tag: String)
}

// MARK: - RuntimeSendableSpyService

@GenerateSpy(.sendable)
nonisolated protocol RuntimeSendableSpyService: Sendable {
  @DefaultReturn(0)
  @concurrent
  func record(_ value: Int) async -> Int
}

// MARK: - RuntimeReentrantRetirementValue

nonisolated final class RuntimeReentrantRetirementValue: Sendable {

  // MARK: Lifecycle

  init(onDeinit: @escaping @Sendable () -> Void) {
    self.onDeinit = onDeinit
  }

  deinit {
    onDeinit()
  }

  // MARK: Internal

  let onDeinit: @Sendable () -> Void

}

// MARK: - RuntimeSendableRetirementService

@GenerateStub(.sendable)
nonisolated protocol RuntimeSendableRetirementService: Sendable {
  var value: RuntimeReentrantRetirementValue? { get set }
}

// MARK: - RuntimeSendableGenericSpyService

@GenerateSpy(.sendable)
nonisolated protocol RuntimeSendableGenericSpyService: Sendable {
  // Named generics are macro input; `some` would change generated storage types.
  // swiftformat:disable opaqueGenericParameters
  func consume<T: Sendable & Equatable>(_ value: T, tag: String)
  func consumeWhere<T: Sendable>(_ value: T)
  // swiftformat:enable opaqueGenericParameters
  func perform<T>(_ operation: () -> T)
}

// MARK: - RuntimeOwnershipSpyService

@GenerateSpy(.sendable)
nonisolated protocol RuntimeOwnershipSpyService: Sendable {
  func receiveSending(_ value: sending String)
  func receiveConsuming(_ value: consuming String)
  func receiveBorrowing(_ value: borrowing String)
}

// MARK: - RuntimeVoidRunner

@GenerateSpy
protocol RuntimeVoidRunner {
  func run(_ body: () throws -> Void) rethrows
}

// MARK: - RuntimeOperationError

enum RuntimeOperationError: Error, Equatable {
  case failed
}

// MARK: - RuntimeFetchError

enum RuntimeFetchError: Error, Equatable {
  case failed
}

// MARK: - RuntimeTypedThrowingService

@GenerateStub
@GenerateSpy
protocol RuntimeTypedThrowingService {
  func perform() throws(RuntimeOperationError)

  @DefaultReturn("default value")
  func fetchValue() async throws(RuntimeFetchError) -> String
}
