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

      #if DEBUG
      @Observable
      class StubDataService: DataService {
        var items: [Item] = []
        var isLoading: Bool = false
        var fetchReturnValue: [Item] = []
        func fetch() async throws -> [Item] { fetchReturnValue }
        func save(_ item: Item) async throws { }
      }
      #endif
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

      #if DEBUG
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
      #endif
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

      #if DEBUG
      @Observable
      class StubThemeService: ThemeService {
        var currentThemeReturnValue: Theme!
        func currentTheme() -> Theme { currentThemeReturnValue }
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubEmptyService: EmptyService {
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubSearchService: SearchService {
        var searchReturnValue: [Result] = []
        func search(query: String, limit: Int) async throws -> [Result] { searchReturnValue }
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubCacheService: CacheService {
        var getReturnValue: Data? = nil
        func get(key: String) -> Data? { getReturnValue }
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubExtractionService: ExtractionService {
        var count: Int = 0
        var theme: Theme! = nil
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
        var count: Int = 0
        var name: String = ""
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubStreamService: StreamService {
        var updates: AsyncStream<Int> = AsyncStream { $0.finish() }
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubTagService: TagService {
        var tags: Set<String> = []
      }
      #endif
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

      #if DEBUG
      @Observable
      class StubItemService: ItemService {
        func perform(with item: Item) async throws { }
      }
      #endif
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
  func `Error when applied to enum`() {
    assertMacroExpansion(
      """
      @Stubbable
      enum NotValid {
        case a
      }
      """,
      expandedSource: """
      enum NotValid {
        case a
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Stubbable can only be applied to protocols", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when applied to class`() {
    assertMacroExpansion(
      """
      @Stubbable
      final class NotValid {
        private let service: DataService
      }
      """,
      expandedSource: """
      final class NotValid {
        private let service: DataService
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

      #if DEBUG
      @Observable
      class StubHasSubscript: HasSubscript {
        var name: String = ""
      }
      #endif
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Stubbable skips subscript members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }
}
#endif
