import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacroExpansion
import Testing

#if canImport(VISORMacros)
@testable import VISORMacros

@Suite("Computed State binding macro contracts")
struct StateProjectionMacroTests {

  // MARK: Internal

  @Test(arguments: [
    "var projected: Int { count }",
    "var projected: Int { get { count } }",
    "public var projected: Int { count }",
    "fileprivate var projected: Int { count }",
  ])
  func `Get-only projections are eligible`(property: String) throws {
    let (model, state) = try declarations(property)
    let analysis = StateBindingAnalysis(viewModel: model, state: state)
    #expect(analysis.isValid)
    #expect(analysis.bindings.first?.fieldName == "projected")
  }

  @Test(arguments: [
    "private var projected: Int { count }",
    "static var projected: Int { 0 }",
    "let projected = 0",
    "var projected: Int { get { count } set {} }",
    "var projected: Int { get async { count } }",
    "var projected: Int { get throws { count } }",
    "var projected: Int { get async throws { count } }",
    "#if DEBUG\nvar projected: Int { count }\n#endif",
  ])
  func `Unsupported projections receive a selection diagnostic`(property: String) throws {
    let (model, state) = try declarations(property)
    let analysis = StateBindingAnalysis(viewModel: model, state: state)
    #expect(analysis.diagnostics.map { $0.1.rawValue } == ["selection"])
  }

  @Test
  func `Only opted-in computed properties gain selectors and never mutation metadata`() throws {
    let (model, state) = try declarations("public var projected: Int { count }")
    let context = BasicMacroExpansionContext()
    let attributes = try ViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@ViewModel"),
      attachedTo: model,
      providingAttributesFor: state,
      in: context,
    )
    let attribute = try #require(attributes.first {
      $0.attributeName.trimmedDescription == "VISOR._ViewModelState"
    })
    #expect(attribute.trimmedDescription == "@VISOR._ViewModelState")
    let members = try ViewModelStateMacro.expansion(
      of: attribute,
      providingMembersOf: state,
      conformingTo: [],
      in: context,
    ).map(\.description).joined(separator: "\n")

    #expect(context.diagnostics.isEmpty)
    #expect(!members.contains("_visorProjection"))
    #expect(!members.contains("let projected ="))
    #expect(!members.contains("_visorField_projected"))
    #expect(!members.contains("$0._projected"))

    let modelMembers = try ViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@ViewModel"),
      providingMembersOf: model,
      conformingTo: [],
      in: context,
    ).map(\.description).joined(separator: "\n")
    #expect(modelMembers.contains("private static let _visorBinding_projected = VISOR._ViewModelBinding("))
    #expect(modelMembers.contains(#"keyPath: \State.projected"#))
    #expect(modelMembers.contains("public let projected = Model._visorBinding_projected"))
    #expect(!modelMembers.contains("_visorBinding_displayOnly"))
    #expect(!modelMembers.contains("_visorBinding_count"))
    #expect(!modelMembers.contains("model.updateState("))
    #expect(modelMembers.contains("model.handle(.changed(value))"))
  }

  // MARK: Private

  private func declarations(_ property: String) throws -> (ClassDeclSyntax, ClassDeclSyntax) {
    let model = try #require(DeclSyntax(stringLiteral: """
      @MainActor
      @Observable
      @ViewModel
      final class Model {
        final class State {
          private(set) var count = 0
          var displayOnly: String { count.description }
          \(property)
        }
        enum Action {
          @StateBinding(\\State.projected) case changed(Int)
        }
        func handle(_ action: Action) -> ActionCompletion { .completed }
      }
      """).as(ClassDeclSyntax.self))
    let state = try #require(model.memberBlock.members.compactMap {
      $0.decl.as(ClassDeclSyntax.self)
    }.first)
    return (model, state)
  }
}
#endif
