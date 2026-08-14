//
//  GenerateSpyMacroTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftSyntaxMacros
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let testMacros: [String: Macro.Type] = [
  "GenerateSpy": GenerateTestDoublesSpyMacro.self,
  "DefaultValue": DefaultValueMacro.self,
  "DefaultReturn": DefaultValueMacro.self,
]

// MARK: - GenerateSpyMacroTests

@Suite("GenerateSpy Macro")
struct GenerateSpyMacroTests {

  // MARK: - Spy Generation

  @Test
  func `Generates spy with properties and methods`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
        func save(_ item: Item) async throws
      }
      """,
      expandedSource: """
      protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
        func save(_ item: Item) async throws
      }

      @Observable
      final class SpyDataService: DataService {
        var items: [Item] = []
        // -- fetch --
        var fetchCallCount = 0
        var fetchResult: Result<[Item], any Error> = .success([])
        @ObservationIgnored
        var fetchImplementation: (() async throws -> [Item])?
        func fetch() async throws -> [Item] {
          fetchCallCount += 1
          calls.append(.fetch)
          if let fetchImplementation {
            return try await fetchImplementation()
          }
          return try fetchResult.get()
        }
        // -- save --
        var saveCallCount = 0
        var saveReceivedItem: Item?
        var saveReceivedInvocations: [Item] = []
        var saveResult: Result<Void, any Error> = .success(())
        @ObservationIgnored
        var saveImplementation: ((Item) async throws -> Void)?
        func save(_ item: Item) async throws {
          saveCallCount += 1
          saveReceivedItem = item
          saveReceivedInvocations.append(item)
          calls.append(.save(item: item))
          if let saveImplementation {
            try await saveImplementation(item)
            return
          }
          try saveResult.get()
        }
        enum Call {
          case fetch
          case save(item: Item)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Preserves typed throws in generated spy`() {
    assertMacroExpansionSwiftTesting(
      """
      enum OperationError: Error {
        case failed
      }
      enum FetchError: Error {
        case failed
      }

      @GenerateSpy
      protocol TypedThrowingService {
        func perform() throws(OperationError)
        @DefaultReturn("value") func fetchValue() async throws(FetchError) -> String
      }
      """,
      expandedSource: """
      enum OperationError: Error {
        case failed
      }
      enum FetchError: Error {
        case failed
      }
      protocol TypedThrowingService {
        func perform() throws(OperationError)
        func fetchValue() async throws(FetchError) -> String
      }

      @Observable
      final class SpyTypedThrowingService: TypedThrowingService {
        // -- perform --
        var performCallCount = 0
        var performResult: Result<Void, OperationError> = .success(())
        @ObservationIgnored
        var performImplementation: (() throws(OperationError) -> Void)?
        func perform() throws(OperationError) {
          performCallCount += 1
          calls.append(.perform)
          if let performImplementation {
            try performImplementation()
            return
          }
          try performResult.get()
        }
        // -- fetchValue --
        var fetchValueCallCount = 0
        var fetchValueResult: Result<String, FetchError> = .success("value")
        @ObservationIgnored
        var fetchValueImplementation: (() async throws(FetchError) -> String)?
        func fetchValue() async throws(FetchError) -> String {
          fetchValueCallCount += 1
          calls.append(.fetchValue)
          if let fetchValueImplementation {
            return try await fetchValueImplementation()
          }
          return try fetchValueResult.get()
        }
        enum Call {
          case perform
          case fetchValue
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for void methods`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol LogService {
        func log(message: String)
        func reset()
      }
      """,
      expandedSource: """
      protocol LogService {
        func log(message: String)
        func reset()
      }

      @Observable
      final class SpyLogService: LogService {
        // -- log --
        var logCallCount = 0
        var logReceivedMessage: String?
        var logReceivedInvocations: [String] = []
        @ObservationIgnored
        var logImplementation: ((String) -> Void)?
        func log(message: String) {
          logCallCount += 1
          logReceivedMessage = message
          logReceivedInvocations.append(message)
          calls.append(.log(message: message))
          logImplementation?(message)
        }
        // -- reset --
        var resetCallCount = 0
        @ObservationIgnored
        var resetImplementation: (() -> Void)?
        func reset() {
          resetCallCount += 1
          calls.append(.reset)
          resetImplementation?()
        }
        enum Call {
          case log(message: String)
          case reset
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy with multiple parameters`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [String]
      }
      """,
      expandedSource: """
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [String]
      }

      @Observable
      final class SpySearchService: SearchService {
        // -- search --
        var searchCallCount = 0
        var searchReceivedArguments: (query: String, limit: Int)?
        var searchReceivedInvocations: [(query: String, limit: Int)] = []
        var searchResult: Result<[String], any Error> = .success([])
        @ObservationIgnored
        var searchImplementation: ((String, Int) async throws -> [String])?
        func search(query: String, limit: Int) async throws -> [String] {
          searchCallCount += 1
          searchReceivedArguments = (query, limit)
          searchReceivedInvocations.append((query, limit))
          calls.append(.search(query: query, limit: limit))
          if let searchImplementation {
            return try await searchImplementation(query, limit)
          }
          return try searchResult.get()
        }
        enum Call {
          case search(query: String, limit: Int)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy with optional and fatalError for unknown return type`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ThemeService {
        func currentTheme() -> Theme
        @DefaultReturn(Theme.system) func preferredTheme() -> Theme
        @DefaultReturn(User.guest) func loadUser() throws -> User
      }
      """,
      expandedSource: """
      protocol ThemeService {
        func currentTheme() -> Theme
        func preferredTheme() -> Theme
        func loadUser() throws -> User
      }

      @Observable
      final class SpyThemeService: ThemeService {
        // -- currentTheme --
        var currentThemeCallCount = 0
        var currentThemeReturnValue: Theme?
        @ObservationIgnored
        var currentThemeImplementation: (() -> Theme)?
        func currentTheme() -> Theme {
          currentThemeCallCount += 1
          calls.append(.currentTheme)
          if let currentThemeImplementation {
            return currentThemeImplementation()
          }
          guard let value = currentThemeReturnValue else {
              fatalError("Configure currentThemeReturnValue before calling currentTheme()")
          }
          return value
        }
        // -- preferredTheme --
        var preferredThemeCallCount = 0
        var preferredThemeReturnValue: Theme = Theme.system
        @ObservationIgnored
        var preferredThemeImplementation: (() -> Theme)?
        func preferredTheme() -> Theme {
          preferredThemeCallCount += 1
          calls.append(.preferredTheme)
          if let preferredThemeImplementation {
            return preferredThemeImplementation()
          }
          return preferredThemeReturnValue
        }
        // -- loadUser --
        var loadUserCallCount = 0
        var loadUserResult: Result<User, any Error> = .success(User.guest)
        @ObservationIgnored
        var loadUserImplementation: (() throws -> User)?
        func loadUser() throws -> User {
          loadUserCallCount += 1
          calls.append(.loadUser)
          if let loadUserImplementation {
            return try loadUserImplementation()
          }
          return try loadUserResult.get()
        }
        enum Call {
          case currentTheme
          case preferredTheme
          case loadUser
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateSpy: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates spy for empty protocol`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol EmptyService {
      }
      """,
      expandedSource: """
      protocol EmptyService {
      }

      @Observable
      final class SpyEmptyService: EmptyService {

      }
      """,
      macros: testMacros)
  }

  @Test
  func `Uses IUO for unknown property types`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ThemeService {
        var currentTheme: Theme { get }
      }
      """,
      expandedSource: """
      protocol ThemeService {
        var currentTheme: Theme { get }
      }

      @Observable
      final class SpyThemeService: ThemeService {
        var currentTheme: Theme! = nil
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateSpy: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates spy with external label different from internal name`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ItemService {
        func perform(with item: Item) async throws
      }
      """,
      expandedSource: """
      protocol ItemService {
        func perform(with item: Item) async throws
      }

      @Observable
      final class SpyItemService: ItemService {
        // -- perform --
        var performCallCount = 0
        var performReceivedItem: Item?
        var performReceivedInvocations: [Item] = []
        var performResult: Result<Void, any Error> = .success(())
        @ObservationIgnored
        var performImplementation: ((Item) async throws -> Void)?
        func perform(with item: Item) async throws {
          performCallCount += 1
          performReceivedItem = item
          performReceivedInvocations.append(item)
          calls.append(.perform(item: item))
          if let performImplementation {
            try await performImplementation(item)
            return
          }
          try performResult.get()
        }
        enum Call {
          case perform(item: Item)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - Overloaded Methods

  @Test
  func `Disambiguates methods with same name but different labels`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol LoadService {
        func load(byId id: String) -> Item
        func load(matching query: String) -> [Item]
      }
      """,
      expandedSource: """
      protocol LoadService {
        func load(byId id: String) -> Item
        func load(matching query: String) -> [Item]
      }

      @Observable
      final class SpyLoadService: LoadService {
        // -- loadById --
        var loadByIdCallCount = 0
        var loadByIdReceivedId: String?
        var loadByIdReceivedInvocations: [String] = []
        var loadByIdReturnValue: Item?
        @ObservationIgnored
        var loadByIdImplementation: ((String) -> Item)?
        func load(byId id: String) -> Item {
          loadByIdCallCount += 1
          loadByIdReceivedId = id
          loadByIdReceivedInvocations.append(id)
          calls.append(.load(id: id))
          if let loadByIdImplementation {
            return loadByIdImplementation(id)
          }
          guard let value = loadByIdReturnValue else {
              fatalError("Configure loadByIdReturnValue before calling load()")
          }
          return value
        }
        // -- loadMatching --
        var loadMatchingCallCount = 0
        var loadMatchingReceivedQuery: String?
        var loadMatchingReceivedInvocations: [String] = []
        var loadMatchingReturnValue: [Item] = []
        @ObservationIgnored
        var loadMatchingImplementation: ((String) -> [Item])?
        func load(matching query: String) -> [Item] {
          loadMatchingCallCount += 1
          loadMatchingReceivedQuery = query
          loadMatchingReceivedInvocations.append(query)
          calls.append(.load(query: query))
          if let loadMatchingImplementation {
            return loadMatchingImplementation(query)
          }
          return loadMatchingReturnValue
        }
        enum Call {
          case load(id: String)
          case load(query: String)
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateSpy: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Non-colliding methods keep simple names alongside overloads`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol MixedService {
        func fetch() -> [Item]
        func send(event: String)
        func send(error: any Error)
      }
      """,
      expandedSource: """
      protocol MixedService {
        func fetch() -> [Item]
        func send(event: String)
        func send(error: any Error)
      }

      @Observable
      final class SpyMixedService: MixedService {
        // -- fetch --
        var fetchCallCount = 0
        var fetchReturnValue: [Item] = []
        @ObservationIgnored
        var fetchImplementation: (() -> [Item])?
        func fetch() -> [Item] {
          fetchCallCount += 1
          calls.append(.fetch)
          if let fetchImplementation {
            return fetchImplementation()
          }
          return fetchReturnValue
        }
        // -- sendEvent --
        var sendEventCallCount = 0
        var sendEventReceivedEvent: String?
        var sendEventReceivedInvocations: [String] = []
        @ObservationIgnored
        var sendEventImplementation: ((String) -> Void)?
        func send(event: String) {
          sendEventCallCount += 1
          sendEventReceivedEvent = event
          sendEventReceivedInvocations.append(event)
          calls.append(.send(event: event))
          sendEventImplementation?(event)
        }
        // -- sendError --
        var sendErrorCallCount = 0
        var sendErrorReceivedError: any Error?
        var sendErrorReceivedInvocations: [any Error] = []
        @ObservationIgnored
        var sendErrorImplementation: ((any Error) -> Void)?
        func send(error: any Error) {
          sendErrorCallCount += 1
          sendErrorReceivedError = error
          sendErrorReceivedInvocations.append(error)
          calls.append(.send(error: error))
          sendErrorImplementation?(error)
        }
        enum Call {
          case fetch
          case send(event: String)
          case send(error: any Error)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - Access Level Propagation

  @Test
  func `Public protocol generates public spy`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      public protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }
      """,
      expandedSource: """
      public protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }

      @Observable
      public final class SpyDataService: DataService {
        public var items: [Item] = []
        // -- fetch --
        public var fetchCallCount = 0
        public var fetchResult: Result<[Item], any Error> = .success([])
        @ObservationIgnored
        public var fetchImplementation: (() async throws -> [Item])?
        public func fetch() async throws -> [Item] {
          fetchCallCount += 1
          calls.append(.fetch)
          if let fetchImplementation {
            return try await fetchImplementation()
          }
          return try fetchResult.get()
        }
        public enum Call {
          case fetch
        }
        public var calls: [Call] = []
        public init() {
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Package protocol generates package spy`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      package protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }
      """,
      expandedSource: """
      package protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }

      @Observable
      package final class SpyDataService: DataService {
        package var items: [Item] = []
        // -- fetch --
        package var fetchCallCount = 0
        package var fetchResult: Result<[Item], any Error> = .success([])
        @ObservationIgnored
        package var fetchImplementation: (() async throws -> [Item])?
        package func fetch() async throws -> [Item] {
          fetchCallCount += 1
          calls.append(.fetch)
          if let fetchImplementation {
            return try await fetchImplementation()
          }
          return try fetchResult.get()
        }
        package enum Call {
          case fetch
        }
        package var calls: [Call] = []
        package init() {
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Fileprivate protocol generates fileprivate spy`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      fileprivate protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }
      """,
      expandedSource: """
      fileprivate protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }

      @Observable
      fileprivate final class SpyDataService: DataService {
        fileprivate var items: [Item] = []
        // -- fetch --
        fileprivate var fetchCallCount = 0
        fileprivate var fetchResult: Result<[Item], any Error> = .success([])
        @ObservationIgnored
        fileprivate var fetchImplementation: (() async throws -> [Item])?
        fileprivate func fetch() async throws -> [Item] {
          fetchCallCount += 1
          calls.append(.fetch)
          if let fetchImplementation {
            return try await fetchImplementation()
          }
          return try fetchResult.get()
        }
        fileprivate enum Call {
          case fetch
        }
        fileprivate var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Private protocol generates private spy`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      private protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }
      """,
      expandedSource: """
      private protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
      }

      @Observable
      private final class SpyDataService: DataService {
        private var items: [Item] = []
        // -- fetch --
        private var fetchCallCount = 0
        private var fetchResult: Result<[Item], any Error> = .success([])
        @ObservationIgnored
        private var fetchImplementation: (() async throws -> [Item])?
        private func fetch() async throws -> [Item] {
          fetchCallCount += 1
          calls.append(.fetch)
          if let fetchImplementation {
            return try await fetchImplementation()
          }
          return try fetchResult.get()
        }
        private enum Call {
          case fetch
        }
        private var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - @DefaultValue

  @Test
  func `Spy property with DefaultValue uses custom default`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ExtractionService {
        @DefaultValue(ExtractionStatus.idle) var status: ExtractionStatus { get }
        var count: Int { get }
        func reset()
      }
      """,
      expandedSource: """
      protocol ExtractionService {
        var status: ExtractionStatus { get }
        var count: Int { get }
        func reset()
      }

      @Observable
      final class SpyExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
        var count: Int = 0
        // -- reset --
        var resetCallCount = 0
        @ObservationIgnored
        var resetImplementation: (() -> Void)?
        func reset() {
          resetCallCount += 1
          calls.append(.reset)
          resetImplementation?()
        }
        enum Call {
          case reset
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - Properties-only Protocol

  @Test
  func `Properties-only protocol generates spy without Call enum`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ConfigService {
        var apiKey: String { get }
        var isEnabled: Bool { get }
      }
      """,
      expandedSource: """
      protocol ConfigService {
        var apiKey: String { get }
        var isEnabled: Bool { get }
      }

      @Observable
      final class SpyConfigService: ConfigService {
        var apiKey: String = ""
        var isEnabled: Bool = false
      }
      """,
      macros: testMacros)
  }

  // MARK: - Generic Types

  @Test
  func `Generates spy with generic return type`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ResultService {
        func execute() -> Result<String, any Error>
      }
      """,
      expandedSource: """
      protocol ResultService {
        func execute() -> Result<String, any Error>
      }

      @Observable
      final class SpyResultService: ResultService {
        // -- execute --
        var executeCallCount = 0
        var executeReturnValue: Result<String, any Error>?
        @ObservationIgnored
        var executeImplementation: (() -> Result<String, any Error>)?
        func execute() -> Result<String, any Error> {
          executeCallCount += 1
          calls.append(.execute)
          if let executeImplementation {
            return executeImplementation()
          }
          guard let value = executeReturnValue else {
              fatalError("Configure executeReturnValue before calling execute()")
          }
          return value
        }
        enum Call {
          case execute
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateSpy: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates spy with generic parameter type`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol BatchService {
        func process(_ batch: Set<String>)
      }
      """,
      expandedSource: """
      protocol BatchService {
        func process(_ batch: Set<String>)
      }

      @Observable
      final class SpyBatchService: BatchService {
        // -- process --
        var processCallCount = 0
        var processReceivedBatch: Set<String>?
        var processReceivedInvocations: [Set<String>] = []
        @ObservationIgnored
        var processImplementation: ((Set<String>) -> Void)?
        func process(_ batch: Set<String>) {
          processCallCount += 1
          processReceivedBatch = batch
          processReceivedInvocations.append(batch)
          calls.append(.process(batch: batch))
          processImplementation?(batch)
        }
        enum Call {
          case process(batch: Set<String>)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for generic rethrowing method`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol WorkRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T
      }
      """,
      expandedSource: """
      protocol WorkRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T
      }

      @Observable
      final class SpyWorkRunner: WorkRunner {
        // -- run --
        var runCallCount = 0
        var runReceivedName: String?
        var runReceivedInvocations: [String] = []
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
          runCallCount += 1
          runReceivedName = name
          runReceivedInvocations.append(name)
          calls.append(.run(name: name))
          return try await body()
        }
        enum Call {
          case run(name: String)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for generic rethrowing method with where clause`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ConstrainedRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T where T: Sendable
      }
      """,
      expandedSource: """
      protocol ConstrainedRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T where T: Sendable
      }

      @Observable
      final class SpyConstrainedRunner: ConstrainedRunner {
        // -- run --
        var runCallCount = 0
        var runReceivedName: String?
        var runReceivedInvocations: [String] = []
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T where T: Sendable {
          runCallCount += 1
          runReceivedName = name
          runReceivedInvocations.append(name)
          calls.append(.run(name: name))
          return try await body()
        }
        enum Call {
          case run(name: String)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for method generic argument storage`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol GenericSink {
        func consume<T>(_ value: T, tag: String)
      }
      """,
      expandedSource: """
      protocol GenericSink {
        func consume<T>(_ value: T, tag: String)
      }

      @Observable
      final class SpyGenericSink: GenericSink {
        // -- consume --
        var consumeCallCount = 0
        var consumeReceivedArguments: (value: Any, tag: String)?
        var consumeReceivedInvocations: [(value: Any, tag: String)] = []
        func consume<T>(_ value: T, tag: String) {
          consumeCallCount += 1
          consumeReceivedArguments = (value, tag)
          consumeReceivedInvocations.append((value, tag))
          calls.append(.consume(value: value, tag: tag))
        }
        enum Call {
          case consume(value: Any, tag: String)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for rethrowing void method`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol VoidRunner {
        func run(_ body: () throws -> Void) rethrows
      }
      """,
      expandedSource: """
      protocol VoidRunner {
        func run(_ body: () throws -> Void) rethrows
      }

      @Observable
      final class SpyVoidRunner: VoidRunner {
        // -- run --
        var runCallCount = 0
        func run(_ body: () throws -> Void) rethrows {
          runCallCount += 1
          calls.append(.run)
          try body()
        }
        enum Call {
          case run
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - Diagnostics

  @Test
  func `Error when applied to struct`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      struct NotAProtocol {
      }
      """,
      expandedSource: """
      struct NotAProtocol {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateSpy can only be applied to protocols", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when applied to class`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      class NotAProtocol {
      }
      """,
      expandedSource: """
      class NotAProtocol {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateSpy can only be applied to protocols", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error on protocol with associated types`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol HasAssoc {
        associatedtype Item
        func fetch() -> [Item]
      }
      """,
      expandedSource: """
      protocol HasAssoc {
        associatedtype Item
        func fetch() -> [Item]
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateSpy does not support protocols with associated types", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error on protocol with static members`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol HasStatic {
        static var shared: String { get }
        func doWork()
      }
      """,
      expandedSource: """
      protocol HasStatic {
        static var shared: String { get }
        func doWork()
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateSpy does not support static or class requirements", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error on protocol with subscripts`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol HasSubscript {
        var name: String { get }
        subscript(index: Int) -> String { get }
      }
      """,
      expandedSource: """
      protocol HasSubscript {
        var name: String { get }
        subscript(index: Int) -> String { get }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateSpy does not support subscript requirements", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }
  
  // MARK: - Typealias
  
  @Test
  func `Single typealias`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol FooService {
        typealias Foo = String
        func processFoo(_ foo: Foo) -> Foo
      }
      """,
      expandedSource: """
      protocol FooService {
        typealias Foo = String
        func processFoo(_ foo: Foo) -> Foo
      }

      @Observable
      final class SpyFooService: FooService {
        // -- processFoo --
        var processFooCallCount = 0
        var processFooReceivedFoo: FooService.Foo?
        var processFooReceivedInvocations: [FooService.Foo] = []
        var processFooReturnValue: FooService.Foo?
        @ObservationIgnored
        var processFooImplementation: ((FooService.Foo) -> FooService.Foo)?
        func processFoo(_ foo: FooService.Foo) -> FooService.Foo {
          processFooCallCount += 1
          processFooReceivedFoo = foo
          processFooReceivedInvocations.append(foo)
          calls.append(.processFoo(foo: foo))
          if let processFooImplementation {
            return processFooImplementation(foo)
          }
          guard let value = processFooReturnValue else {
              fatalError("Configure processFooReturnValue before calling processFoo()")
          }
          return value
        }
        enum Call {
          case processFoo(foo: FooService.Foo)
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        .init(
          message:
            """
            @GenerateSpy: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. \
            Use @DefaultValue for properties or @DefaultReturn for method returns.
            """,
          line: 1,
          column: 1,
          severity: .note)
      ],
      macros: testMacros)
  }

  // MARK: - Implementation Closures

  @Test
  func `Generates implementation closure for sync throwing void`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol SaveService {
        func save(_ item: Item) throws
      }
      """,
      expandedSource: """
      protocol SaveService {
        func save(_ item: Item) throws
      }

      @Observable
      final class SpySaveService: SaveService {
        // -- save --
        var saveCallCount = 0
        var saveReceivedItem: Item?
        var saveReceivedInvocations: [Item] = []
        var saveResult: Result<Void, any Error> = .success(())
        @ObservationIgnored
        var saveImplementation: ((Item) throws -> Void)?
        func save(_ item: Item) throws {
          saveCallCount += 1
          saveReceivedItem = item
          saveReceivedInvocations.append(item)
          calls.append(.save(item: item))
          if let saveImplementation {
            try saveImplementation(item)
            return
          }
          try saveResult.get()
        }
        enum Call {
          case save(item: Item)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates implementation closure for async non-throwing void`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol RefreshService {
        func refresh() async
      }
      """,
      expandedSource: """
      protocol RefreshService {
        func refresh() async
      }

      @Observable
      final class SpyRefreshService: RefreshService {
        // -- refresh --
        var refreshCallCount = 0
        @ObservationIgnored
        var refreshImplementation: (() async -> Void)?
        func refresh() async {
          refreshCallCount += 1
          calls.append(.refresh)
          if let refreshImplementation {
            await refreshImplementation()
            return
          }
        }
        enum Call {
          case refresh
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Implementation closure records before delegating`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol MotionService {
        func waitForFirstData(timeout: Duration) async -> Bool
      }
      """,
      expandedSource: """
      protocol MotionService {
        func waitForFirstData(timeout: Duration) async -> Bool
      }

      @Observable
      final class SpyMotionService: MotionService {
        // -- waitForFirstData --
        var waitForFirstDataCallCount = 0
        var waitForFirstDataReceivedTimeout: Duration?
        var waitForFirstDataReceivedInvocations: [Duration] = []
        var waitForFirstDataReturnValue: Bool = false
        @ObservationIgnored
        var waitForFirstDataImplementation: ((Duration) async -> Bool)?
        func waitForFirstData(timeout: Duration) async -> Bool {
          waitForFirstDataCallCount += 1
          waitForFirstDataReceivedTimeout = timeout
          waitForFirstDataReceivedInvocations.append(timeout)
          calls.append(.waitForFirstData(timeout: timeout))
          if let waitForFirstDataImplementation {
            return await waitForFirstDataImplementation(timeout)
          }
          return waitForFirstDataReturnValue
        }
        enum Call {
          case waitForFirstData(timeout: Duration)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Implementation closure for async throwing returning with multiple params`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [Result]
      }
      """,
      expandedSource: """
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [Result]
      }

      @Observable
      final class SpySearchService: SearchService {
        // -- search --
        var searchCallCount = 0
        var searchReceivedArguments: (query: String, limit: Int)?
        var searchReceivedInvocations: [(query: String, limit: Int)] = []
        var searchResult: Result<[Result], any Error> = .success([])
        @ObservationIgnored
        var searchImplementation: ((String, Int) async throws -> [Result])?
        func search(query: String, limit: Int) async throws -> [Result] {
          searchCallCount += 1
          searchReceivedArguments = (query, limit)
          searchReceivedInvocations.append((query, limit))
          calls.append(.search(query: query, limit: limit))
          if let searchImplementation {
            return try await searchImplementation(query, limit)
          }
          return try searchResult.get()
        }
        enum Call {
          case search(query: String, limit: Int)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - Collision Detection

  @Test
  func `Renames implementation closure when name collides with protocol property`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol CollisionService {
        func fetch() -> Item
        var fetchImplementation: Bool { get }
      }
      """,
      expandedSource: """
      protocol CollisionService {
        func fetch() -> Item
        var fetchImplementation: Bool { get }
      }

      @Observable
      final class SpyCollisionService: CollisionService {
        var fetchImplementation: Bool = false
        // -- fetch --
        var fetchCallCount = 0
        var fetchReturnValue: Item?
        @ObservationIgnored
        var fetchImplementationClosure: (() -> Item)?
        func fetch() -> Item {
          fetchCallCount += 1
          calls.append(.fetch)
          if let fetchImplementationClosure {
            return fetchImplementationClosure()
          }
          guard let value = fetchReturnValue else {
              fatalError("Configure fetchReturnValue before calling fetch()")
          }
          return value
        }
        enum Call {
          case fetch
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateSpy: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
        DiagnosticSpec(message: "@GenerateSpy: 'fetchImplementation' collides with an existing protocol member; using 'fetchImplementationClosure' for the generated implementation closure for 'fetch()'.", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Renames implementation closure when name collides with protocol method`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol CollisionService {
        func reset()
        func resetImplementation()
      }
      """,
      expandedSource: """
      protocol CollisionService {
        func reset()
        func resetImplementation()
      }

      @Observable
      final class SpyCollisionService: CollisionService {
        // -- reset --
        var resetCallCount = 0
        @ObservationIgnored
        var resetImplementationClosure: (() -> Void)?
        func reset() {
          resetCallCount += 1
          calls.append(.reset)
          resetImplementationClosure?()
        }
        // -- resetImplementation --
        var resetImplementationCallCount = 0
        @ObservationIgnored
        var resetImplementationImplementation: (() -> Void)?
        func resetImplementation() {
          resetImplementationCallCount += 1
          calls.append(.resetImplementation)
          resetImplementationImplementation?()
        }
        enum Call {
          case reset
          case resetImplementation
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateSpy: 'resetImplementation' collides with an existing protocol member; using 'resetImplementationClosure' for the generated implementation closure for 'reset()'.", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - Escaping Closures

  @Test
  func `Strips escaping from implementation closure and Call enum but preserves in signature`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol CallbackService {
        func register(_ callback: @escaping (String) -> Void)
      }
      """,
      expandedSource: """
      protocol CallbackService {
        func register(_ callback: @escaping (String) -> Void)
      }

      @Observable
      final class SpyCallbackService: CallbackService {
        // -- register --
        var registerCallCount = 0
        @ObservationIgnored
        var registerReceivedCallback: ((String) -> Void)?
        @ObservationIgnored
        var registerReceivedInvocations: [((String) -> Void)] = []
        @ObservationIgnored
        var registerImplementation: (((String) -> Void) -> Void)?
        func register(_ callback: @escaping (String) -> Void) {
          registerCallCount += 1
          registerReceivedCallback = callback
          registerReceivedInvocations.append(callback)
          calls.append(.register(callback: callback))
          registerImplementation?(callback)
        }
        enum Call {
          case register(callback: (String) -> Void)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Strips escaping but preserves Sendable in implementation closure and Call enum`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol HandlerService {
        func handle(_ completion: @escaping @Sendable (String) -> Void)
      }
      """,
      expandedSource: """
      protocol HandlerService {
        func handle(_ completion: @escaping @Sendable (String) -> Void)
      }

      @Observable
      final class SpyHandlerService: HandlerService {
        // -- handle --
        var handleCallCount = 0
        @ObservationIgnored
        var handleReceivedCompletion: (@Sendable (String) -> Void)?
        @ObservationIgnored
        var handleReceivedInvocations: [(@Sendable (String) -> Void)] = []
        @ObservationIgnored
        var handleImplementation: ((@Sendable (String) -> Void) -> Void)?
        func handle(_ completion: @escaping @Sendable (String) -> Void) {
          handleCallCount += 1
          handleReceivedCompletion = completion
          handleReceivedInvocations.append(completion)
          calls.append(.handle(completion: completion))
          handleImplementation?(completion)
        }
        enum Call {
          case handle(completion: @Sendable (String) -> Void)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - Inout Parameters

  @Test
  func `Generates spy for method with single inout parameter`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol MigratorService {
        func registerMigrations(migrator: inout DatabaseMigrator)
      }
      """,
      expandedSource: """
      protocol MigratorService {
        func registerMigrations(migrator: inout DatabaseMigrator)
      }

      @Observable
      final class SpyMigratorService: MigratorService {
        // -- registerMigrations --
        var registerMigrationsCallCount = 0
        @ObservationIgnored
        var registerMigrationsImplementation: ((inout DatabaseMigrator) -> Void)?
        func registerMigrations(migrator: inout DatabaseMigrator) {
          registerMigrationsCallCount += 1
          calls.append(.registerMigrations(migrator: migrator))
          registerMigrationsImplementation?(&migrator)
        }
        enum Call {
          case registerMigrations(migrator: DatabaseMigrator)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for method mixing inout and regular parameters`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol ProcessorService {
        func process(name: String, output: inout String)
      }
      """,
      expandedSource: """
      protocol ProcessorService {
        func process(name: String, output: inout String)
      }

      @Observable
      final class SpyProcessorService: ProcessorService {
        // -- process --
        var processCallCount = 0
        var processReceivedName: String?
        var processReceivedInvocations: [String] = []
        @ObservationIgnored
        var processImplementation: ((String, inout String) -> Void)?
        func process(name: String, output: inout String) {
          processCallCount += 1
          processReceivedName = name
          processReceivedInvocations.append(name)
          calls.append(.process(name: name, output: output))
          processImplementation?(name, &output)
        }
        enum Call {
          case process(name: String, output: String)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for method with only inout parameters in multi-param`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol SwapperService {
        func swap(a: inout Int, b: inout Int)
      }
      """,
      expandedSource: """
      protocol SwapperService {
        func swap(a: inout Int, b: inout Int)
      }

      @Observable
      final class SpySwapperService: SwapperService {
        // -- swap --
        var swapCallCount = 0
        @ObservationIgnored
        var swapImplementation: ((inout Int, inout Int) -> Void)?
        func swap(a: inout Int, b: inout Int) {
          swapCallCount += 1
          calls.append(.swap(a: a, b: b))
          swapImplementation?(&a, &b)
        }
        enum Call {
          case swap(a: Int, b: Int)
        }
        var calls: [Call] = []
      }
      """,
      macros: testMacros)
  }

  // MARK: - Sendable Generation

  @Test
  func `Generates lock-backed Sendable spy`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy(.sendable)
      nonisolated protocol EventRecorder: Sendable {
        func record(_ value: Int)
      }
      """,
      expandedSource: """
      nonisolated protocol EventRecorder: Sendable {
        func record(_ value: Int)
      }

      @Observable
      nonisolated final class SpyEventRecorder: EventRecorder, Sendable {
        private struct _Storage: Sendable {
          var recordCallCount: Int = 0
          var recordReceivedValue: Int? = nil
          var recordReceivedInvocations: [Int] = []
          var recordImplementation: (@Sendable (Int) -> Void)? = nil
          var calls: [Call] = []
        }
        @ObservationIgnored
        private let _testDoubleStorage = VISORTestDoubles._TestDoubleStorage(_Storage())
        var recordCallCount: Int {
          get {
            access(keyPath: \\.recordCallCount)
            return _testDoubleStorage.withValue {
                $0.recordCallCount
            }
          }
          set {
            withMutation(keyPath: \\.recordCallCount) {
              _testDoubleStorage.withValue {
                  $0.recordCallCount = newValue
              }
            }
          }
        }
        var recordReceivedValue: Int? {
          get {
            access(keyPath: \\.recordReceivedValue)
            return _testDoubleStorage.withValue {
                $0.recordReceivedValue
            }
          }
          set {
            withMutation(keyPath: \\.recordReceivedValue) {
              _testDoubleStorage.withValue {
                  $0.recordReceivedValue = newValue
              }
            }
          }
        }
        var recordReceivedInvocations: [Int] {
          get {
            access(keyPath: \\.recordReceivedInvocations)
            return _testDoubleStorage.withValue {
                $0.recordReceivedInvocations
            }
          }
          set {
            withMutation(keyPath: \\.recordReceivedInvocations) {
              _testDoubleStorage.withValue {
                  $0.recordReceivedInvocations = newValue
              }
            }
          }
        }
        var recordImplementation: (@Sendable (Int) -> Void)? {
          get {
            return _testDoubleStorage.withValue {
                $0.recordImplementation
            }
          }
          set {
            _testDoubleStorage.withValue {
                $0.recordImplementation = newValue
            }
          }
        }
        var calls: [Call] {
          get {
            access(keyPath: \\.calls)
            return _testDoubleStorage.withValue {
                $0.calls
            }
          }
          set {
            withMutation(keyPath: \\.calls) {
              _testDoubleStorage.withValue {
                  $0.calls = newValue
              }
            }
          }
        }
        func record(_ value: Int) {
          let recordImplementation = withMutation(keyPath: \\.recordCallCount) {
            withMutation(keyPath: \\.recordReceivedValue) {
              withMutation(keyPath: \\.recordReceivedInvocations) {
                withMutation(keyPath: \\.calls) {
                  _testDoubleStorage.withValue { state in
                    state.recordCallCount += 1
                    state.recordReceivedValue = value
                    state.recordReceivedInvocations.append(value)
                    state.calls.append(.record(value: value))
                    return state.recordImplementation
                  }
                }
              }
            }
          }
          recordImplementation?(value)
        }
        enum Call: Sendable {
          case record(value: Int)
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Sendable spy preserves concurrent typed throws and inout snapshots`() {
    assertMacroExpansionSwiftTesting(
      """
      enum WorkError: Error {
        case failed
      }

      @GenerateSpy(.sendable)
      protocol Worker: Sendable {
        @DefaultReturn("done")
        @concurrent func work(value: inout Int) async throws(WorkError) -> String
      }
      """,
      expandedSource: """
      enum WorkError: Error {
        case failed
      }
      protocol Worker: Sendable {
        @concurrent func work(value: inout Int) async throws(WorkError) -> String
      }

      @Observable
      nonisolated final class SpyWorker: Worker, Sendable {
        private struct _Storage: Sendable {
          var workCallCount: Int = 0
          var workResult: Result<String, WorkError> = .success("done")
          var workImplementation: (@Sendable (inout Int) async throws(WorkError) -> String)? = nil
          var calls: [Call] = []
        }
        @ObservationIgnored
        private let _testDoubleStorage = VISORTestDoubles._TestDoubleStorage(_Storage())
        var workCallCount: Int {
          get {
            access(keyPath: \\.workCallCount)
            return _testDoubleStorage.withValue {
                $0.workCallCount
            }
          }
          set {
            withMutation(keyPath: \\.workCallCount) {
              _testDoubleStorage.withValue {
                  $0.workCallCount = newValue
              }
            }
          }
        }
        var workResult: Result<String, WorkError> {
          get {
            access(keyPath: \\.workResult)
            return _testDoubleStorage.withValue {
                $0.workResult
            }
          }
          set {
            withMutation(keyPath: \\.workResult) {
              _testDoubleStorage.withValue {
                  $0.workResult = newValue
              }
            }
          }
        }
        var workImplementation: (@Sendable (inout Int) async throws(WorkError) -> String)? {
          get {
            return _testDoubleStorage.withValue {
                $0.workImplementation
            }
          }
          set {
            _testDoubleStorage.withValue {
                $0.workImplementation = newValue
            }
          }
        }
        var calls: [Call] {
          get {
            access(keyPath: \\.calls)
            return _testDoubleStorage.withValue {
                $0.calls
            }
          }
          set {
            withMutation(keyPath: \\.calls) {
              _testDoubleStorage.withValue {
                  $0.calls = newValue
              }
            }
          }
        }
        @concurrent
        func work(value: inout Int) async throws(WorkError) -> String {
          let _visorValueSnapshot = value
          let (workImplementation, workResult) = withMutation(keyPath: \\.workCallCount) {
            withMutation(keyPath: \\.calls) {
              _testDoubleStorage.withValue { state in
                state.workCallCount += 1
                state.calls.append(.work(value: _visorValueSnapshot))
                return (state.workImplementation, state.workResult)
              }
            }
          }
          if let workImplementation {
            return try await workImplementation(&value)
          }
          return try workResult.get()
        }
        enum Call: Sendable {
          case work(value: Int)
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Rejects unconstrained generic values requiring Sendable spy storage`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy(.sendable)
      protocol GenericService: Sendable {
        func consume<T>(_ value: T)
      }
      """,
      expandedSource: """
      protocol GenericService: Sendable {
        func consume<T>(_ value: T)
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateSpy(.sendable) cannot record unconstrained generic value 'T' in 'consume()'; constrain it to Sendable",
          line: 1,
          column: 1,
          severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Sendable spies erase constrained generic arguments to any Sendable`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy(.sendable)
      protocol GenericService: Sendable {
        func consume<T: Sendable>(_ value: T)
      }
      """,
      expandedSource: """
      protocol GenericService: Sendable {
        func consume<T: Sendable>(_ value: T)
      }

      @Observable
      nonisolated final class SpyGenericService: GenericService, Sendable {
        private struct _Storage: Sendable {
          var consumeCallCount: Int = 0
          var consumeReceivedValue: (any Sendable)? = nil
          var consumeReceivedInvocations: [(any Sendable)] = []
          var calls: [Call] = []
        }
        @ObservationIgnored
        private let _testDoubleStorage = VISORTestDoubles._TestDoubleStorage(_Storage())
        var consumeCallCount: Int {
          get {
            access(keyPath: \\.consumeCallCount)
            return _testDoubleStorage.withValue {
                $0.consumeCallCount
            }
          }
          set {
            withMutation(keyPath: \\.consumeCallCount) {
              _testDoubleStorage.withValue {
                  $0.consumeCallCount = newValue
              }
            }
          }
        }
        var consumeReceivedValue: (any Sendable)? {
          get {
            access(keyPath: \\.consumeReceivedValue)
            return _testDoubleStorage.withValue {
                $0.consumeReceivedValue
            }
          }
          set {
            withMutation(keyPath: \\.consumeReceivedValue) {
              _testDoubleStorage.withValue {
                  $0.consumeReceivedValue = newValue
              }
            }
          }
        }
        var consumeReceivedInvocations: [(any Sendable)] {
          get {
            access(keyPath: \\.consumeReceivedInvocations)
            return _testDoubleStorage.withValue {
                $0.consumeReceivedInvocations
            }
          }
          set {
            withMutation(keyPath: \\.consumeReceivedInvocations) {
              _testDoubleStorage.withValue {
                  $0.consumeReceivedInvocations = newValue
              }
            }
          }
        }
        var calls: [Call] {
          get {
            access(keyPath: \\.calls)
            return _testDoubleStorage.withValue {
                $0.calls
            }
          }
          set {
            withMutation(keyPath: \\.calls) {
              _testDoubleStorage.withValue {
                  $0.calls = newValue
              }
            }
          }
        }
        func consume<T: Sendable>(_ value: T) {
          withMutation(keyPath: \\.consumeCallCount) {
            withMutation(keyPath: \\.consumeReceivedValue) {
              withMutation(keyPath: \\.consumeReceivedInvocations) {
                withMutation(keyPath: \\.calls) {
                  _testDoubleStorage.withValue { state in
                    state.consumeCallCount += 1
                    state.consumeReceivedValue = value
                    state.consumeReceivedInvocations.append(value)
                    state.calls.append(.consume(value: value))
                  }
                }
              }
            }
          }
        }
        enum Call: Sendable {
          case consume(value: any Sendable)
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Rejects duplicate Sendable traits`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy(.sendable, .sendable)
      protocol Service {}
      """,
      expandedSource: """
      protocol Service {}
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateSpy received duplicate '.sendable' traits",
          line: 1,
          column: 25,
          severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Rejects unsupported test double traits`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy(.observable)
      protocol Service {}
      """,
      expandedSource: """
      protocol Service {}
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateSpy does not support the 'observable' trait",
          line: 1,
          column: 14,
          severity: .error),
      ],
      macros: testMacros)
  }

}

#endif
