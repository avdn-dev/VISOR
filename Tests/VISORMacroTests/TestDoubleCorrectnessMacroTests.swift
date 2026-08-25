import SwiftSyntaxMacros
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let correctnessMacros: [String: Macro.Type] = [
  "GenerateSpy": GenerateTestDoublesSpyMacro.self,
  "GenerateStub": GenerateTestDoublesStubMacro.self,
]

@Suite("Test-double macro correctness")
struct TestDoubleCorrectnessMacroTests {
  @Test
  func `Initialiser requirements fail without emitting a peer`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol Constructible {
        init(value: Int)
      }
      """,
      expandedSource: """
        protocol Constructible {
          init(value: Int)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateStub does not support initialiser requirements",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: correctnessMacros,
    )
  }

  @Test
  func `Inherited requirements fail without emitting a peer`() {
    assertMacroExpansionSwiftTesting(
      """
      protocol ParentService {
        func parentValue() -> Int
      }

      @GenerateSpy
      protocol ChildService: ParentService {
        func childValue() -> Int
      }
      """,
      expandedSource: """
        protocol ParentService {
          func parentValue() -> Int
        }
        protocol ChildService: ParentService {
          func childValue() -> Int
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateSpy cannot analyse requirements inherited from 'ParentService'",
          line: 5,
          column: 1,
          severity: .error,
        )
      ],
      macros: correctnessMacros,
    )
  }

  @Test
  func `Sendable inheritance requires synchronised generation`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      nonisolated protocol ConcurrentService: Sendable {
        func value() -> Int
      }
      """,
      expandedSource: """
        nonisolated protocol ConcurrentService: Sendable {
          func value() -> Int
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateStub requires the '.sendable' trait when the protocol inherits Sendable",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: correctnessMacros,
    )
  }

  @Test
  func `Variadic requirements fail without emitting a peer`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateSpy
      protocol VariadicService {
        func record(_ values: Int...)
      }
      """,
      expandedSource: """
        protocol VariadicService {
          func record(_ values: Int...)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateSpy does not support variadic method requirements",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: correctnessMacros,
    )
  }

  @Test
  func `Effectful property requirements fail without emitting a peer`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol AsyncPropertyService {
        var value: Int { get async throws }
      }
      """,
      expandedSource: """
        protocol AsyncPropertyService {
          var value: Int { get async throws }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateStub does not support effectful property accessor requirements",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: correctnessMacros,
    )
  }

  @Test
  func `AnyObject inheritance remains supported`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol ReferenceService: AnyObject {
        func reset()
      }
      """,
      expandedSource: """
        protocol ReferenceService: AnyObject {
          func reset()
        }

        @Observable
        final class StubReferenceService: ReferenceService {
          func reset() {
          }
        }
        """,
      macros: correctnessMacros,
    )
  }

  @Test
  func `Stub return storage is renamed around a protocol member`() {
    assertMacroExpansionSwiftTesting(
      """
      @GenerateStub
      protocol CollisionService {
        var fetchReturnValue: String { get }
        func fetch() -> Int
      }
      """,
      expandedSource: """
        protocol CollisionService {
          var fetchReturnValue: String { get }
          func fetch() -> Int
        }

        @Observable
        final class StubCollisionService: CollisionService {
          var fetchReturnValue: String = ""
          var fetchReturnValueGenerated: Int = 0
          func fetch() -> Int {
              fetchReturnValueGenerated
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@GenerateStub: generated return-storage member 'fetchReturnValue' collides with another member; using 'fetchReturnValueGenerated'.",
          line: 1,
          column: 1,
          severity: .warning,
        )
      ],
      macros: correctnessMacros,
    )
  }
}

#endif
