import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - StateBindingSpec

struct StateBindingSpec {
  let fieldName: String
  let caseName: String
  let label: String?
}

// MARK: - StateBindingDiagnostic

enum StateBindingDiagnostic: String, DiagnosticMessage {
  case placement
  case declaration
  case selection
  case duplicate
  case synchronousHandler
  case conditional

  // MARK: Internal

  var message: String {
    switch self {
    case .placement: "@StateBinding requires a case in a @ViewModel's nested Action enum"
    case .declaration: "@StateBinding requires one case with exactly one associated value"
    case .selection: "@StateBinding must select one accessible, routed stored State field"
    case .duplicate: "each State field can have only one @StateBinding action"
    case .synchronousHandler: "@StateBinding requires synchronous, nonthrowing handle(_ action: Action); move async work into managed effects"
    case .conditional: "@StateBinding cases must be declared directly in Action, outside conditional compilation blocks"
    }
  }

  var diagnosticID: MessageID {
    MessageID(domain: "VISOR.StateBinding", id: rawValue)
  }

  var severity: DiagnosticSeverity {
    .error
  }
}

// MARK: - StateBindingAnalysis

struct StateBindingAnalysis {

  // MARK: Lifecycle

  init(viewModel: ClassDeclSyntax, state: ClassDeclSyntax) {
    let action = viewModel.memberBlock.members.compactMap {
      $0.decl.as(EnumDeclSyntax.self)
    }.first { $0.name.text == "Action" }
    guard let action else { return }

    let fields = Set(state.memberBlock.members.compactMap {
      stateFieldSpec(from: $0.decl)
    }.filter { $0.accessPrefix != "private " }.map(\.name))

    for member in action.memberBlock.members {
      if let conditional = member.decl.as(IfConfigDeclSyntax.self) {
        let visitor = ConditionalBindingVisitor(viewMode: .sourceAccurate)
        visitor.walk(conditional)
        for attribute in visitor.attributes {
          diagnostics.append((Syntax(attribute), .conditional))
        }
        continue
      }
      guard
        let declaration = member.decl.as(EnumCaseDeclSyntax.self),
        let attribute = declaration.attributes.visorAttribute(named: "StateBinding")
      else { continue }
      guard
        declaration.attributes.count(where: {
          $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription.split(separator: ".").last == "StateBinding"
        }) == 1,
        declaration.elements.count == 1,
        let element = declaration.elements.first,
        let parameters = element.parameterClause?.parameters,
        parameters.count == 1,
        let parameter = parameters.first,
        parameter.defaultValue == nil
      else {
        diagnostics.append((Syntax(attribute), .declaration))
        continue
      }
      guard
        let name = stateBindingField(attribute),
        fields.contains(name)
      else {
        diagnostics.append((Syntax(attribute), .selection))
        continue
      }
      guard !bindings.contains(where: { $0.fieldName == name }) else {
        diagnostics.append((Syntax(attribute), .duplicate))
        continue
      }
      let label = parameter.firstName?.text
      bindings.append(StateBindingSpec(
        fieldName: name,
        caseName: element.name.trimmedDescription,
        label: label == "_" ? nil : label,
      ))
    }

    guard !bindings.isEmpty else { return }
    let hasSynchronousHandler = viewModel.memberBlock.members.contains { member in
      guard
        let function = member.decl.as(FunctionDeclSyntax.self),
        function.name.text == "handle",
        function.signature.parameterClause.parameters.count == 1,
        let parameter = function.signature.parameterClause.parameters.first,
        parameter.firstName.text == "_",
        parameter.type.trimmedDescription == "Action",
        function.signature.effectSpecifiers == nil,
        function.signature.returnClause.map({
          ["Void", "Swift.Void", "()"].contains($0.type.trimmedDescription)
        }) ?? true,
        !function.modifiers.contains(where: {
          ["static", "class", "nonisolated"].contains($0.name.text)
        })
      else { return false }
      return true
    }
    if !hasSynchronousHandler {
      diagnostics.append((Syntax(action.name), .synchronousHandler))
    }
  }

  // MARK: Internal

  var bindings = [StateBindingSpec]()
  var diagnostics = [(Syntax, StateBindingDiagnostic)]()

  var isValid: Bool {
    diagnostics.isEmpty
  }

  func diagnose(in context: some MacroExpansionContext) {
    for (node, message) in diagnostics {
      context.diagnose(Diagnostic(node: node, message: message))
    }
  }
}

func stateBindingField(_ attribute: AttributeSyntax) -> String? {
  guard
    case .argumentList(let arguments) = attribute.arguments,
    arguments.count == 1,
    let argument = arguments.first,
    argument.label == nil,
    let keyPath = argument.expression.as(KeyPathExprSyntax.self),
    let root = keyPath.root,
    root.trimmedDescription == "State",
    keyPath.components.count == 1,
    let component = keyPath.components.first,
    case .property(let property) = component.component,
    property.declName.argumentNames == nil
  else { return nil }
  return property.declName.baseName.text
}

// MARK: - ConditionalBindingVisitor

private final class ConditionalBindingVisitor: SyntaxVisitor {
  var attributes = [AttributeSyntax]()

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    if node.attributeName.trimmedDescription.split(separator: ".").last == "StateBinding" {
      attributes.append(node)
    }
    return .skipChildren
  }
}
