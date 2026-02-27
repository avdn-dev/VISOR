//
//  SpyableMacroTests.swift
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
  "Spyable": SpyableMacro.self,
  "StubbableDefault": StubbableDefaultMacro.self,
]

// MARK: - SpyableMacroTests

@Suite("Spyable Macro")
struct SpyableMacroTests {

  // MARK: - Spy Generation

  @Test
  func `Generates spy with properties and methods`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyDataService: DataService {
        var items: [Item] = []
        // -- fetch --
        var fetchCallCount = 0
        var fetchReturnValue: [Item] = []
        func fetch() async throws -> [Item] {
          fetchCallCount += 1
          calls.append(.fetch)
          return fetchReturnValue
        }
        // -- save --
        var saveCallCount = 0
        var saveReceivedItem: Item?
        var saveReceivedInvocations: [Item] = []
        func save(_ item: Item) async throws {
          saveCallCount += 1
          saveReceivedItem = item
          saveReceivedInvocations.append(item)
          calls.append(.save(item: item))
        }
        enum Call {
          case fetch
          case save(item: Item)
        }
        var calls: [Call] = []
      }
      #endif
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for void methods`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyLogService: LogService {
        // -- log --
        var logCallCount = 0
        var logReceivedMessage: String?
        var logReceivedInvocations: [String] = []
        func log(message: String) {
          logCallCount += 1
          logReceivedMessage = message
          logReceivedInvocations.append(message)
          calls.append(.log(message: message))
        }
        // -- reset --
        var resetCallCount = 0
        func reset() {
          resetCallCount += 1
          calls.append(.reset)
        }
        enum Call {
          case log(message: String)
          case reset
        }
        var calls: [Call] = []
      }
      #endif
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy with multiple parameters`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpySearchService: SearchService {
        // -- search --
        var searchCallCount = 0
        var searchReceivedArguments: (query: String, limit: Int)?
        var searchReceivedInvocations: [(query: String, limit: Int)] = []
        var searchReturnValue: [String] = []
        func search(query: String, limit: Int) async throws -> [String] {
          searchCallCount += 1
          searchReceivedArguments = (query, limit)
          searchReceivedInvocations.append((query, limit))
          calls.append(.search(query: query, limit: limit))
          return searchReturnValue
        }
        enum Call {
          case search(query: String, limit: Int)
        }
        var calls: [Call] = []
      }
      #endif
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy with IUO for unknown return type`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyThemeService: ThemeService {
        // -- currentTheme --
        var currentThemeCallCount = 0
        var currentThemeReturnValue: Theme!
        func currentTheme() -> Theme {
          currentThemeCallCount += 1
          calls.append(.currentTheme)
          return currentThemeReturnValue
        }
        enum Call {
          case currentTheme
        }
        var calls: [Call] = []
      }
      #endif
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy for empty protocol`() {
    assertMacroExpansion(
      """
      @Spyable
      protocol EmptyService {
      }
      """,
      expandedSource: """
      protocol EmptyService {
      }

      #if DEBUG
      @Observable
      class SpyEmptyService: EmptyService {
      }
      #endif
      """,
      macros: testMacros)
  }

  @Test
  func `Uses IUO for unknown property types`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyThemeService: ThemeService {
        var currentTheme: Theme! = nil
      }
      #endif
      """,
      macros: testMacros)
  }

  @Test
  func `Generates spy with external label different from internal name`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyItemService: ItemService {
        // -- perform --
        var performCallCount = 0
        var performReceivedItem: Item?
        var performReceivedInvocations: [Item] = []
        func perform(with item: Item) async throws {
          performCallCount += 1
          performReceivedItem = item
          performReceivedInvocations.append(item)
          calls.append(.perform(item: item))
        }
        enum Call {
          case perform(item: Item)
        }
        var calls: [Call] = []
      }
      #endif
      """,
      macros: testMacros)
  }

  // MARK: - @StubbableDefault

  @Test
  func `Spy property with StubbableDefault uses custom default`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyExtractionService: ExtractionService {
        var status: ExtractionStatus = ExtractionStatus.idle
        var count: Int = 0
        // -- reset --
        var resetCallCount = 0
        func reset() {
          resetCallCount += 1
          calls.append(.reset)
        }
        enum Call {
          case reset
        }
        var calls: [Call] = []
      }
      #endif
      """,
      macros: testMacros)
  }

  // MARK: - Diagnostics

  @Test
  func `Error when applied to class`() {
    assertMacroExpansion(
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
  func `Error when applied to struct`() {
    assertMacroExpansion(
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
  func `Error on protocol with associated types`() {
    assertMacroExpansion(
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
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyHasStatic: HasStatic {
        // -- doWork --
        var doWorkCallCount = 0
        func doWork() {
          doWorkCallCount += 1
          calls.append(.doWork)
        }
        enum Call {
          case doWork
        }
        var calls: [Call] = []
      }
      #endif
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Spyable skips static members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning on protocol with subscripts`() {
    assertMacroExpansion(
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

      #if DEBUG
      @Observable
      class SpyHasSubscript: HasSubscript {
        var name: String = ""
      }
      #endif
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Spyable skips subscript members (not yet supported)", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }
}
#endif
