//
//  StubbableMacroTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let testMacros: [String: Macro.Type] = [
  "Stubbable": StubbableMacro.self,
  "StubbableDefault": StubbableDefaultMacro.self,
]

// MARK: - StubbableMacroTests

@Suite("Stubbable Macro")
struct StubbableMacroTests {

  // MARK: - Protocol Stub Generation

  @Test
  func `Generates stub with properties and methods`() {
    assertMacroExpansion(
      """
      @Stubbable
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
      class StubDataService: DataService {
        var items: [Item] = []
        var isLoading: Bool = false
        var fetchReturnValue: [Item] = []
        func fetch() async throws -> [Item] { fetchReturnValue }
        func save(_ item: Item) async throws { }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub with default values for known types`() {
    assertMacroExpansion(
      """
      @Stubbable
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
      class StubConfigService: ConfigService {
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
  func `Uses IUO for unknown custom types`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol ThemeService {
        func currentTheme() -> Theme
      }
      """,
      expandedSource: """
      protocol ThemeService {
        func currentTheme() -> Theme
      }

      @Observable
      class StubThemeService: ThemeService {
        var currentThemeReturnValue: Theme!
        func currentTheme() -> Theme { currentThemeReturnValue }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub for empty protocol`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol EmptyService {
      }
      """,
      expandedSource: """
      protocol EmptyService {
      }

      @Observable
      class StubEmptyService: EmptyService {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub with labeled parameters`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [Result]
      }
      """,
      expandedSource: """
      protocol SearchService {
        func search(query: String, limit: Int) async throws -> [Result]
      }

      @Observable
      class StubSearchService: SearchService {
        var searchReturnValue: [Result] = []
        func search(query: String, limit: Int) async throws -> [Result] { searchReturnValue }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Generates stub with optional return type`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol CacheService {
        func get(key: String) -> Data?
      }
      """,
      expandedSource: """
      protocol CacheService {
        func get(key: String) -> Data?
      }

      @Observable
      class StubCacheService: CacheService {
        var getReturnValue: Data? = nil
        func get(key: String) -> Data? { getReturnValue }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Access Level Propagation

  @Test
  func `Public protocol generates public stub`() {
    assertMacroExpansion(
      """
      @Stubbable
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
      public class StubDataService: DataService {
        public var items: [Item] = []
        public var fetchReturnValue: [Item] = []
        public func fetch() async throws -> [Item] { fetchReturnValue }
        public func save(_ item: Item) async throws { }
        public init() {}
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Package protocol generates package stub`() {
    assertMacroExpansion(
      """
      @Stubbable
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
      package class StubDataService: DataService {
        package var items: [Item] = []
        package var fetchReturnValue: [Item] = []
        package func fetch() async throws -> [Item] { fetchReturnValue }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Fileprivate protocol generates fileprivate stub`() {
    assertMacroExpansion(
      """
      @Stubbable
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
      fileprivate class StubDataService: DataService {
        fileprivate var items: [Item] = []
        fileprivate var fetchReturnValue: [Item] = []
        fileprivate func fetch() async throws -> [Item] { fetchReturnValue }
      }
      """,
      macros: testMacros)
  }

  // MARK: - @StubbableDefault

  @Test
  func `Property with StubbableDefault uses custom default`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol ExtractionService {
        @StubbableDefault(ExtractionStatus.idle) var status: ExtractionStatus { get }
      }
      """,
      expandedSource: """
      protocol ExtractionService {
        var status: ExtractionStatus { get }
      }

      @Observable
      class StubExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Property without StubbableDefault uses defaultValue as before`() {
    assertMacroExpansion(
      """
      @Stubbable
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
      class StubExtractionService: ExtractionService {
        var count: Int = 0
        var theme: Theme! = nil
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Mixed properties with and without StubbableDefault`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol ExtractionService {
        @StubbableDefault(ExtractionStatus.idle) var status: ExtractionStatus { get }
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
      class StubExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
        var count: Int = 0
        var name: String = ""
      }
      """,
      macros: testMacros)
  }

  @Test
  func `AsyncStream property gets default`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol StreamService {
        var updates: AsyncStream<Int> { get }
      }
      """,
      expandedSource: """
      protocol StreamService {
        var updates: AsyncStream<Int> { get }
      }

      @Observable
      class StubStreamService: StreamService {
        var updates: AsyncStream<Int> = AsyncStream { $0.finish() }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Set property gets empty default`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol TagService {
        var tags: Set<String> { get }
      }
      """,
      expandedSource: """
      protocol TagService {
        var tags: Set<String> { get }
      }

      @Observable
      class StubTagService: TagService {
        var tags: Set<String> = []
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Method with external label different from internal name`() {
    assertMacroExpansion(
      """
      @Stubbable
      protocol ItemService {
        func perform(with item: Item) async throws
      }
      """,
      expandedSource: """
      protocol ItemService {
        func perform(with item: Item) async throws
      }

      @Observable
      class StubItemService: ItemService {
        func perform(with item: Item) async throws { }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Diagnostics

  @Test
  func `Error when applied to struct`() {
    assertMacroExpansion(
      """
      @Stubbable
      struct NotValid {
      }
      """,
      expandedSource: """
      struct NotValid {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Stubbable can only be applied to protocols", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error on protocol with associated types`() {
    assertMacroExpansion(
      """
      @Stubbable
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
        DiagnosticSpec(message: "@Stubbable does not support protocols with associated types", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning on protocol with subscripts`() {
    assertMacroExpansion(
      """
      @Stubbable
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
      class StubHasSubscript: HasSubscript {
        var name: String = ""
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Stubbable skips subscript members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }
}
#endif
