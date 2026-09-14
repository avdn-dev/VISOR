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

  @Test(arguments: ["ActionCompletion", "VISOR.ActionCompletion", "CompletionAlias"])
  func `Binding analysis leaves handler return type checking to protocol conformance`(returnType: String) throws {
    // Given
    let model = try model(
      action: #"@StateBinding(\State.count) case changed(Int)"#,
      handler: "func handle(_ action: Action) -> \(returnType) { .completed }",
    )

    // When
    let analysis = try analyse(model)

    // Then
    #expect(analysis.isValid)
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
  func `Conditionally declared Action enums receive a diagnostic before route synthesis`() throws {
    // Given
    let model = try modelWithMembers(#"""
    #if os(macOS)
    enum Action {
      @StateBinding(\State.count) case changed(Int)
    }
    #elseif DEBUG
    #if FEATURE
    enum Action {
      @StateBinding(\State.count) case changed(Int)
    }
    #endif
    #else
    enum Action {
      @StateBinding(\State.count) case changed(Int)
    }
    #endif
    func handle(_ action: Action) -> ActionCompletion { .completed }
    """#)
    let context = BasicMacroExpansionContext()

    // When
    let analysis = try analyse(model)
    let members = try ViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@ViewModel"),
      providingMembersOf: model,
      conformingTo: [],
      in: context,
    )

    // Then
    #expect(analysis.diagnostics.map { $0.1.rawValue } == Array(repeating: "conditional", count: 3))
    #expect(context.diagnostics.map(\.message) == Array(repeating: StateBindingDiagnostic.conditional.message, count: 3))
    #expect(members.isEmpty)
  }

  @Test
  func `Conditional Action enums without bindings remain supported`() throws {
    // Given
    let model = try modelWithMembers(#"""
    #if DEBUG
    enum Action { case refresh }
    #else
    enum Action {
      case reload
      @MainActor
      @Observable
      @ViewModel
      final class NestedModel {
        final class State { private(set) var count = 0 }
        enum Action {
          @StateBinding(\State.count) case changed(Int)
        }
        func handle(_ action: Action) -> ActionCompletion { .completed }
      }
    }
    #endif
    func handle(_ action: Action) -> ActionCompletion { .completed }
    """#)

    // When
    let analysis = try analyse(model)

    // Then
    #expect(analysis.isValid)
    #expect(analysis.bindings.isEmpty)
  }

  @Test
  func `Conditional nested models do not contribute bindings to their enclosing model`() throws {
    // Given
    let model = try modelWithMembers(#"""
    enum Action {
      @StateBinding(\State.count) case changed(Int)
    }
    func handle(_ action: Action) -> ActionCompletion { .completed }
    #if DEBUG
    @MainActor
    @Observable
    @ViewModel
    final class NestedModel {
      final class State { private(set) var count = 0 }
      enum Action {
        @StateBinding(\State.count) case changed(Int)
      }
      func handle(_ action: Action) -> ActionCompletion { .completed }
    }
    #endif
    """#)

    // When
    let analysis = try analyse(model)

    // Then
    #expect(analysis.isValid)
    #expect(analysis.bindings.count == 1)
  }

  @Test
  func `Labelled payloads synthesise synchronous forwarding that discards completion`() throws {
    // Given
    let model = try model(
      action: #"@StateBinding(\State.count) case changed(value: Int)"#,
      handler: "func handle(_ action: Action) -> ActionCompletion { .completed }",
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
    #expect(!members.contains("_visorConnectStateBindings"))
    #expect(!members.contains("[weak self]"))
    #expect(members.contains("_ = model.handle(.changed(value: value))"))
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

  @Test(arguments: ["bindings", "_VISORBindingSelectors", "_visorBindingSelectors", "_visorBindings", "_visorBinding_count"])
  func `Binding namespace collisions fail with a focused diagnostic`(name: String) throws {
    let model = try modelWithMembers("""
      let \(name) = 0
      enum Action {
        @StateBinding(\\State.count) case changed(Int)
      }
      func handle(_ action: Action) -> ActionCompletion { .completed }
      """)
    let context = BasicMacroExpansionContext()
    let members = try ViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@ViewModel"),
      providingMembersOf: model,
      conformingTo: [],
      in: context,
    )
    #expect(members.isEmpty)
    #expect(context.diagnostics.count == 1)
    #expect(context.diagnostics.first?.message.contains("could not generate '\(name)'") == true)
  }

  @Test
  func `A view-owned bindings member is rejected as an ambiguous readiness alias`() throws {
    let view = try #require(DeclSyntax(stringLiteral: """
      struct Screen: View {
        let bindings = 0
        var content: some View { EmptyView() }
      }
      """).as(StructDeclSyntax.self))
    let context = BasicMacroExpansionContext()
    let members = try LazyViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@LazyViewModel(Model.self)"),
      providingMembersOf: view,
      conformingTo: [],
      in: context,
    ).map(\.description).joined(separator: "\n")
    #expect(!members.contains("var bindings:"))
    #expect(context.diagnostics.first?.diagMessage.severity == .error)
  }

  @Test(arguments: [true, false])
  func `Removing an annotation removes the binding instead of changing its setter`(annotated: Bool) throws {
    // Given
    let annotation = annotated ? #"@StateBinding(\State.count) "# : ""
    let model = try model(action: annotation + "case changed(Int)")
    let context = BasicMacroExpansionContext()

    // When
    let members = try ViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@ViewModel"),
      providingMembersOf: model,
      conformingTo: [],
      in: context,
    ).map(\.description).joined(separator: "\n")

    // Then
    #expect(context.diagnostics.isEmpty)
    #expect(members.contains("private static let _visorBinding_count") == annotated)
    #expect(members.contains("let count = Model._visorBinding_count") == annotated)
    #expect(members.contains("model.handle(.changed(value))") == annotated)
    #expect(!members.contains("model.updateState("))
    #expect(!members.contains("_visorBinding_output"))
    #expect(!members.contains("_visorBinding_computed"))
  }

  @Test(arguments: ["", "enum Action { case changed(Int) }\nfunc handle(_ action: Action) -> ActionCompletion { .completed }"])
  func `Models without binding actions still conform with an empty binding namespace`(members: String) throws {
    // Given
    let model = try modelWithMembers(members)
    let context = BasicMacroExpansionContext()

    // When
    let generated = try ViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@ViewModel"),
      providingMembersOf: model,
      conformingTo: [],
      in: context,
    ).map(\.description).joined(separator: "\n")

    // Then
    #expect(context.diagnostics.isEmpty)
    #expect(generated.contains("struct _VISORBindingSelectors"))
    #expect(generated.contains("var bindings: VISOR.ViewModelBindings<Model>"))
    #expect(!generated.contains("private static let _visorBinding_"))
    #expect(!generated.contains("model.handle("))
    #expect(!generated.contains("model.updateState("))
  }

  // MARK: Private

  private func model(
    action: String,
    handler: String = "func handle(_ action: Action) -> ActionCompletion { .completed }",
  ) throws -> ClassDeclSyntax {
    try modelWithMembers("""
      enum Action {
        \(action)
      }
      \(handler)
      """)
  }

  private func modelWithMembers(_ members: String) throws -> ClassDeclSyntax {
    try #require(DeclSyntax(stringLiteral: """
      @MainActor
      @Observable
      @ViewModel
      final class Model {
        final class State {
          private(set) var count = 0
          private(set) var output = 0
          private var secret = 0
          let constant = 0
          var computed: Int { count }
        }
        \(members)
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
