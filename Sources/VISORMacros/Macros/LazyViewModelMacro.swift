import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - LazyViewModelMacro

public struct LazyViewModelMacro: MemberMacro {

  // MARK: Public

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    guard let view = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.notAStruct(macroName: "LazyViewModel")))
      return []
    }
    guard
      case .argumentList(let arguments) = node.arguments,
      let first = arguments.first,
      let type = first.expression.as(MemberAccessExprSyntax.self),
      type.declName.baseName.text == "self",
      let base = type.base
    else {
      diagnose("@LazyViewModel requires (ViewModel.self)", at: node, in: context)
      return []
    }
    let model = base.trimmedDescription
    let policy = arguments.first { $0.label?.text == "observationPolicy" }?.expression.trimmedDescription
      ?? ".alwaysObserving"
    guard arguments.dropFirst().allSatisfy({ $0.label?.text == "observationPolicy" }) else {
      diagnose("@LazyViewModel uses pendingContent and failureContent properties for custom presentation", at: node, in: context)
      return []
    }
    for name in [
      "content",
      "state",
      "bindings",
      "viewModel",
      "send",
      "_visorPresentation",
      "_visorScenePhase",
    ] {
      guard !view.hasMemberNamed(name) else {
        diagnose("@LazyViewModel reserves '\(name)'; implement readyContent(state:) and optionally body", at: node, in: context)
        return []
      }
    }
    let methods = view.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
      .filter { $0.name.text == "readyContent" }
    guard methods.count == 1, let ready = methods.first else {
      diagnose("@LazyViewModel requires one func readyContent(state:) returning a View", at: node, in: context)
      return []
    }
    let parameters = ready.signature.parameterClause.parameters
    let labels = parameters.map { $0.firstName.text }
    guard
      labels.contains("state"), Set(labels).count == labels.count,
      labels.allSatisfy({ ["state", "bindings", "viewModel"].contains($0) }),
      ready.signature.effectSpecifiers == nil,
      ready.signature.returnClause != nil,
      ready.genericParameterClause == nil,
      !ready.modifiers.contains(where: { ["static", "class", "mutating"].contains($0.name.text) }),
      parameters.allSatisfy({ $0.defaultValue == nil && $0.ellipsis == nil })
    else {
      diagnose(
        "readyContent requires a synchronous nonthrowing state parameter, with optional bindings and viewModel parameters",
        at: ready,
        in: context,
      )
      return []
    }
    let access = accessLevel(of: view)
    let prefix = access == "public" || access == "open" ? "public " : ""
    let call = labels.map { label in
      switch label {
      case "state": "state: _visorModel.state"
      case "bindings": "bindings: _visorBindings"
      default: "viewModel: _visorModel"
      }
    }.joined(separator: ", ")
    let pending = view.hasMemberNamed("pendingContent") ? "pendingContent" : "Color.clear"
    let failure = view.hasMemberNamed("failureContent")
      ? "failureContent"
      : """
        ContentUnavailableView(
            "Unable to Load",
            systemImage: "exclamationmark.triangle",
            description: Text("This screen could not be prepared.")
        )
        """
    var members: [DeclSyntax] = [
      "@Environment(\\.scenePhase) private var _visorScenePhase",
      "@State private var _visorPresentation = VISOR._LazyViewModelPresentation<\(raw: model)>()",
      """
      var state: \(raw: model).State? {
          _visorPresentation._visorState(observationPolicy: \(raw: policy), scenePhase: _visorScenePhase)
      }
      """,
      """
      var send: VISOR._LazyViewModelActionSender<\(raw: model)> {
          _visorPresentation._visorSender(observationPolicy: \(raw: policy), scenePhase: _visorScenePhase)
      }
      """,
      """
      var content: some View {
          VISOR._visorLazyViewModelContent(
              presentation: _visorPresentation,
              observationPolicy: \(raw: policy),
              pending: { \(raw: pending) },
              failure: { \(raw: failure) }
          ) { _visorModel, _visorBindings in
              readyContent(\(raw: call))
          }
      }
      """,
    ]
    if !view.hasMemberNamed("body") {
      members.append("\(raw: prefix)var body: some View { content }")
    }
    return members
  }

  // MARK: Private

  private static func diagnose(
    _ message: String,
    at node: some SyntaxProtocol,
    in context: some MacroExpansionContext,
  ) {
    context.diagnose(Diagnostic(node: node, message: LazyViewDiagnostic(message: message)))
  }
}

// MARK: - LazyViewDiagnostic

private struct LazyViewDiagnostic: DiagnosticMessage {
  let message: String

  var diagnosticID: MessageID {
    MessageID(domain: "VISOR", id: "lazyViewPresentation")
  }

  var severity: DiagnosticSeverity {
    .error
  }
}
