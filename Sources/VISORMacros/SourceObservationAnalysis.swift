import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - SourceObservationSelection

struct SourceObservationSelection {
  let source: ExprSyntax
  let selection: ExprSyntax?
}

extension AttributeSyntax {
  var sourceObservationSelection: SourceObservationSelection? {
    guard let arguments = arguments?.as(LabeledExprListSyntax.self) else {
      return nil
    }
    guard
      arguments.count == 1 || arguments.count == 2,
      let source = arguments.first,
      source.label?.text == "source"
    else {
      return nil
    }
    if arguments.count == 1 {
      return SourceObservationSelection(
        source: source.expression,
        selection: nil,
      )
    }
    guard
      let selection = arguments.dropFirst().first,
      selection.label?.text == "selecting"
    else {
      return nil
    }
    return SourceObservationSelection(
      source: source.expression,
      selection: selection.expression,
    )
  }
}

// MARK: - SourceBoundRecipe

struct SourceBoundRecipe {
  let selection: ExprSyntax?
  let fieldName: String
}

// MARK: - SourceReactionRecipe

struct SourceReactionRecipe {
  let selection: ExprSyntax?
  let methodName: String
  let argumentLabel: String?
  let isAsync: Bool
}

// MARK: - SourceObservationRecipeGroup

struct SourceObservationRecipeGroup {
  let source: ExprSyntax
  let sourceComponents: [String]?
  var bounds = [SourceBoundRecipe]()
  var reactions = [SourceReactionRecipe]()
}

// MARK: - SourceObservationAnalysis

/// The source-routing facts shared by the ViewModel macro's independent roles.
struct SourceObservationAnalysis {

  // MARK: Lifecycle

  init(
    viewModel: ClassDeclSyntax,
    state: ClassDeclSyntax,
  ) {
    var groups = [SourceObservationRecipeGroup]()
    var hasRejectedDeclaration = false
    var diagnostics = [Diagnostic]()

    func groupIndex(for source: ExprSyntax) -> Int {
      let components = keyPathPropertyComponents(
        from: source,
        ownerName: viewModel.name.text,
      )
      if
        let components,
        let index = groups.firstIndex(where: {
          $0.sourceComponents == components
        })
      {
        return index
      }
      groups.append(SourceObservationRecipeGroup(
        source: source,
        sourceComponents: components,
      ))
      return groups.index(before: groups.endIndex)
    }

    for member in state.memberBlock.members {
      let attributes = observationRoutingAttributes(on: member.decl)
      let bounds = attributes.filter {
        routingMarkerName($0) == AttributeName.bound
      }
      let misplacedReactions = attributes.filter {
        routingMarkerName($0) == AttributeName.reaction
      }

      if bounds.count > 1 {
        hasRejectedDeclaration = true
        diagnostics.append(Diagnostic(
          node: Syntax(member.decl),
          message: VISORDiagnostic.invalidSourceBoundDeclaration,
        ))
      }
      if !misplacedReactions.isEmpty {
        hasRejectedDeclaration = true
        diagnostics.append(contentsOf: misplacedReactions.map {
          Diagnostic(
            node: Syntax($0),
            message: VISORDiagnostic.invalidSourceReactionPlacement,
          )
        })
      }

      if let attribute = bounds.first {
        guard
          let variable = member.decl.as(VariableDeclSyntax.self),
          let field = stateFieldSpec(from: variable),
          field.accessPrefix != "private ",
          let observation = attribute.sourceObservationSelection
        else {
          hasRejectedDeclaration = true
          continue
        }
        groups[groupIndex(for: observation.source)].bounds.append(
          SourceBoundRecipe(
            selection: observation.selection,
            fieldName: field.name,
          )
        )
      }

      if
        let nested = nestedMemberBlock(of: member.decl),
        containsObservationRoutingMarker(in: nested)
      {
        hasRejectedDeclaration = true
      }
    }

    for member in viewModel.memberBlock.members {
      if member.decl.as(ClassDeclSyntax.self)?.name.text == "State" {
        continue
      }
      let attributes = observationRoutingAttributes(on: member.decl)
      let reactions = attributes.filter {
        routingMarkerName($0) == AttributeName.reaction
      }
      let misplacedBounds = attributes.filter {
        routingMarkerName($0) == AttributeName.bound
      }

      if reactions.count > 1 {
        hasRejectedDeclaration = true
        diagnostics.append(Diagnostic(
          node: Syntax(member.decl),
          message: VISORDiagnostic.invalidSourceReactionDeclaration,
        ))
      }
      if !misplacedBounds.isEmpty {
        hasRejectedDeclaration = true
        diagnostics.append(contentsOf: misplacedBounds.map {
          Diagnostic(
            node: Syntax($0),
            message: VISORDiagnostic.invalidSourceBoundPlacement,
          )
        })
      }

      if let attribute = reactions.first {
        guard
          let observation = attribute.sourceObservationSelection,
          let function = member.decl.as(FunctionDeclSyntax.self),
          function.signature.parameterClause.parameters.count == 1,
          let parameter = function.signature.parameterClause.parameters.first,
          function.signature.returnClause == nil,
          function.signature.effectSpecifiers?.throwsClause == nil,
          !function.modifiers.hasStateTypeStorageModifier
        else {
          hasRejectedDeclaration = true
          continue
        }
        groups[groupIndex(for: observation.source)].reactions.append(
          SourceReactionRecipe(
            selection: observation.selection,
            methodName: function.name.text,
            argumentLabel: parameter.firstName.text == "_"
              ? nil
              : parameter.firstName.text,
            isAsync: function.signature.effectSpecifiers?.asyncSpecifier
              != nil,
          )
        )
      }

      if
        let nested = nestedMemberBlock(of: member.decl),
        containsObservationRoutingMarker(in: nested)
      {
        hasRejectedDeclaration = true
      }
    }

    self.groups = groups
    self.hasRejectedDeclaration = hasRejectedDeclaration
    self.diagnostics = diagnostics
  }

