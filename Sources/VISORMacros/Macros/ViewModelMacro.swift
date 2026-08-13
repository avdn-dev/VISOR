import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

private enum ViewModelFixIt: String, FixItMessage {
  case addMainActor

  var message: String { "add '@MainActor'" }

  var fixItID: MessageID {
    MessageID(domain: "VISOR", id: rawValue)
  }
}

struct SourceObservationSelection {
  let source: ExprSyntax
  let selection: ExprSyntax?
}

extension AttributeSyntax {
  var isSourceObservationForm: Bool {
    guard let arguments = arguments?.as(LabeledExprListSyntax.self) else {
      return false
    }
    return arguments.contains { $0.label?.text == "source" }
  }

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
        selection: nil)
    }
    guard
      let selection = arguments.dropFirst().first,
      selection.label?.text == "selecting"
    else {
      return nil
    }
    return SourceObservationSelection(
      source: source.expression,
      selection: selection.expression)
  }
}

extension MacroExpansionContext {
  var isDirectViewModelStateContext: Bool {
    let classes = lexicalContext.compactMap { $0.as(ClassDeclSyntax.self) }
    guard classes.count >= 2 else { return false }
    return classes[0].name.text == "State" &&
      classes[1].attributes.visorContains(named: "ViewModel")
  }

  var isDirectViewModelContext: Bool {
    guard let type = lexicalContext.first?.as(ClassDeclSyntax.self) else {
      return false
    }
    return type.attributes.visorContains(named: "ViewModel")
  }
}

private struct SourceBoundRecipe {
  let source: ExprSyntax
  let selection: ExprSyntax?
  let fieldName: String
}

private struct SourceReactionRecipe {
  let source: ExprSyntax
  let selection: ExprSyntax?
  let methodName: String
  let argumentLabel: String?
  let isAsync: Bool
}

private struct SourceObservationRecipeGroup {
  let source: ExprSyntax
  var bounds: [SourceBoundRecipe] = []
  var reactions: [SourceReactionRecipe] = []
}

