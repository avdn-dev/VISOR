import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
import VISORMacros

@Suite("Lazy view presentation macro")
struct LazyViewModelMacroTests {

  // MARK: Internal

  @Test
  func `Authored body stays outside the generated readiness slot`() throws {
    // Given
    let source = """
      struct Screen: View {
        var body: some View { content.navigationTitle("Library") }
        func readyContent(state: Model.State) -> some View { Text(state.title) }
      }
      """

    // When
    let (members, diagnostics) = try expand(source)

    // Then
    #expect(diagnostics.isEmpty)
    #expect(!members.contains("var body:"))
    #expect(members.contains("var state: Model.State?"))
    #expect(members.contains("var content: some View"))
    #expect(members.contains("readyContent(state: _visorModel.state)"))
    #expect(members.contains("_visorPresentation.wrappedValue._visorSender"))
    #expect(!members.contains("preconditionFailure"))
    #expect(!members.contains("var viewModel:"))
    #expect(!members.contains("var bindings:"))
    #expect(members.contains("private var _visorPresentation = SwiftUI.State(initialValue:"))
    #expect(members.contains("presentation: _visorPresentation.wrappedValue,"))
    #expect(!members.contains("@State"))
  }

  @Test(arguments: ["", "public ", "package ", "private ", "fileprivate "])
  func `Default body has the access required by its view`(access: String) throws {
    // Given
    let source = """
      \(access)struct Screen: View {
        func readyContent(state: Model.State) -> some View { Text(state.title) }
      }
      """

    // When
    let (members, diagnostics) = try expand(source)

    // Then
    #expect(diagnostics.isEmpty)
    #expect(members.contains("var body: some View { content }"))
    #expect(members.contains("public var body:") == (access == "public "))
  }

  @Test
  func `Bindings and model integration are explicit ready parameters`() throws {
    // Given
    let source = """
      struct Screen: View {
        func readyContent(
          bindings: ViewModelBindings<Model>, state: Model.State, viewModel: Model
        ) -> some View { Toggle(state.title, isOn: bindings.enabled) }
        var pendingContent: some View { ProgressView() }
        var failureContent: some View { Text("Unavailable") }
      }
      """

    // When
    let (members, diagnostics) = try expand(source, policy: ".pauseWhenInactive")

    // Then
    #expect(diagnostics.isEmpty)
    #expect(members.contains("readyContent(bindings: _visorBindings, state: _visorModel.state, viewModel: _visorModel)"))
    #expect(members.contains("pending: { pendingContent }"))
    #expect(members.contains("failure: { failureContent }"))
    #expect(members.contains("observationPolicy: .pauseWhenInactive"))
  }

  @Test(arguments: [
    ("viewModel: Model", "viewModel: _visorModel"),
    ("viewModel model: Model", "viewModel: _visorModel"),
    ("viewModel: Model, bindings: ViewModelBindings<Model>", "viewModel: _visorModel, bindings: _visorBindings"),
    ("bindings: ViewModelBindings<Model>, viewModel: Model", "bindings: _visorBindings, viewModel: _visorModel"),
  ])
  func `Model access does not require a redundant state parameter`(parameters: String, arguments: String) throws {
    // Given
    let source = "struct Screen: View { func readyContent(\(parameters)) -> some View { Text(\"Ready\") } }"

    // When
    let (members, diagnostics) = try expand(source)

    // Then
    #expect(diagnostics.isEmpty)
    #expect(members.contains("readyContent(\(arguments))"))
    #expect(!members.contains("state: _visorModel.state"))
    #expect(members.contains("var state: Model.State?"))
  }

  @Test
  func `Overloaded ready methods remain ambiguous and are rejected`() throws {
    // Given
    let source = """
      struct Screen: View {
        func readyContent(state: Model.State) -> some View { Text(state.title) }
        func readyContent(viewModel: Model) -> some View { Text(viewModel.state.title) }
      }
      """

    // When
    let (members, diagnostics) = try expand(source)

    // Then
    #expect(members.isEmpty)
    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.contains("exactly one readyContent method") == true)
  }

  @Test
  func `Bindings alone diagnose the required state or model parameter`() throws {
    // Given
    let source = """
      struct Screen: View {
        func readyContent(bindings: ViewModelBindings<Model>) -> some View {
          Toggle("Enabled", isOn: bindings.enabled)
        }
      }
      """

    // When
    let (members, diagnostics) = try expand(source)

    // Then
    #expect(members.isEmpty)
    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.contains("state or viewModel") == true)
  }

  @Test(arguments: ["state", "bindings", "viewModel", "content", "send", "_visorPresentation"])
  func `Reserved members are rejected instead of leaving ambiguous aliases`(name: String) throws {
    // Given
    let source = """
      struct Screen: View {
        var \(name) = 1
        func readyContent(state: Model.State) -> some View { Text("") }
      }
      """

    // When
    let (members, diagnostics) = try expand(source)

    // Then
    #expect(members.isEmpty)
    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.contains("reserves '\(name)'") == true)
  }

  @Test(arguments: [
    "var readyContent: some View { Text(\"\") }",
    "func readyContent() -> some View { Text(\"\") }",
    "func readyContent(state: Model.State) async -> some View { Text(\"\") }",
    "func readyContent(state: Model.State) throws -> some View { Text(\"\") }",
    "static func readyContent(state: Model.State) -> some View { Text(\"\") }",
    "func readyContent(state: Model.State, unexpected: Int) -> some View { Text(\"\") }",
    "func readyContent(state: Model.State, bindings: Int = 0) -> some View { Text(\"\") }",
    "func readyContent(viewModel: Model) async -> some View { Text(\"\") }",
    "func readyContent(viewModel: Model) throws -> some View { Text(\"\") }",
    "static func readyContent(viewModel: Model) -> some View { Text(\"\") }",
    "func readyContent(viewModel: Model, unexpected: Int) -> some View { Text(\"\") }",
    "func readyContent(viewModel first: Model, viewModel second: Model) -> some View { Text(\"\") }",
    "func readyContent(viewModel: Model = Model()) -> some View { Text(\"\") }",
  ])
  func `Invalid ready declarations receive an actionable diagnostic`(declaration: String) throws {
    // Given
    let source = "struct Screen: View { \(declaration) }"

    // When
    let (members, diagnostics) = try expand(source)

    // Then
    #expect(members.isEmpty)
    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.contains("readyContent") == true)
  }

  // MARK: Private

  private func expand(_ source: String, policy: String = ".alwaysObserving") throws -> (String, [String]) {
    let view = try #require(DeclSyntax(stringLiteral: source).as(StructDeclSyntax.self))
    let context = BasicMacroExpansionContext()
    let members = try LazyViewModelMacro.expansion(
      of: AttributeSyntax(stringLiteral: "@LazyViewModel(Model.self, observationPolicy: \(policy))"),
      providingMembersOf: view,
      conformingTo: [],
      in: context,
    )
    return (members.map(\.description).joined(separator: "\n"), context.diagnostics.map(\.message))
  }
}
