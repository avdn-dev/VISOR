//
//  SpyableMacroTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftSyntaxMacros
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let testMacros: [String: Macro.Type] = [
  "Spyable": SpyableMacro.self,
  "StubbableDefault": StubbableDefaultMacro.self,
]

// MARK: - SpyableMacroTests

@Suite("Spyable Macro")
struct SpyableMacroTests {

  // MARK: - Spy Generation

  @Test
  func `Generates spy with properties and methods`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
  func `Generates spy for void methods`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
      @Spyable
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
      @Spyable
      protocol ThemeService {
        func currentTheme() -> Theme
      }
      """,
      expandedSource: """
      protocol ThemeService {
        func currentTheme() -> Theme
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
              fatalError("Configure \\(String(describing: currentThemeReturnValue)) before calling currentTheme()")
          }
          return value
        }
        enum Call {
          case currentTheme
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@Spyable: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @StubbableDefault to provide explicit defaults."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates spy for empty protocol`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
      @Spyable
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
        DiagnosticSpec(message: #"@Spyable: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @StubbableDefault to provide explicit defaults."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates spy with external label different from internal name`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
      @Spyable
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
              fatalError("Configure \\(String(describing: loadByIdReturnValue)) before calling load()")
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
        DiagnosticSpec(message: #"@Spyable: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @StubbableDefault to provide explicit defaults."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Non-colliding methods keep simple names alongside overloads`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
      @Spyable
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
      @Spyable
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
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Fileprivate protocol generates fileprivate spy`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
      @Spyable
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

  // MARK: - @StubbableDefault

  @Test
  func `Spy property with StubbableDefault uses custom default`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
      protocol ExtractionService {
        @StubbableDefault(ExtractionStatus.idle) var status: ExtractionStatus { get }
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
      @Spyable
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
      @Spyable
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
              fatalError("Configure \\(String(describing: executeReturnValue)) before calling execute()")
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
        DiagnosticSpec(message: #"@Spyable: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @StubbableDefault to provide explicit defaults."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates spy with generic parameter type`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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

  // MARK: - Diagnostics

  @Test
  func `Error when applied to struct`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
      struct NotAProtocol {
      }
      """,
      expandedSource: """
      struct NotAProtocol {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Spyable can only be applied to protocols", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when applied to class`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
      class NotAProtocol {
      }
      """,
      expandedSource: """
      class NotAProtocol {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Spyable can only be applied to protocols", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error on protocol with associated types`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
        DiagnosticSpec(message: "@Spyable does not support protocols with associated types", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning on protocol with static members`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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

      @Observable
      final class SpyHasStatic: HasStatic {
        // -- doWork --
        var doWorkCallCount = 0
        @ObservationIgnored
        var doWorkImplementation: (() -> Void)?
        func doWork() {
          doWorkCallCount += 1
          calls.append(.doWork)
          doWorkImplementation?()
        }
        enum Call {
          case doWork
        }
        var calls: [Call] = []
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Spyable skips static members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning on protocol with subscripts`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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

      @Observable
      final class SpyHasSubscript: HasSubscript {
        var name: String = ""
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Spyable skips subscript members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }
  
  // MARK: - Typealias
  
  @Test
  func `Single typealias`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
              fatalError("Configure \\(String(describing: processFooReturnValue)) before calling processFoo()")
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
            @Spyable: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. \
            Use @StubbableDefault to provide explicit defaults.
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
      @Spyable
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
      @Spyable
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
      @Spyable
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
      @Spyable
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
      @Spyable
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
              fatalError("Configure \\(String(describing: fetchReturnValue)) before calling fetch()")
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
        DiagnosticSpec(message: #"@Spyable: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @StubbableDefault to provide explicit defaults."#, line: 1, column: 1, severity: .note),
        DiagnosticSpec(message: "@Spyable: 'fetchImplementation' collides with an existing protocol member; using 'fetchImplementationClosure' for the generated implementation closure for 'fetch()'.", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Renames implementation closure when name collides with protocol method`() {
    assertMacroExpansionSwiftTesting(
      """
      @Spyable
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
        DiagnosticSpec(message: "@Spyable: 'resetImplementation' collides with an existing protocol member; using 'resetImplementationClosure' for the generated implementation closure for 'reset()'.", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

}
#endif
