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
  let selection: ExprSyntax?
  let fieldName: String
}

private struct SourceReactionRecipe {
  let selection: ExprSyntax?
  let methodName: String
  let argumentLabel: String?
  let isAsync: Bool
}

private struct SourceObservationRecipeGroup {
  let source: ExprSyntax
  let sourceComponents: [String]?
  var bounds: [SourceBoundRecipe] = []
  var reactions: [SourceReactionRecipe] = []
}

private struct ViewModelDependency {
  let name: String
  let parameterType: String
}

private struct StateInitialisationArgument {
  let label: String?
  let source: ExprSyntax
  let selection: ExprSyntax?
}

private struct StateInitialisation {
  let snapshotReads: [String]
  let arguments: [String]
}

private struct ViewModelSynthesisPlan {
  let stateDeclaration: DeclSyntax?
  let initialiserDeclaration: DeclSyntax?
}

private func viewModelInitialiserParameterType(
  for type: TypeSyntax
) -> String {
  let typeString = type.trimmedDescription
  guard type.isTopLevelViewModelFunctionType else { return typeString }
  guard !typeString.contains("@escaping") else { return typeString }
  return "@escaping \(typeString)"
}

private extension TypeSyntax {
  var isTopLevelViewModelFunctionType: Bool {
    if self.is(FunctionTypeSyntax.self) { return true }
    if let attributedType = self.as(AttributedTypeSyntax.self) {
      return attributedType.baseType.isTopLevelViewModelFunctionType
    }
    if
      let tupleType = self.as(TupleTypeSyntax.self),
      tupleType.elements.count == 1,
      let element = tupleType.elements.first
    {
      return element.type.isTopLevelViewModelFunctionType
    }
    return false
  }

  var hasImplicitNilInitialValue: Bool {
    if self.is(OptionalTypeSyntax.self) ||
       self.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
    {
      return true
    }
    if let identifier = self.as(IdentifierTypeSyntax.self) {
      return identifier.name.text == "Optional" &&
        identifier.genericArgumentClause?.arguments.count == 1
    }
    guard
      let member = self.as(MemberTypeSyntax.self),
      member.name.text == "Optional",
      member.genericArgumentClause?.arguments.count == 1,
      let base = member.baseType.as(IdentifierTypeSyntax.self)
    else {
      return false
    }
    return base.name.text == "Swift" && base.genericArgumentClause == nil
  }

  var isViewModelStateType: Bool {
    guard let identifier = self.as(IdentifierTypeSyntax.self) else {
      return false
    }
    return identifier.name.text == "State" &&
      identifier.genericArgumentClause == nil
  }
}

private extension ExprSyntax {
  var isViewModelStateInitialiserReference: Bool {
    if let reference = self.as(DeclReferenceExprSyntax.self) {
      return reference.baseName.text == "State"
    }
    guard
      let member = self.as(MemberAccessExprSyntax.self),
      member.declName.baseName.text == "init",
      let base = member.base?.as(DeclReferenceExprSyntax.self)
    else {
      return false
    }
    return base.baseName.text == "State"
  }
}

