import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - StateBindingSpec

struct StateBindingSpec {
  let fieldName: String
  let accessPrefix: String
  let caseName: String
  let label: String?
}

// MARK: - StateBindingDiagnostic

enum StateBindingDiagnostic: String, DiagnosticMessage {
  case placement
  case declaration
  case selection
  case duplicate
  case conditional

  // MARK: Internal

  var message: String {
    switch self {
    case .placement: "@StateBinding requires a case in a @ViewModel's nested Action enum"
    case .declaration: "@StateBinding requires one case with exactly one associated value"
    case .selection: "@StateBinding must select one accessible, routed stored State field or synchronous get-only computed State property"
    case .duplicate: "each State field can have only one @StateBinding action"
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
    for member in viewModel.memberBlock.members {
      guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else { continue }
      for attribute in conditionalActionBindings(in: conditional) {
        diagnostics.append((Syntax(attribute), .conditional))
      }
    }
    let action = viewModel.memberBlock.members.compactMap {
      $0.decl.as(EnumDeclSyntax.self)
    }.first { $0.name.text == "Action" }
    guard let action else { return }

    let fields = state.memberBlock.members.compactMap {
      stateFieldSpec(from: $0.decl)
    }.filter { $0.accessPrefix != "private " }
    let projections = state.memberBlock.members.compactMap {
      stateProjectionSpec(from: $0.decl)
    }
    let selections = fields.map { (name: $0.name, accessPrefix: $0.accessPrefix) } +
      projections.map { (name: $0.name, accessPrefix: $0.accessPrefix) }

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
        let selection = selections.first(where: { $0.name == name })
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
        accessPrefix: selection.accessPrefix,
        caseName: element.name.trimmedDescription,
        label: label == "_" ? nil : label,
      ))
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

// MARK: - Conditional action bindings

/// Searches conditional members without crossing into a nested model's scope.
private func conditionalActionBindings(in conditional: IfConfigDeclSyntax) -> [AttributeSyntax] {
  conditional.clauses.flatMap { clause -> [AttributeSyntax] in
    guard case .decls(let members) = clause.elements else { return [] }
    return members.flatMap { member -> [AttributeSyntax] in
      if let nested = member.decl.as(IfConfigDeclSyntax.self) {
        return conditionalActionBindings(in: nested)
      }
      guard
        let action = member.decl.as(EnumDeclSyntax.self),
        action.name.text == "Action"
      else { return [] }
      let visitor = ConditionalBindingVisitor(viewMode: .sourceAccurate)
      visitor.walk(action)
      return visitor.attributes
    }
  }
}

// MARK: - ConditionalBindingVisitor

private final class ConditionalBindingVisitor: SyntaxVisitor {
  var attributes = [AttributeSyntax]()

  override func visit(_: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
    if node.attributeName.trimmedDescription.split(separator: ".").last == "StateBinding" {
      attributes.append(node)
    }
    return .skipChildren
  }
}
