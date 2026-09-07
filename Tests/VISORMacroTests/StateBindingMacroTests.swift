import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacroExpansion
import Testing

#if canImport(VISORMacros)
@testable import VISORMacros

@Suite("State binding macro contracts")
struct StateBindingMacroTests {

  // MARK: Internal

  @Test(arguments: [
    (#"@StateBinding(\State.count) case changed"#, "declaration"),
    (#"@StateBinding(\State.count) case changed(Int, Int)"#, "declaration"),
    (#"@StateBinding(\State.count) case changed(Int = 1)"#, "declaration"),
    (#"@StateBinding(\State.count) case first(Int), second(Int)"#, "declaration"),
    (#"@StateBinding(\State.count) @StateBinding(\State.count) case changed(Int)"#, "declaration"),
    (#"@StateBinding(\State.missing) case changed(Int)"#, "selection"),
    (#"@StateBinding(\Other.State.count) case changed(Int)"#, "selection"),
    (#"@StateBinding(\State.count.description) case changed(String)"#, "selection"),
    (#"@StateBinding(\State.secret) case changed(Int)"#, "selection"),
    (#"@StateBinding(\State.computed) case changed(Int)"#, "selection"),
    (#"@StateBinding(\State.constant) case changed(Int)"#, "selection"),
  ])
  func `Invalid declarations produce a focused diagnostic`(action: String, expected: String) throws {
    // Given
    let model = try model(action: action)

    // When
    let analysis = try analyse(model)

    // Then
    #expect(analysis.diagnostics.map { $0.1.rawValue } == [expected])
  }

  @Test(arguments: [
    "func handle(_ action: Action) async {}",
    "func handle(_ action: Action) throws {}",
    "func handle(action: Action) {}",
    "nonisolated func handle(_ action: Action) {}",
    "static func handle(_ action: Action) {}",
  ])
  func `Binding actions require a synchronous instance handler`(handler: String) throws {
    // Given
    let model = try model(action: #"@StateBinding(\State.count) case changed(Int)"#, handler: handler)

    // When
    let analysis = try analyse(model)

    // Then
    #expect(analysis.diagnostics.map { $0.1.rawValue } == ["synchronousHandler"])
  }

  @Test
  func `Duplicate routes and conditional routes are rejected`() throws {
    // Given
    let duplicate = try model(action: #"""
    @StateBinding(\State.count) case first(Int)
    @StateBinding(\State.count) case second(Int)
    """#)
    let conditional = try model(action: #"""
    #if DEBUG
    @StateBinding(\State.count) case changed(Int)
    #endif
    """#)

    // When
    let duplicateAnalysis = try analyse(duplicate)
    let conditionalAnalysis = try analyse(conditional)

    // Then
    #expect(duplicateAnalysis.diagnostics.map { $0.1.rawValue } == ["duplicate"])
    #expect(conditionalAnalysis.diagnostics.map { $0.1.rawValue } == ["conditional"])
  }

  @Test
  func `Labelled payloads and explicit Void return types synthesise weak synchronous routing`() throws {
    // Given
    let model = try model(
      action: #"@StateBinding(\State.count) case changed(value: Int)"#,
      handler: "func handle(_ action: Action) -> Void {}",
    )
    let context = BasicMacroExpansionContext()

    // When
    let analysis = try analyse(model)
    let members = try ViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@ViewModel"),
      providingMembersOf: model,
      conformingTo: [],
      in: context,
    ).map(\.description).joined(separator: "\n")

    // Then
    #expect(analysis.isValid)
    #expect(analysis.bindings.first?.label == "value")
    #expect(context.diagnostics.isEmpty)
    #expect(members.contains("self._visorConnectStateBindings()"))
    #expect(members.contains("[weak self]"))
    #expect(members.contains("self?.handle(.changed(value: value))"))
    #expect(!members.contains("Task {"))
  }

  @Test
  func `Marker diagnoses use outside a ViewModel Action`() {
    assertMacroExpansionSwiftTesting(
      #"""
      enum Action {
        @StateBinding(\State.count)
        case changed(Int)
      }
      """#,
      expandedSource: """
        enum Action {
          case changed(Int)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@StateBinding requires a case in a @ViewModel's nested Action enum",
          line: 2,
          column: 3,
        )
      ],
      macros: ["StateBinding": StateBindingMacro.self],
    )
  }

  // MARK: Private

  private func model(
    action: String,
    handler: String = "func handle(_ action: Action) {}",
  ) throws -> ClassDeclSyntax {
    try #require(DeclSyntax(stringLiteral: """
      @MainActor
      @Observable
      @ViewModel
      final class Model {
        final class State {
          private(set) var count = 0
          private var secret = 0
          let constant = 0
          var computed: Int { count }
        }
        enum Action {
          \(action)
        }
        \(handler)
      }
      """).as(ClassDeclSyntax.self))
  }

  private func analyse(_ model: ClassDeclSyntax) throws -> StateBindingAnalysis {
    let state = try #require(model.memberBlock.members.compactMap {
      $0.decl.as(ClassDeclSyntax.self)
    }.first)
    return StateBindingAnalysis(viewModel: model, state: state)
  }
}
#endif