private func keyPathPropertyComponents(
  from expression: ExprSyntax,
  ownerName: String
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
          if binding.typeAnnotation?.type.isViewModelStateType == true {
            return true
          }
          guard
            let call = binding.initializer?.value.as(
              FunctionCallExprSyntax.self)
          else {
            return false
          }
          return call.calledExpression.isViewModelStateInitialiserReference
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

  var hasExplicitViewModelInitialiser: Bool {
    memberBlock.members.contains { $0.decl.is(InitializerDeclSyntax.self) }
  }

  func viewModelSynthesisPlan(
    state: ClassDeclSyntax
  ) -> ViewModelSynthesisPlan? {
    if declaredViewModelStateProperty != nil,
       stableViewModelStateProperty == nil
    {
      return nil
    }

    if hasExplicitViewModelInitialiser {
      guard stableViewModelStateProperty != nil else { return nil }
      return ViewModelSynthesisPlan(
        stateDeclaration: nil,
        initialiserDeclaration: nil)
    }

    guard let dependencies = synthesisedViewModelDependencies else {
      return nil
    }

    let generatesState = stableViewModelStateProperty == nil
    let authoredStateNeedsAssignment = stableViewModelStateProperty?
      .bindings.first?.initializer == nil
    let needsStateInitialisation = generatesState || authoredStateNeedsAssignment

    let stateInitialisation: StateInitialisation?
    if needsStateInitialisation {
      guard let initialisation = synthesisedStateInitialisation(
        state: state,
        dependencies: dependencies)
      else {
        return nil
      }
      stateInitialisation = initialisation
    } else {
      stateInitialisation = nil
    }

    let access = accessLevel(of: self)
    let prefix = access == "public" || access == "open" ? "public " : ""
    let stateDeclaration: DeclSyntax? = generatesState
      ? DeclSyntax(stringLiteral: "\(prefix)let state: State")
      : nil

    guard !dependencies.isEmpty || needsStateInitialisation else {
      return ViewModelSynthesisPlan(
        stateDeclaration: stateDeclaration,
        initialiserDeclaration: nil)
    }

    let parameters = dependencies.map {
      "\($0.name): \($0.parameterType)"
    }.joined(separator: ", ")
    var body = dependencies.map { "self.\($0.name) = \($0.name)" }

    if let stateInitialisation {
      body.append(contentsOf: stateInitialisation.snapshotReads)
      if stateInitialisation.arguments.isEmpty {
        body.append("self.state = State()")
      } else {
        let arguments = stateInitialisation.arguments
          .joined(separator: ",\n  ")
        body.append("""
          self.state = State(
            \(arguments))
          """)
      }
    }

    let bodySource = body.joined(separator: "\n")
    let initialiser: DeclSyntax = DeclSyntax(stringLiteral: """
      \(prefix)init(\(parameters)) {
        \(bodySource)
      }
      """)
    return ViewModelSynthesisPlan(
      stateDeclaration: stateDeclaration,
      initialiserDeclaration: initialiser)
  }

  private var synthesisedViewModelDependencies: [ViewModelDependency]? {
    var dependencies: [ViewModelDependency] = []

    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else {
        continue
      }
      if variable.modifiers.contains(where: {
        $0.name.text == "static" || $0.name.text == "class"
      }) {
        continue
      }

      for binding in variable.bindings where
        binding.accessorBlock == nil && binding.initializer == nil
      {
        if variable.bindingSpecifier.text == "var" {
          guard binding.typeAnnotation?.type.hasImplicitNilInitialValue == true
          else {
            return nil
          }
          continue
        }
        guard
          variable.bindingSpecifier.text == "let",
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          let type = binding.typeAnnotation?.type
        else {
          return nil
        }
        let name = identifier.identifier.text
        if name == "state" { continue }
        dependencies.append(ViewModelDependency(
          name: name,
          parameterType: viewModelInitialiserParameterType(for: type)))
      }
    }

    return dependencies
  }

  private func synthesisedStateInitialisation(
    state: ClassDeclSyntax,
    dependencies: [ViewModelDependency]
  ) -> StateInitialisation? {
    let initialisers = state.memberBlock.members.compactMap {
      $0.decl.as(InitializerDeclSyntax.self)
    }

    if initialisers.isEmpty {
      guard stateCanUseImplicitInitialiser(state) else { return nil }
      return StateInitialisation(snapshotReads: [], arguments: [])
    }

    guard initialisers.count == 1, let initialiser = initialisers.first else {
      return nil
    }
    guard
      initialiser.optionalMark == nil,
      initialiser.genericParameterClause == nil,
      initialiser.signature.effectSpecifiers == nil
    else {
      return nil
    }

    let dependencyNames = Set(dependencies.map(\.name))
    let bounds = sourceBoundStateFields(in: state)
    var arguments: [StateInitialisationArgument] = []

    for parameter in initialiser.signature.parameterClause.parameters {
      guard parameter.ellipsis == nil else { return nil }
      let internalName = parameter.secondName?.text
        ?? parameter.firstName.text
      if let bound = bounds[internalName] {
        guard sourceAccessComponents(
          from: bound.source,
          dependencyNames: dependencyNames) != nil
        else {
          return nil
        }
        arguments.append(StateInitialisationArgument(
          label: parameter.firstName.text == "_"
            ? nil
            : parameter.firstName.text,
          source: bound.source,
          selection: bound.selection))
      } else if parameter.defaultValue == nil {
        return nil
      }
    }

    var sources: [[String]] = []
    func sourceIndex(for argument: StateInitialisationArgument) -> Int? {
      guard let accessComponents = sourceAccessComponents(
        from: argument.source,
        dependencyNames: dependencyNames)
      else {
        return nil
      }
      if let index = sources.firstIndex(of: accessComponents) {
        return index
      }
      sources.append(accessComponents)
      return sources.index(before: sources.endIndex)
    }

    var renderedArguments: [String] = []
    for argument in arguments {
      guard let index = sourceIndex(for: argument) else { return nil }
      let snapshot = "_visorInitialSource\(index)"
      let value = argument.selection.map {
        "\(snapshot)[keyPath: \($0.trimmedDescription)]"
      } ?? snapshot
      renderedArguments.append(argument.label.map {
        "\($0): \(value)"
      } ?? value)
    }

    let reads = sources.enumerated().map { index, accessComponents in
      "let _visorInitialSource\(index) = " +
        "\(accessComponents.joined(separator: ".")).currentSnapshot()"
    }
    return StateInitialisation(
      snapshotReads: reads,
      arguments: renderedArguments)
  }

  private func sourceBoundStateFields(
    in state: ClassDeclSyntax
  ) -> [String: SourceObservationSelection] {
    var fields: [String: SourceObservationSelection] = [:]
    for member in state.memberBlock.members {
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        let attribute = variable.attributes.visorAttribute(named: "Bound"),
        let observation = attribute.sourceObservationSelection,
        let binding = variable.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
      else {
        continue
      }
      fields[identifier.identifier.text] = observation
    }
    return fields
  }

  private func stateCanUseImplicitInitialiser(
    _ state: ClassDeclSyntax
  ) -> Bool {
    for member in state.memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else {
        continue
      }
      if variable.modifiers.contains(where: {
        $0.name.text == "static" || $0.name.text == "class"
      }) {
        continue
      }
      if variable.bindings.contains(where: {
        $0.accessorBlock == nil &&
          $0.initializer == nil &&
          $0.typeAnnotation?.type.hasImplicitNilInitialValue != true
      }) {
        return false
      }
    }
    return true
  }

  private func sourceAccessComponents(
    from expression: ExprSyntax,
    dependencyNames: Set<String>
  ) -> [String]? {
    guard
      let components = keyPathPropertyComponents(
        from: expression,
        ownerName: name.text),
      let dependency = components.first,
      dependencyNames.contains(dependency)
    else {
      return nil
    }
    return components
  }

  func hasStableOrSynthesisedState(state: ClassDeclSyntax) -> Bool {
    stableViewModelStateProperty != nil ||
      viewModelSynthesisPlan(state: state)?.stateDeclaration != nil
  }

  var hasConformanceCompatiblePublicState: Bool {
    let access = accessLevel(of: self)
    guard access == "public" || access == "open" else { return true }
    guard let state = nestedViewModelState else { return false }
    let stateAccess = accessLevel(of: state)
    guard stateAccess == "public" || stateAccess == "open" else {
      return false
    }
    if let stateProperty = stableViewModelStateProperty {
      return stateProperty.modifiers.stateFieldAccessPrefix == "public "
    }
    return viewModelSynthesisPlan(state: state)?.stateDeclaration != nil
  }

  var hasRejectedSourceObservationDeclaration: Bool {
    guard let state = nestedViewModelState else { return false }

    for member in state.memberBlock.members {
      let attributes = observationRoutingAttributes(on: member.decl)
      let bounds = attributes.filter {
        routingMarkerName($0) == AttributeName.bound
      }
      let hasOtherRoutingMarker = attributes.contains {
        routingMarkerName($0) == AttributeName.reaction
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
      if bounds.count > 1 {
        context.diagnose(Diagnostic(
          node: Syntax(member.decl),
          message: VISORDiagnostic.invalidSourceBoundDeclaration))
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
      if reactions.count > 1 {
        context.diagnose(Diagnostic(
          node: Syntax(member.decl),
          message: VISORDiagnostic.invalidSourceReactionDeclaration))
      }
      for attribute in attributes where
        routingMarkerName(attribute) == AttributeName.bound
      {
        context.diagnose(Diagnostic(
          node: Syntax(attribute),
          message: VISORDiagnostic.invalidSourceBoundPlacement))
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

    let synthesisPlan = viewModel.viewModelSynthesisPlan(state: state)
    guard viewModel.hasStableOrSynthesisedState(state: state) else {
      let diagnosticNode = viewModel.declaredViewModelStateProperty
        .map(Syntax.init) ?? Syntax(viewModel)
      context.diagnose(Diagnostic(
        node: diagnosticNode,
        message: viewModel.declaredViewModelStateProperty == nil
          ? VISORDiagnostic.viewModelRequiresInitialisation
          : VISORDiagnostic.viewModelRequiresStableState))
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
      let components = keyPathPropertyComponents(
        from: source,
        ownerName: viewModel.name.text)
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
        sourceComponents: components))
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

    if let stateDeclaration = synthesisPlan?.stateDeclaration {
      members.append(stateDeclaration)
    }
    if let initialiserDeclaration = synthesisPlan?.initialiserDeclaration {
      members.append(initialiserDeclaration)
    }

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
      viewModel.hasStableOrSynthesisedState(state: state),
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
      viewModel.hasStableOrSynthesisedState(state: state),
      viewModel.hasConformanceCompatiblePublicState,
      !viewModel.hasRejectedSourceObservationDeclaration
    else {
      return []
    }

    return [makeProtocolExtension(for: type, conformingTo: "ViewModel")]
  }
}