private func observationRoutingAttributes(
  on declaration: some DeclSyntaxProtocol
) -> [AttributeSyntax] {
  let attributes: AttributeListSyntax?
  if let variable = declaration.as(VariableDeclSyntax.self) {
    attributes = variable.attributes
  } else if let function = declaration.as(FunctionDeclSyntax.self) {
    attributes = function.attributes
  } else if let type = declaration.as(ClassDeclSyntax.self) {
    attributes = type.attributes
  } else if let type = declaration.as(StructDeclSyntax.self) {
    attributes = type.attributes
  } else if let type = declaration.as(EnumDeclSyntax.self) {
    attributes = type.attributes
  } else {
    attributes = nil
  }

  return attributes?.compactMap { $0.as(AttributeSyntax.self) }
    .filter { attribute in
      let name = attribute.attributeName.trimmedDescription
        .split(separator: ".").last
      return [
        Substring(AttributeName.bound),
        Substring(AttributeName.reaction),
        Substring("Polled"),
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

extension MemberBlockItemListSyntax {
  var visorHasUnconditionalDeinitialiser: Bool {
    contains { $0.decl.is(DeinitializerDeclSyntax.self) }
  }

  var visorConditionalDeinitialisers: [DeinitializerDeclSyntax] {
    flatMap { member -> [DeinitializerDeclSyntax] in
      guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else {
        return []
      }
      return conditional.clauses.flatMap { clause -> [DeinitializerDeclSyntax] in
        guard case .decls(let members) = clause.elements else { return [] }
        return members.compactMap {
          $0.decl.as(DeinitializerDeclSyntax.self)
        } + members.visorConditionalDeinitialisers
      }
    }
  }
}

extension ClassDeclSyntax {
  var hasExplicitDeinitialiser: Bool {
    memberBlock.members.visorHasUnconditionalDeinitialiser
  }

  var conditionalDeinitialisers: [DeinitializerDeclSyntax] {
    memberBlock.members.visorConditionalDeinitialisers
  }
}

private extension ClassDeclSyntax {
  var nestedViewModelState: ClassDeclSyntax? {
    memberBlock.members.compactMap {
      $0.decl.as(ClassDeclSyntax.self)
    }.first { $0.name.text == "State" }
  }

  var hasExplicitMainActor: Bool {
    attributes.visorContains(named: "MainActor")
  }

  var stableViewModelStateProperty: VariableDeclSyntax? {
    memberBlock.members.compactMap {
      $0.decl.as(VariableDeclSyntax.self)
    }.first { variable in
      variable.bindingSpecifier.text == "let" &&
        !variable.modifiers.hasStateTypeStorageModifier &&
        variable.bindings.count == 1 &&
        variable.bindings.contains { binding in
          guard
            binding.accessorBlock == nil,
            binding.pattern.as(IdentifierPatternSyntax.self)?
              .identifier.text == "state"
          else {
            return false
          }
          if binding.typeAnnotation?.type.trimmedDescription == "State" {
            return true
          }
          guard
            let call = binding.initializer?.value.as(
              FunctionCallExprSyntax.self)
          else {
            return false
          }
          return ["State", "Self.State"].contains(
            call.calledExpression.trimmedDescription)
        }
    }
  }

  var declaredViewModelStateProperty: VariableDeclSyntax? {
    memberBlock.members.compactMap {
      $0.decl.as(VariableDeclSyntax.self)
    }.first { variable in
      variable.bindings.contains { binding in
        binding.pattern.as(IdentifierPatternSyntax.self)?
          .identifier.text == "state"
      }
    }
  }

  var hasConformanceCompatiblePublicState: Bool {
    let access = accessLevel(of: self)
    guard access == "public" || access == "open" else { return true }
    guard
      let state = nestedViewModelState,
      let stateProperty = stableViewModelStateProperty
    else {
      return false
    }
    let stateAccess = accessLevel(of: state)
    return (stateAccess == "public" || stateAccess == "open") &&
      stateProperty.modifiers.stateFieldAccessPrefix == "public "
  }

  var hasRejectedSourceObservationDeclaration: Bool {
    guard let state = nestedViewModelState else { return false }

    for member in state.memberBlock.members {
      let attributes = observationRoutingAttributes(on: member.decl)
      let bounds = attributes.filter {
        routingMarkerName($0) == AttributeName.bound
      }
      let hasOtherRoutingMarker = attributes.contains { attribute in
        ["Polled", AttributeName.reaction]
          .contains(routingMarkerName(attribute))
      }
      if hasOtherRoutingMarker || bounds.count > 1 {
        return true
      }
      if let attribute = bounds.first {
        guard
          let variable = member.decl.as(VariableDeclSyntax.self),
          let field = stateFieldSpec(from: variable),
          field.accessPrefix != "private ",
          attribute.sourceObservationSelection != nil
        else {
          return true
        }
      }
      if
        let nested = nestedMemberBlock(of: member.decl),
        containsObservationRoutingMarker(in: nested)
      {
        return true
      }
    }

    for member in memberBlock.members {
      if member.decl.as(ClassDeclSyntax.self)?.name.text == "State" {
        continue
      }
      let attributes = observationRoutingAttributes(on: member.decl)
      let reactions = attributes.filter {
        routingMarkerName($0) == AttributeName.reaction
      }
      if attributes.count != reactions.count || reactions.count > 1 {
        return true
      }
      if let reaction = reactions.first {
        guard
          reaction.sourceObservationSelection != nil,
          let function = member.decl.as(FunctionDeclSyntax.self),
          function.signature.parameterClause.parameters.count == 1,
          function.signature.returnClause == nil,
          function.signature.effectSpecifiers?.throwsClause == nil,
          !function.modifiers.hasStateTypeStorageModifier
        else {
          return true
        }
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

  func diagnoseRejectedSourceObservationDeclarations(
    in context: some MacroExpansionContext
  ) {
    guard let state = nestedViewModelState else { return }

    for member in state.memberBlock.members {
      let attributes = observationRoutingAttributes(on: member.decl)
      let bounds = attributes.filter {
        routingMarkerName($0) == AttributeName.bound
      }
      for attribute in bounds where !attribute.isSourceObservationForm {
        context.diagnose(Diagnostic(
          node: Syntax(attribute),
          message: VISORDiagnostic.sourceBackedBoundRequiresSource))
      }
      if bounds.count > 1 {
        context.diagnose(Diagnostic(
          node: Syntax(member.decl),
          message: VISORDiagnostic.invalidSourceBoundDeclaration))
      }
      for attribute in attributes where
        routingMarkerName(attribute) == "Polled"
      {
        context.diagnose(Diagnostic(
          node: Syntax(attribute),
          message: VISORDiagnostic.sourceBackedPolledUnsupported))
      }
      for attribute in attributes where
        routingMarkerName(attribute) == AttributeName.reaction
      {
        context.diagnose(Diagnostic(
          node: Syntax(attribute),
          message: VISORDiagnostic.invalidSourceReactionPlacement))
      }
    }

    for member in memberBlock.members {
      if member.decl.as(ClassDeclSyntax.self)?.name.text == "State" {
        continue
      }
      let attributes = observationRoutingAttributes(on: member.decl)
      let reactions = attributes.filter {
        routingMarkerName($0) == AttributeName.reaction
      }
      for attribute in reactions where !attribute.isSourceObservationForm {
        context.diagnose(Diagnostic(
          node: Syntax(attribute),
          message: VISORDiagnostic.sourceBackedReactionRequiresSource))
      }
      if reactions.count > 1 {
        context.diagnose(Diagnostic(
          node: Syntax(member.decl),
          message: VISORDiagnostic.invalidSourceReactionDeclaration))
      }
      for attribute in attributes where
        routingMarkerName(attribute) == AttributeName.bound ||
        routingMarkerName(attribute) == "Polled"
      {
        let message = routingMarkerName(attribute) == AttributeName.bound
          ? VISORDiagnostic.invalidSourceBoundPlacement
          : VISORDiagnostic.sourceBackedPolledUnsupported
        context.diagnose(Diagnostic(
          node: Syntax(attribute),
          message: message))
      }
    }
  }
}

public struct ViewModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let viewModel = declaration.as(ClassDeclSyntax.self) else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.notAClass))
      return []
    }
    guard viewModel.attributes.visorContains(named: AttributeName.observable)
    else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.missingObservable))
      return []
    }
    guard let state = viewModel.nestedViewModelState else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.missingState))
      return []
    }
    guard state.modifiers.contains(where: { $0.name.text == "final" }) else {
      context.diagnose(Diagnostic(
        node: Syntax(state),
        message: VISORDiagnostic.stateClassNotFinal))
      return []
    }
    guard !state.attributes.visorContains(named: AttributeName.observable) else {
      context.diagnose(Diagnostic(
        node: Syntax(state),
        message: VISORDiagnostic.sourceObservationRequiresPlainState))
      return []
    }

    return sourceObservationMembers(
      for: viewModel,
      state: state,
      analysis: ClassAnalysis(viewModel),
      in: context)
  }

  private static func sourceObservationMembers(
    for viewModel: ClassDeclSyntax,
    state: ClassDeclSyntax,
    analysis: ClassAnalysis,
    in context: some MacroExpansionContext
  ) -> [DeclSyntax] {
    for deinitialiser in viewModel.conditionalDeinitialisers {
      context.diagnose(Diagnostic(
        node: Syntax(deinitialiser),
        message: VISORDiagnostic.conditionalDeinitialiserUnsupported))
    }
    for deinitialiser in state.conditionalDeinitialisers {
      context.diagnose(Diagnostic(
        node: Syntax(deinitialiser),
        message: VISORDiagnostic.conditionalDeinitialiserUnsupported))
    }
    guard
      viewModel.conditionalDeinitialisers.isEmpty,
      state.conditionalDeinitialisers.isEmpty
    else {
      return []
    }

    if viewModel.hasRejectedSourceObservationDeclaration {
      viewModel.diagnoseRejectedSourceObservationDeclarations(in: context)
      return []
    }

    guard viewModel.hasExplicitMainActor, !state.hasRejectedStateField else {
      return []
    }

    guard viewModel.stableViewModelStateProperty != nil else {
      let diagnosticNode = viewModel.declaredViewModelStateProperty
        .map(Syntax.init) ?? Syntax(viewModel)
      context.diagnose(Diagnostic(
        node: diagnosticNode,
        message: VISORDiagnostic.viewModelRequiresStableState))
      return []
    }

    guard viewModel.hasConformanceCompatiblePublicState else {
      context.diagnose(Diagnostic(
        node: Syntax(viewModel),
        message: VISORDiagnostic.viewModelRequiresVisibleState))
      return []
    }

    if analysis.hasActionEnum && !analysis.hasHandleMethod {
      context.diagnose(Diagnostic(
        node: Syntax(viewModel),
        message: VISORDiagnostic.actionWithoutHandle))
    }
    if analysis.handleHasWrongLabel {
      context.diagnose(Diagnostic(
        node: Syntax(viewModel),
        message: VISORDiagnostic.handleWrongLabel))
    }

    var groups: [SourceObservationRecipeGroup] = []

    func groupIndex(for source: ExprSyntax) -> Int {
      let spelling = source.trimmedDescription
      if let index = groups.firstIndex(where: {
        $0.source.trimmedDescription == spelling
      }) {
        return index
      }
      groups.append(SourceObservationRecipeGroup(source: source))
      return groups.index(before: groups.endIndex)
    }

    for member in state.memberBlock.members {
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        stateFieldSpec(from: variable) != nil,
        let attribute = variable.attributes.visorAttribute(named: "Bound"),
        let observation = attribute.sourceObservationSelection,
        let binding = variable.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
      else {
        continue
      }
      let entry = SourceBoundRecipe(
        source: observation.source,
        selection: observation.selection,
        fieldName: identifier.identifier.text)
      groups[groupIndex(for: observation.source)].bounds.append(entry)
    }

    for member in viewModel.memberBlock.members {
      guard
        let function = member.decl.as(FunctionDeclSyntax.self),
        let attribute = function.attributes.visorAttribute(named: "Reaction"),
        let observation = attribute.sourceObservationSelection,
        function.signature.parameterClause.parameters.count == 1,
        let parameter = function.signature.parameterClause.parameters.first
      else {
        continue
      }
      let entry = SourceReactionRecipe(
        source: observation.source,
        selection: observation.selection,
        methodName: function.name.text,
        argumentLabel: parameter.firstName.text == "_"
          ? nil
          : parameter.firstName.text,
        isAsync: function.signature.effectSpecifiers?.asyncSpecifier != nil)
      groups[groupIndex(for: observation.source)].reactions.append(entry)
    }

    let access = accessLevel(of: viewModel)
    let prefix = access == "public" || access == "open" ? "public " : ""
    var members: [DeclSyntax] = [
      DeclSyntax(stringLiteral:
        "\(prefix)typealias Factory = ViewModelFactory<\(viewModel.name.text)>"),
      DeclSyntax(stringLiteral:
        "\(prefix)let _visorObservationOwnership = " +
        "VISOR._ViewModelObservationOwnership()"),
    ]

    // Swift 6.2.4 can crash in release builds while synthesising destruction
    // for explicitly MainActor-isolated macro-expanded classes. An explicit
    // empty deinitialiser avoids that optimiser defect and remains inert at
    // runtime. Preserve any user-authored deinitialiser unchanged.
    if !viewModel.hasExplicitDeinitialiser {
      members.append("deinit {}")
    }

    guard !groups.isEmpty else { return members }

    let recipes = groups.map { group in
      let projections = group.bounds.map { bound in
        let value = bound.selection.map {
          "snapshot[keyPath: \($0.trimmedDescription)]"
        } ?? "snapshot"
        return """
          { [weak self] snapshot in
            guard let self else { return }
            self.updateState(\\.\(bound.fieldName), to: \(value))
          }
          """
      }.joined(separator: ",\n")

      let reactions = group.reactions.map { reaction in
        let value = reaction.selection.map {
          "snapshot[keyPath: \($0.trimmedDescription)]"
        } ?? "snapshot"
        let argument = reaction.argumentLabel.map {
          "\($0): \(value)"
        } ?? value
        let awaitPrefix = reaction.isAsync ? "await " : ""
        return """
          { [weak self] snapshot in
            guard let self else { return }
            \(awaitPrefix)self.\(reaction.methodName)(\(argument))
          }
          """
      }.joined(separator: ",\n")

      return """
        visitor.add(
          source: self[keyPath: \(group.source.trimmedDescription)],
          projections: [
            \(projections)
          ],
          initialReactions: [
            \(reactions)
          ])
        """
    }.joined(separator: "\n")

    members.append(DeclSyntax(stringLiteral: """
      \(prefix)func _visorBuildObservationRecipe(
        into visitor: VISOR._ObservationRecipeVisitor
      ) {
        \(recipes)
      }
      """))
    return members
  }

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext
  ) throws -> [AttributeSyntax] {
    guard
      let viewModel = declaration.as(ClassDeclSyntax.self),
      let state = member.as(ClassDeclSyntax.self),
      state.name.text == "State",
      !state.attributes.visorContains(named: AttributeName.observable),
      state.modifiers.contains(where: { $0.name.text == "final" }),
      viewModel.hasExplicitMainActor,
      viewModel.attributes.visorContains(named: AttributeName.observable),
      viewModel.stableViewModelStateProperty != nil,
      viewModel.hasConformanceCompatiblePublicState,
      viewModel.conditionalDeinitialisers.isEmpty,
      state.conditionalDeinitialisers.isEmpty,
      !viewModel.hasRejectedSourceObservationDeclaration
    else {
      return []
    }

    var attributes: [AttributeSyntax] = ["@VISOR._ViewModelState"]
    if !state.hasExplicitMainActor {
      attributes.insert("@MainActor", at: 0)
    }
    return attributes
  }

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard
      let viewModel = declaration.as(ClassDeclSyntax.self),
      let state = viewModel.nestedViewModelState
    else {
      return []
    }
    guard viewModel.hasExplicitMainActor else {
      let position = viewModel.positionAfterSkippingLeadingTrivia
      context.diagnose(Diagnostic(
        node: Syntax(viewModel.name),
        message: VISORDiagnostic.viewModelRequiresMainActor,
        fixIts: [
          FixIt(
            message: ViewModelFixIt.addMainActor,
            changes: [
              .replaceText(
                range: position..<position,
                with: "@MainActor\n",
                in: Syntax(viewModel)),
            ])
        ]))
      return []
    }
    guard
      viewModel.attributes.visorContains(named: AttributeName.observable),
      !state.attributes.visorContains(named: AttributeName.observable),
      state.modifiers.contains(where: { $0.name.text == "final" }),
      !state.hasRejectedStateField,
      viewModel.conditionalDeinitialisers.isEmpty,
      state.conditionalDeinitialisers.isEmpty,
      viewModel.stableViewModelStateProperty != nil,
      viewModel.hasConformanceCompatiblePublicState,
      !viewModel.hasRejectedSourceObservationDeclaration
    else {
      return []
    }

    return [makeProtocolExtension(for: type, conformingTo: "ViewModel")]
  }
}
