//
//  GenerateStubMacroTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftSyntaxMacros
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let testMacros: [String: Macro.Type] = [
  "GenerateStub": GenerateStubMacro.self,
  "DefaultValue": DefaultValueMacro.self,
  "DefaultReturn": DefaultValueMacro.self,
]

private let defaultValueWarning = """
  @GenerateStub: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. \
  Use @DefaultValue for properties or @DefaultReturn for method returns.
  """

// MARK: - GenerateStubMacroTests

@Suite("GenerateStub Macro")
struct GenerateStubMacroTests {

  // MARK: - Protocol Stub Generation

  @Test
  func `Generates stub with properties and methods`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol DataService {
        var items: [Item] { get }
        var isLoading: Bool { get set }
        func fetch() async throws -> [Item]
        func save(_ item: Item) async throws
      }
      """,
      expandedSource: """
      protocol DataService {
        var items: [Item] { get }
        var isLoading: Bool { get set }
        func fetch() async throws -> [Item]
        func save(_ item: Item) async throws
      }

      @Observable
      final class StubDataService: DataService {
        var items: [Item] = []
        var isLoading: Bool = false
        var fetchResult: Result<[Item], any Error> = .success([])
        func fetch() async throws -> [Item] {
            try fetchResult.get()
        }
        var saveResult: Result<Void, any Error> = .success(())
        func save(_ item: Item) async throws {
            try saveResult.get()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Preserves typed throws in generated stub`() {
    assertMacroExpansionSwiftTesting(
      """
      enum OperationError: Error {
        case failed
      }
      enum FetchError: Error {
        case failed
      }

      @GenerateStub
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
      final class StubTypedThrowingService: TypedThrowingService {
        var performResult: Result<Void, OperationError> = .success(())
        func perform() throws(OperationError) {
            try performResult.get()
        }
        var fetchValueResult: Result<String, FetchError> = .success("value")
        func fetchValue() async throws(FetchError) -> String {
            try fetchValueResult.get()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub with default values for known types`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ConfigService {
        var name: String { get }
        var count: Int { get }
        var rate: Double { get }
        var isEnabled: Bool { get }
        var data: Data { get }
        var tags: [String] { get }
        var mapping: [String: Int] { get }
        var optional: String? { get }
      }
      """,
      expandedSource: """
      protocol ConfigService {
        var name: String { get }
        var count: Int { get }
        var rate: Double { get }
        var isEnabled: Bool { get }
        var data: Data { get }
        var tags: [String] { get }
        var mapping: [String: Int] { get }
        var optional: String? { get }
      }

      @Observable
      final class StubConfigService: ConfigService {
        var name: String = ""
        var count: Int = 0
        var rate: Double = 0.0
        var isEnabled: Bool = false
        var data: Data = Data()
        var tags: [String] = []
        var mapping: [String: Int] = [:]
        var optional: String? = nil
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Uses optional with fatalError for unknown custom return types`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      final class StubThemeService: ThemeService {
        var currentThemeReturnValue: Theme?
        func currentTheme() -> Theme {
          guard let value = currentThemeReturnValue else {
              fatalError("Configure currentThemeReturnValue before calling currentTheme()")
          }
          return value
        }
        var preferredThemeReturnValue: Theme = Theme.system
        func preferredTheme() -> Theme {
            preferredThemeReturnValue
        }
        var loadUserResult: Result<User, any Error> = .success(User.guest)
        func loadUser() throws -> User {
            try loadUserResult.get()
        }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateStub: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates stub for empty protocol`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol EmptyService {
      }
      """,
      expandedSource: """
      protocol EmptyService {
      }

      @Observable
      final class StubEmptyService: EmptyService {

      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub with labelled parameters`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [Result]
      }
      """,
      expandedSource: """
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [Result]
      }

      @Observable
      final class StubSearchService: SearchService {
        var searchResult: Result<[Result], any Error> = .success([])
        func search(query: String, limit: Int) async throws -> [Result] {
            try searchResult.get()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub with optional return type`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol CacheService {
        func get(key: String) -> Data?
      }
      """,
      expandedSource: """
      protocol CacheService {
        func get(key: String) -> Data?
      }

      @Observable
      final class StubCacheService: CacheService {
        var getReturnValue: Data? = nil
        func get(key: String) -> Data? {
            getReturnValue
        }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Access Level Propagation

  @Test
  func `Public protocol generates public stub`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      public protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
        func save(_ item: Item) async throws
      }
      """,
      expandedSource: """
      public protocol DataService {
        var items: [Item] { get }
        func fetch() async throws -> [Item]
        func save(_ item: Item) async throws
      }

      @Observable
      public final class StubDataService: DataService {
        public var items: [Item] = []
        public var fetchResult: Result<[Item], any Error> = .success([])
        public func fetch() async throws -> [Item] {
            try fetchResult.get()
        }
        public var saveResult: Result<Void, any Error> = .success(())
        public func save(_ item: Item) async throws {
            try saveResult.get()
        }
        public init() {
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Package protocol generates package stub`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      package final class StubDataService: DataService {
        package var items: [Item] = []
        package var fetchResult: Result<[Item], any Error> = .success([])
        package func fetch() async throws -> [Item] {
            try fetchResult.get()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Fileprivate protocol generates fileprivate stub`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      fileprivate final class StubDataService: DataService {
        fileprivate var items: [Item] = []
        fileprivate var fetchResult: Result<[Item], any Error> = .success([])
        fileprivate func fetch() async throws -> [Item] {
            try fetchResult.get()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Private protocol generates private stub`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      private final class StubDataService: DataService {
        private var items: [Item] = []
        private var fetchResult: Result<[Item], any Error> = .success([])
        private func fetch() async throws -> [Item] {
            try fetchResult.get()
        }
      }
      """,
      macros: testMacros)
  }

  // MARK: - @DefaultValue

  @Test
  func `Property with DefaultValue uses custom default`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ExtractionService {
        @DefaultValue(ExtractionStatus.idle) var status: ExtractionStatus { get }
      }
      """,
      expandedSource: """
      protocol ExtractionService {
        var status: ExtractionStatus { get }
      }

      @Observable
      final class StubExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Property without DefaultValue uses defaultValue as before`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ExtractionService {
        var count: Int { get }
        var theme: Theme { get }
      }
      """,
      expandedSource: """
      protocol ExtractionService {
        var count: Int { get }
        var theme: Theme { get }
      }

      @Observable
      final class StubExtractionService: ExtractionService {
        var count: Int = 0
        var theme: Theme! = nil
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateStub: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Mixed properties with and without DefaultValue`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ExtractionService {
        @DefaultValue(ExtractionStatus.idle) var status: ExtractionStatus { get }
        var count: Int { get }
        var name: String { get }
      }
      """,
      expandedSource: """
      protocol ExtractionService {
        var status: ExtractionStatus { get }
        var count: Int { get }
        var name: String { get }
      }

      @Observable
      final class StubExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
        var count: Int = 0
        var name: String = ""
      }
      """,
      macros: testMacros)
  }

  @Test
  func `AsyncStream property gets default`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol StreamService {
        var updates: AsyncStream<Int> { get }
      }
      """,
      expandedSource: """
      protocol StreamService {
        var updates: AsyncStream<Int> { get }
      }

      @Observable
      final class StubStreamService: StreamService {
        var updates: AsyncStream<Int> = AsyncStream {
            $0.finish()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Set property gets empty default`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol TagService {
        var tags: Set<String> { get }
      }
      """,
      expandedSource: """
      protocol TagService {
        var tags: Set<String> { get }
      }

      @Observable
      final class StubTagService: TagService {
        var tags: Set<String> = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Method with external label different from internal name`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ItemService {
        func perform(with item: Item) async throws
      }
      """,
      expandedSource: """
      protocol ItemService {
        func perform(with item: Item) async throws
      }

      @Observable
      final class StubItemService: ItemService {
        var performResult: Result<Void, any Error> = .success(())
        func perform(with item: Item) async throws {
            try performResult.get()
        }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Overloaded Methods

  @Test
  func `Disambiguates methods with same name but different labels`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      final class StubLoadService: LoadService {
        var loadByIdReturnValue: Item?
        func load(byId id: String) -> Item {
          guard let value = loadByIdReturnValue else {
              fatalError("Configure loadByIdReturnValue before calling load()")
          }
          return value
        }
        var loadMatchingReturnValue: [Item] = []
        func load(matching query: String) -> [Item] {
            loadMatchingReturnValue
        }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateStub: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Disambiguates void overloads`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol EventService {
        func send(event: String)
        func send(error: any Error)
      }
      """,
      expandedSource: """
      protocol EventService {
        func send(event: String)
        func send(error: any Error)
      }

      @Observable
      final class StubEventService: EventService {
        func send(event: String) {
        }
        func send(error: any Error) {
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Disambiguates overload with underscore label using type name`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol Finder {
        func find(_ expected: Item) -> Bool
        func find(byID id: String) -> Bool
      }
      """,
      expandedSource: """
      protocol Finder {
        func find(_ expected: Item) -> Bool
        func find(byID id: String) -> Bool
      }

      @Observable
      final class StubFinder: Finder {
        var findItemReturnValue: Bool = false
        func find(_ expected: Item) -> Bool {
            findItemReturnValue
        }
        var findByIDReturnValue: Bool = false
        func find(byID id: String) -> Bool {
            findByIDReturnValue
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Disambiguates overloads with same labels but different return types`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol Converter {
        func convert(from value: String) -> Int
        func convert(from value: String) -> Double
      }
      """,
      expandedSource: """
      protocol Converter {
        func convert(from value: String) -> Int
        func convert(from value: String) -> Double
      }

      @Observable
      final class StubConverter: Converter {
        var convertFromReturningIntReturnValue: Int = 0
        func convert(from value: String) -> Int {
            convertFromReturningIntReturnValue
        }
        var convertFromReturningDoubleReturnValue: Double = 0.0
        func convert(from value: String) -> Double {
            convertFromReturningDoubleReturnValue
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Non-colliding methods keep simple names`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol MixedService {
        func fetch() -> [Item]
        func save(_ item: Item)
        func delete(byId id: String)
      }
      """,
      expandedSource: """
      protocol MixedService {
        func fetch() -> [Item]
        func save(_ item: Item)
        func delete(byId id: String)
      }

      @Observable
      final class StubMixedService: MixedService {
        var fetchReturnValue: [Item] = []
        func fetch() -> [Item] {
            fetchReturnValue
        }
        func save(_ item: Item) {
        }
        func delete(byId id: String) {
        }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Generic Types

  @Test
  func `Generates stub with generic return type`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ResultService {
        func execute() -> Result<String, any Error>
      }
      """,
      expandedSource: """
      protocol ResultService {
        func execute() -> Result<String, any Error>
      }

      @Observable
      final class StubResultService: ResultService {
        var executeReturnValue: Result<String, any Error>?
        func execute() -> Result<String, any Error> {
          guard let value = executeReturnValue else {
              fatalError("Configure executeReturnValue before calling execute()")
          }
          return value
        }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateStub: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates stub with generic parameter type`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol StorageService {
        func store(_ value: Set<String>)
        func retrieve() -> [String: [Int]]
      }
      """,
      expandedSource: """
      protocol StorageService {
        func store(_ value: Set<String>)
        func retrieve() -> [String: [Int]]
      }

      @Observable
      final class StubStorageService: StorageService {
        func store(_ value: Set<String>) {
        }
        var retrieveReturnValue: [String: [Int]] = [:]
        func retrieve() -> [String: [Int]] {
            retrieveReturnValue
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Disambiguates overloads with generic underscore parameter types`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol Processor {
        func process(_ items: Set<String>) -> Int
        func process(_ items: Array<Int>) -> Int
      }
      """,
      expandedSource: """
      protocol Processor {
        func process(_ items: Set<String>) -> Int
        func process(_ items: Array<Int>) -> Int
      }

      @Observable
      final class StubProcessor: Processor {
        var processSetStringReturnValue: Int = 0
        func process(_ items: Set<String>) -> Int {
            processSetStringReturnValue
        }
        var processArrayIntReturnValue: Int = 0
        func process(_ items: Array<Int>) -> Int {
            processArrayIntReturnValue
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generic property types use correct defaults`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol CacheService {
        var entries: Dictionary<String, Int> { get }
        var pending: Set<String> { get }
        var result: Result<String, any Error> { get }
      }
      """,
      expandedSource: """
      protocol CacheService {
        var entries: Dictionary<String, Int> { get }
        var pending: Set<String> { get }
        var result: Result<String, any Error> { get }
      }

      @Observable
      final class StubCacheService: CacheService {
        var entries: Dictionary<String, Int> = [:]
        var pending: Set<String> = []
        var result: Result<String, any Error>! = nil
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: #"@GenerateStub: Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."#, line: 1, column: 1, severity: .note),
      ],
      macros: testMacros)
  }

  @Test
  func `Generates stub for generic rethrowing method`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol WorkRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T
      }
      """,
      expandedSource: """
      protocol WorkRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T
      }

      @Observable
      final class StubWorkRunner: WorkRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
            return try await body()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub for generic rethrowing method with where clause`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ConstrainedRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T where T: Sendable
      }
      """,
      expandedSource: """
      protocol ConstrainedRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T where T: Sendable
      }

      @Observable
      final class StubConstrainedRunner: ConstrainedRunner {
        func run<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T where T: Sendable {
            return try await body()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub for rethrowing void method`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol VoidRunner {
        func run(_ body: () throws -> Void) rethrows
      }
      """,
      expandedSource: """
      protocol VoidRunner {
        func run(_ body: () throws -> Void) rethrows
      }

      @Observable
      final class StubVoidRunner: VoidRunner {
        func run(_ body: () throws -> Void) rethrows {
            try body()
        }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Diagnostics

  @Test
  func `Error when applied to struct`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      struct NotValid {
      }
      """,
      expandedSource: """
      struct NotValid {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateStub can only be applied to protocols", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error on protocol with associated types`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
        DiagnosticSpec(message: "@GenerateStub does not support protocols with associated types", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning on protocol with static members`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      final class StubHasStatic: HasStatic {
        func doWork() {
        }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateStub skips static members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning on protocol with subscripts`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      final class StubHasSubscript: HasSubscript {
        var name: String = ""
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@GenerateStub skips subscript members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }
  
  // MARK: - Typealias
  
  @Test
  func `Single typealias used in function`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
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
      final class StubFooService: FooService {
        var processFooReturnValue: FooService.Foo?
        func processFoo(_ foo: FooService.Foo) -> FooService.Foo {
          guard let value = processFooReturnValue else {
              fatalError("Configure processFooReturnValue before calling processFoo()")
          }
          return value
        }
      }
      """,
      diagnostics: [
        .init(
          message: defaultValueWarning,
          line: 1,
          column: 1,
          severity: .note)
      ],
      macros: testMacros)
  }
  
}

@Test
func `Single typealias used in property`() {
  assertMacroExpansionSwiftTesting(
    """
    @GenerateStub
    protocol BarService {
      typealias Bar = Int
      @DefaultValue(0)
      var bar: Bar { get }
    }
    """,
    expandedSource: """
    protocol BarService {
      typealias Bar = Int
      var bar: Bar { get }
    }
    
    @Observable
    final class StubBarService: BarService {
      var bar: BarService.Bar = 0
    }
    """,
    macros: testMacros)
}

@Test
func `Generic typealias used in property`() {
  assertMacroExpansionSwiftTesting(
    """
    enum FooError: Swift.Error { }
    
    @GenerateStub
    protocol BazService {
      typealias Value = Int
      typealias ErrorType = FooError
    
      var result: Result<Value, ErrorType> { get }
    }
    """,
    expandedSource: """
    enum FooError: Swift.Error { }
    protocol BazService {
      typealias Value = Int
      typealias ErrorType = FooError
    
      var result: Result<Value, ErrorType> { get }
    }
    
    @Observable
    final class StubBazService: BazService {
      var result: Result<BazService.Value, BazService.ErrorType>! = nil
    }
    """,
    diagnostics: [
      .init(message: defaultValueWarning, line: 3, column: 1, severity: .note)
    ],
    macros: testMacros)
}

@Test
func `Multiple typealiases used in method signature`() {
  assertMacroExpansionSwiftTesting(
    """
    @GenerateStub
    protocol SpamService {
      typealias Foo = Int
      typealias Bar = String
      typealias Baz = [Int]
    
      func perform(_ foo: Foo, bar: Bar) async throws -> Baz
    }
    """,
    expandedSource: """
    protocol SpamService {
      typealias Foo = Int
      typealias Bar = String
      typealias Baz = [Int]
    
      func perform(_ foo: Foo, bar: Bar) async throws -> Baz
    }
    
    @Observable
    final class StubSpamService: SpamService {
      var performResult: Result<SpamService.Baz, any Error>?
      func perform(_ foo: SpamService.Foo, bar: SpamService.Bar) async throws -> SpamService.Baz {
        guard let result = performResult else {
            fatalError("Configure performResult before calling perform()")
        }
        return try result.get()
      }
    }
    """,
    diagnostics: [
      .init(message: defaultValueWarning, line: 1, column: 1, severity: .note)
    ],
    macros: testMacros)
}

@Test
func `Handle nested typealiases`() {
  assertMacroExpansionSwiftTesting(
    """
    @GenerateStub
    protocol EggsService {
      typealias Foo = String
      typealias Bar = Int
    
      var foo: Foo { get }
      var fooArray: [Foo] { get }
      var fooDictionary: [Foo : Bar] { get }
    
      var everything: Dictionary<[Set<Foo> : [Bar]], Array<[Set<Foo>]>> { get }
    }
    """,
    expandedSource: """
    protocol EggsService {
      typealias Foo = String
      typealias Bar = Int
    
      var foo: Foo { get }
      var fooArray: [Foo] { get }
      var fooDictionary: [Foo : Bar] { get }
    
      var everything: Dictionary<[Set<Foo> : [Bar]], Array<[Set<Foo>]>> { get }
    }
    
    @Observable
    final class StubEggsService: EggsService {
      var foo: EggsService.Foo! = nil
      var fooArray: [EggsService.Foo] = []
      var fooDictionary: [EggsService.Foo : EggsService.Bar] = [:]
      var everything: Dictionary<[Set<EggsService.Foo> : [EggsService.Bar]], Array<[Set<EggsService.Foo>]>> = [:]
    }
    """,
    diagnostics: [
      .init(message: defaultValueWarning, line: 1, column: 1, severity: .note)
    ],
    macros: testMacros)
}

@Test
func `Handle function property typealiases`() {
  assertMacroExpansionSwiftTesting(
    """
    @GenerateStub
    protocol FooFactoryProvider {
      typealias Foo = Int
      typealias Bar = Int
    
      @DefaultValue({ (_: FooFactoryProvider.Foo) -> FooFactoryProvider.Bar in 0 })
      var fooFactory: (Foo) -> Bar { get }
    }
    """,
    expandedSource: """
    protocol FooFactoryProvider {
      typealias Foo = Int
      typealias Bar = Int
      var fooFactory: (Foo) -> Bar { get }
    }
    
    @Observable
    final class StubFooFactoryProvider: FooFactoryProvider {
      var fooFactory: (FooFactoryProvider.Foo) -> FooFactoryProvider.Bar = { (_: FooFactoryProvider.Foo) -> FooFactoryProvider.Bar in
          0
      }
    }
    """,
    macros: testMacros)
}

@Test
func `Handle typealias in attributed use site`() {
  assertMacroExpansionSwiftTesting(
    """
    @GenerateStub
    protocol BarService {
      typealias Bar = String
      func bar(_ bar: sending Bar)
    }
    """,
    expandedSource: """
    protocol BarService {
      typealias Bar = String
      func bar(_ bar: sending Bar)
    }
    
    @Observable
    final class StubBarService: BarService {
      func bar(_ bar: sending BarService.Bar) {
      }
    }
    """,
    macros: testMacros)
}

  // MARK: - Escaping Closures

  @Test
  func `Preserves escaping in method signature for stub`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol CallbackService {
        func register(_ callback: @escaping (String) -> Void)
      }
      """,
      expandedSource: """
      protocol CallbackService {
        func register(_ callback: @escaping (String) -> Void)
      }

      @Observable
      final class StubCallbackService: CallbackService {
        func register(_ callback: @escaping (String) -> Void) {
        }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Sendable Generation

  @Test
  func `Generates lock-backed public Sendable stub with typed throws`() {
    assertMacroExpansionSwiftTesting(
      """
      enum LoadError: Error {
        case failed
      }

      @GenerateStub(.sendable)
      public protocol Loader: Sendable {
        var isEnabled: Bool { get set }
        @DefaultReturn("loaded")
        func load() throws(LoadError) -> String
      }
      """,
      expandedSource: """
      enum LoadError: Error {
        case failed
      }
      public protocol Loader: Sendable {
        var isEnabled: Bool { get set }
        func load() throws(LoadError) -> String
      }

      @Observable
      nonisolated public final class StubLoader: Loader, Sendable {
        private struct _Storage: Sendable {
          var isEnabled: Bool = false
          var loadResult: Result<String, LoadError> = .success("loaded")
        }
        @ObservationIgnored
        private let _testDoubleStorage = VISOR._TestDoubleStorage(_Storage())
        public var isEnabled: Bool {
          get {
            access(keyPath: \\.isEnabled)
            return _testDoubleStorage.withValue {
                $0.isEnabled
            }
          }
          set {
            withMutation(keyPath: \\.isEnabled) {
              _testDoubleStorage.withValue {
                  $0.isEnabled = newValue
              }
            }
          }
        }
        public var loadResult: Result<String, LoadError> {
          get {
            access(keyPath: \\.loadResult)
            return _testDoubleStorage.withValue {
                $0.loadResult
            }
          }
          set {
            withMutation(keyPath: \\.loadResult) {
              _testDoubleStorage.withValue {
                  $0.loadResult = newValue
              }
            }
          }
        }
        public func load() throws(LoadError) -> String {
          let loadResult = _testDoubleStorage.withValue {
              $0.loadResult
          }
          return try loadResult.get()
        }
        public init() {
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Sendable stubs retain generic rethrowing methods without generic storage`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub(.sendable)
      protocol WorkRunner: Sendable {
        @concurrent
        func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T
      }
      """,
      expandedSource: """
      protocol WorkRunner: Sendable {
        @concurrent
        func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T
      }

      @Observable
      nonisolated final class StubWorkRunner: WorkRunner, Sendable {
        private struct _Storage: Sendable {
        }
        @ObservationIgnored
        private let _testDoubleStorage = VISOR._TestDoubleStorage(_Storage())
        @concurrent
        func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
          return try await operation()
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Sendable stubs disambiguate overloaded return storage`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub(.sendable)
      protocol Converter: Sendable {
        func convert(text: String) -> Int
        func convert(number: Int) -> String
      }
      """,
      expandedSource: """
      protocol Converter: Sendable {
        func convert(text: String) -> Int
        func convert(number: Int) -> String
      }

      @Observable
      nonisolated final class StubConverter: Converter, Sendable {
        private struct _Storage: Sendable {
          var convertTextReturnValue: Int = 0
          var convertNumberReturnValue: String = ""
        }
        @ObservationIgnored
        private let _testDoubleStorage = VISOR._TestDoubleStorage(_Storage())
        var convertTextReturnValue: Int {
          get {
            access(keyPath: \\.convertTextReturnValue)
            return _testDoubleStorage.withValue {
                $0.convertTextReturnValue
            }
          }
          set {
            withMutation(keyPath: \\.convertTextReturnValue) {
              _testDoubleStorage.withValue {
                  $0.convertTextReturnValue = newValue
              }
            }
          }
        }
        var convertNumberReturnValue: String {
          get {
            access(keyPath: \\.convertNumberReturnValue)
            return _testDoubleStorage.withValue {
                $0.convertNumberReturnValue
            }
          }
          set {
            withMutation(keyPath: \\.convertNumberReturnValue) {
              _testDoubleStorage.withValue {
                  $0.convertNumberReturnValue = newValue
              }
            }
          }
        }
        func convert(text: String) -> Int {
          let convertTextReturnValue = _testDoubleStorage.withValue {
              $0.convertTextReturnValue
          }
          return convertTextReturnValue
        }
        func convert(number: Int) -> String {
          let convertNumberReturnValue = _testDoubleStorage.withValue {
              $0.convertNumberReturnValue
          }
          return convertNumberReturnValue
        }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Sendable package stubs expose a package initialiser`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub(.sendable)
      package nonisolated protocol PackageService: Sendable {}
      """,
      expandedSource: """
      package nonisolated protocol PackageService: Sendable {}

      @Observable
      nonisolated package final class StubPackageService: PackageService, Sendable {
        private struct _Storage: Sendable {
        }
        @ObservationIgnored
        private let _testDoubleStorage = VISOR._TestDoubleStorage(_Storage())
        package init() {
        }
      }
      """,
      macros: testMacros)
  }

#endif