  // MARK: Internal

  let groups: [SourceObservationRecipeGroup]
  let hasRejectedDeclaration: Bool

  func diagnose(in context: some MacroExpansionContext) {
    for diagnostic in diagnostics {
      context.diagnose(diagnostic)
    }
  }

  // MARK: Private

  private let diagnostics: [Diagnostic]
}

// MARK: - Syntax Analysis

func keyPathPropertyComponents(
  from expression: ExprSyntax,
  ownerName: String,
) -> [String]? {
  guard let keyPath = expression.as(KeyPathExprSyntax.self) else {
    return nil
  }
  let components = keyPath.components.compactMap { component -> String? in
    guard case .property(let property) = component.component else {
      return nil
    }
    return property.declName.baseName.text
  }
  guard components.count == keyPath.components.count else { return nil }
  guard components.first == ownerName else { return components }
  return Array(components.dropFirst())
}

private func observationRoutingAttributes(
  on declaration: some DeclSyntaxProtocol
) -> [AttributeSyntax] {
  let attributes: AttributeListSyntax? =
    if let variable = declaration.as(VariableDeclSyntax.self) {
      variable.attributes
    } else if let function = declaration.as(FunctionDeclSyntax.self) {
      function.attributes
    } else if let type = declaration.as(ClassDeclSyntax.self) {
      type.attributes
    } else if let type = declaration.as(StructDeclSyntax.self) {
      type.attributes
    } else if let type = declaration.as(EnumDeclSyntax.self) {
      type.attributes
    } else {
      nil
    }

  return attributes?.compactMap { $0.as(AttributeSyntax.self) }
    .filter { attribute in
      let name = attribute.attributeName.trimmedDescription
        .split(separator: ".").last
      return [
        Substring(AttributeName.bound),
        Substring(AttributeName.reaction),
      ].contains(name)
    } ?? []
}

private func nestedMemberBlock(
  of declaration: DeclSyntax
) -> MemberBlockSyntax? {
  if let type = declaration.as(ClassDeclSyntax.self) {
    return type.memberBlock
  }
  if let type = declaration.as(StructDeclSyntax.self) {
    return type.memberBlock
  }
  if let type = declaration.as(EnumDeclSyntax.self) {
    return type.memberBlock
  }
  if let type = declaration.as(ActorDeclSyntax.self) {
    return type.memberBlock
  }
  if let declaration = declaration.as(ExtensionDeclSyntax.self) {
    return declaration.memberBlock
  }
  return nil
}

private func containsObservationRoutingMarker(
  in block: MemberBlockSyntax
) -> Bool {
  for member in block.members {
    if !observationRoutingAttributes(on: member.decl).isEmpty {
      return true
    }
    if
      let nested = nestedMemberBlock(of: member.decl),
      containsObservationRoutingMarker(in: nested)
    {
      return true
    }
  }
  return false
}

private func routingMarkerName(_ attribute: AttributeSyntax) -> String {
  String(attribute.attributeName.trimmedDescription
    .split(separator: ".").last ?? "")
}
