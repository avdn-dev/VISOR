import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ObservationStateMacro

public struct ObservationStateMacro: AccessorMacro, PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    if context.lexicalContext.first?.is(ProtocolDeclSyntax.self) == true {
      diagnoseMissingObservationStateRequirementsIfNeeded(declaration, in: context)
      return []
    }

    guard
      let property = observationStateProperty(
        from: declaration,
        attribute: attribute,
        in: context,
        diagnose: false,
      )
    else {
      return []
    }

    let channel: DeclSyntax = """
      \(raw: property.channelModifiers)\(raw: property.channelBinding) \(raw: property.channelName):
        VISORObservation.ObservationChannel<\(raw: property.valueType)>
      """
    let sequence: DeclSyntax = """
      \(raw: property.sequenceModifiers)var \(raw: property.sequenceName):
        VISORObservation.ObservationSource<\(raw: property.valueType)> {
        \(raw: property.channelName).source
      }
      """
    let mutation: DeclSyntax = """
      @discardableResult
      private func \(raw: property.mutationName)<Result>(
        _ mutation: (inout \(raw: property.valueType)) throws -> Result
      ) rethrows -> Result {
        var updatedValue = \(raw: property.name)
        let result = try mutation(&updatedValue)
        \(raw: property.name) = updatedValue
        return result
      }
      """
    return [channel, sequence, mutation]
  }

  public static func expansion(
    of attribute: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
  ) throws -> [AccessorDeclSyntax] {
    if context.lexicalContext.first?.is(ProtocolDeclSyntax.self) == true {
      return []
    }

    guard
      let property = observationStateProperty(
        from: declaration,
        attribute: attribute,
        in: context,
        diagnose: true,
      )
    else {
      return []
    }

    let initialiser: AccessorDeclSyntax = """
      @storageRestrictions(initializes: \(raw: property.channelName))
      init(initialValue) {
        \(raw: property.channelName) = VISORObservation.ObservationChannel(initialValue)
      }
      """
    var accessors = [initialiser]

    let getter: AccessorDeclSyntax
    let setter: AccessorDeclSyntax
    if property.participatesInAppleObservation {
      getter = """
        get {
          access(keyPath: \\.\(raw: property.name))
          return \(raw: property.channelName).source.currentSnapshot()
        }
        """
      setter = """
        set {
          withMutation(keyPath: \\.\(raw: property.name)) {
            \(raw: property.channelName).publish(newValue)
          }
        }
        """
    } else {
      getter = """
        get {
          \(raw: property.channelName).source.currentSnapshot()
        }
        """
      setter = """
        set {
          \(raw: property.channelName).publish(newValue)
        }
        """
    }
    accessors.append(contentsOf: [getter, setter])
    return accessors
  }
}

// MARK: - ObservationStateRequirementMacro

public struct ObservationStateRequirementMacro: PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    if context.lexicalContext.first?.is(ProtocolDeclSyntax.self) == true {
      diagnoseMissingObservationStateRequirementsIfNeeded(declaration, in: context)
      return []
    }

    diagnoseInvalidDeclaration(declaration, in: context, if: true)
    return []
  }
}

// MARK: - ObservationStateRequirementsMacro

public struct ObservationStateRequirementsMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    guard let protocolDeclaration = declaration.as(ProtocolDeclSyntax.self) else {
      context.diagnose(Diagnostic(
        node: node,
        message: ObservationStateDiagnostic.invalidProtocol,
      ))
      return []
    }

    return protocolDeclaration.memberBlock.members.compactMap { member in
      guard
        let variable = member.decl.as(VariableDeclSyntax.self),
        let attribute = variable.attributes.visorAttribute(
          named: AttributeName.observationState
        ),
        let requirement = observationStateRequirement(
          from: variable,
          attribute: attribute,
          in: context,
          diagnose: true,
          assumeProtocolOwner: true,
        )
      else {
        return nil
      }

      return """
        \(raw: requirement.sequenceModifiers)var \(raw: requirement.sequenceName): VISORObservation.ObservationSource<\(raw: requirement.valueType)> { get }
        """
    }
  }
}

// MARK: - ObservationStateRequirement

private struct ObservationStateRequirement {
  let valueType: String
  let sequenceName: String
  let sequenceModifiers: String
}

// MARK: - ObservationStateProperty

private struct ObservationStateProperty {
  let name: String
  let valueType: String
  let sequenceName: String
  let sequenceModifiers: String
  let hasAuthoredInitialiser: Bool
  let participatesInAppleObservation: Bool

  var channelName: String {
    "__visorObservationState\(name.capitalisedFirst)Channel"
  }

  var mutationName: String {
    "withMutable\(name.capitalisedFirst)"
  }

  var channelBinding: String {
    hasAuthoredInitialiser ? "var" : "let"
  }

  var channelModifiers: String {
    // Swift invokes the init accessor again when an enclosing initialiser
    // replaces a declaration default. The storage restriction confines this
    // rebind to initialisation, but an actor-visible mutable slot must still be
    // spelt `nonisolated(unsafe)` for the compiler.
    hasAuthoredInitialiser
      ? "nonisolated(unsafe) private "
      : "nonisolated private "
  }
}

private func observationStateRequirement(
  from declaration: some DeclSyntaxProtocol,
  attribute: AttributeSyntax,
  in context: any MacroExpansionContext,
  diagnose: Bool,
  assumeProtocolOwner: Bool = false,
) -> ObservationStateRequirement? {
  guard
    assumeProtocolOwner
    || context.lexicalContext.first?.is(ProtocolDeclSyntax.self) == true
  else {
    return nil
  }
  guard
    let variable = declaration.as(VariableDeclSyntax.self),
    variable.bindingSpecifier.tokenKind == .keyword(.var),
    variable.bindings.count == 1,
    let binding = variable.bindings.first,
    let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
    let type = binding.typeAnnotation?.type,
    !isObservationSource(type),
    binding.initializer == nil,
    isReadOnlyRequirement(binding),
    !variable.modifiers.contains(where: isStaticModifier)
  else {
    diagnoseInvalidDeclaration(declaration, in: context, if: diagnose)
    return nil
  }

  guard
    let arguments = parseArguments(
      attribute,
      declaration: declaration,
      in: context,
      shouldDiagnose: diagnose,
    )
  else {
    return nil
  }
  let propertyName = identifier.identifier.text
  let sequenceName = arguments.sequenceNaming.memberName(for: propertyName)
  guard
    validateGeneratedNames(
      stateName: propertyName,
      sequenceName: sequenceName,
      channelName: nil,
      declaration: declaration,
      in: context,
      shouldDiagnose: diagnose,
    )
  else {
    return nil
  }

  return ObservationStateRequirement(
    valueType: type.trimmedDescription,
    sequenceName: sequenceName,
    sequenceModifiers: protocolSequenceModifiers(from: variable),
  )
}

private func diagnoseMissingObservationStateRequirementsIfNeeded(
  _ declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
) {
  guard
    let owner = context.lexicalContext.first?.as(ProtocolDeclSyntax.self),
    !owner.attributes.visorContains(named: "ObservationStateRequirements")
  else {
    return
  }
  context.diagnose(Diagnostic(
    node: Syntax(declaration),
    message: ObservationStateDiagnostic.missingObservationStateRequirements,
  ))
}

private func observationStateProperty(
  from declaration: some DeclSyntaxProtocol,
  attribute: AttributeSyntax,
  in context: any MacroExpansionContext,
  diagnose shouldDiagnose: Bool,
) -> ObservationStateProperty? {
  let owner = context.lexicalContext.first
  let hasReferenceOwner = owner?.is(ClassDeclSyntax.self) == true
    || owner?.is(ActorDeclSyntax.self) == true
  guard
    hasReferenceOwner,
    let variable = declaration.as(VariableDeclSyntax.self),
    variable.bindingSpecifier.tokenKind == .keyword(.var),
    variable.bindings.count == 1,
    let binding = variable.bindings.first,
    let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
    binding.accessorBlock == nil,
    !variable.modifiers.contains(where: isStaticModifier),
    !variable.modifiers.contains(where: isUnsupportedStorageModifier)
  else {
    diagnoseInvalidDeclaration(declaration, in: context, if: shouldDiagnose)
    return nil
  }

  let valueType: String
  if let type = binding.typeAnnotation?.type {
    guard !isObservationSource(type) else {
      diagnoseInvalidDeclaration(declaration, in: context, if: shouldDiagnose)
      return nil
    }
    valueType = type.trimmedDescription
  } else if
    let initialValue = binding.initializer?.value,
    let inferredType = inferredConcreteStateType(from: initialValue)
  {
    guard !isObservationSourceTypeName(inferredType) else {
      diagnoseInvalidDeclaration(declaration, in: context, if: shouldDiagnose)
      return nil
    }
    valueType = inferredType
  } else {
    diagnose(
      declaration,
      in: context,
      with: .uninferableConcreteType,
      if: shouldDiagnose,
    )
    return nil
  }

  let observableOwner = isObservable(owner)
  guard !observableOwner || hasRequiredObservationIgnoredPlacement(variable) else {
    diagnoseMissingObservationIgnored(declaration, in: context, if: shouldDiagnose)
    return nil
  }

  guard
    let arguments = parseArguments(
      attribute,
      declaration: declaration,
      in: context,
      shouldDiagnose: shouldDiagnose,
    )
  else {
    return nil
  }

  let hasAuthoredInitialiser = binding.initializer != nil
  guard arguments.initialValueExpression == nil else {
    diagnoseInvalidDeclaration(declaration, in: context, if: shouldDiagnose)
    return nil
  }

  let propertyName = identifier.identifier.text
  let sequenceName = arguments.sequenceNaming.memberName(for: propertyName)
  let channelName = "__visorObservationState\(propertyName.capitalisedFirst)Channel"
  let mutationName = "withMutable\(propertyName.capitalisedFirst)"
  guard
    validateGeneratedNames(
      stateName: propertyName,
      sequenceName: sequenceName,
      channelName: channelName,
      mutationName: mutationName,
      declaration: declaration,
      in: context,
      shouldDiagnose: shouldDiagnose,
    )
  else {
    return nil
  }

  return ObservationStateProperty(
    name: propertyName,
    valueType: valueType,
    sequenceName: sequenceName,
    sequenceModifiers: sequenceModifiers(from: variable),
    hasAuthoredInitialiser: hasAuthoredInitialiser,
    participatesInAppleObservation: observableOwner,
  )
}

/// Infers only types that are unambiguous from the authored syntax without
/// semantic type information. These are the declaration forms SwiftFormat can
/// produce when removing a redundant concrete type annotation.
private func inferredConcreteStateType(from expression: ExprSyntax) -> String? {
  if expression.is(BooleanLiteralExprSyntax.self) {
    return "Bool"
  }
  if expression.is(IntegerLiteralExprSyntax.self) {
    return "Int"
  }
  if expression.is(FloatLiteralExprSyntax.self) {
    return "Double"
  }
  if expression.is(StringLiteralExprSyntax.self) {
    return "String"
  }
  if
    let prefix = expression.as(PrefixOperatorExprSyntax.self),
    prefix.operator.text == "+" || prefix.operator.text == "-"
  {
    if prefix.expression.is(IntegerLiteralExprSyntax.self) {
      return "Int"
    }
    if prefix.expression.is(FloatLiteralExprSyntax.self) {
      return "Double"
    }
  }

  if let call = expression.as(FunctionCallExprSyntax.self) {
    if let type = explicitTypeReference(from: call.calledExpression) {
      return type
    }
    if
      let member = call.calledExpression.as(MemberAccessExprSyntax.self),
      member.declName.baseName.tokenKind == .keyword(.`init`),
      let base = member.base
    {
      return explicitTypeReference(from: base)
    }
    return nil
  }

  guard
    let member = expression.as(MemberAccessExprSyntax.self),
    member.declName.baseName.tokenKind != .keyword(.self),
    let base = member.base
  else {
    return nil
  }
  return explicitTypeReference(from: base)
}

private func explicitTypeReference(from expression: ExprSyntax) -> String? {
  if
    let array = expression.as(ArrayExprSyntax.self),
    array.elements.count == 1,
    let element = array.elements.first,
    element.trailingComma == nil,
    let elementType = explicitTypeReference(from: element.expression)
  {
    return "[\(elementType)]"
  }

  if let typeExpression = expression.as(TypeExprSyntax.self) {
    return typeExpression.type.trimmedDescription
  }

  if let reference = expression.as(DeclReferenceExprSyntax.self) {
    let name = reference.baseName.text
    return isTypeNameComponent(name) ? reference.trimmedDescription : nil
  }

  if let specialisation = expression.as(GenericSpecializationExprSyntax.self) {
    guard explicitTypeReference(from: specialisation.expression) != nil else {
      return nil
    }
    return specialisation.trimmedDescription
  }

  if
    let member = expression.as(MemberAccessExprSyntax.self),
    let base = member.base,
    explicitTypeReference(from: base) != nil,
    isTypeNameComponent(member.declName.baseName.text)
  {
    return member.trimmedDescription
  }

  return nil
}

private func isTypeNameComponent(_ name: String) -> Bool {
  let unescaped = name.first == "`" && name.last == "`"
    ? String(name.dropFirst().dropLast())
    : name
  guard let first = unescaped.first else { return false }
  return first == "_" || first.isUppercase
}

private func isObservationSourceTypeName(_ type: String) -> Bool {
  let base = type.prefix { $0 != "<" }
    .filter { !$0.isWhitespace }
    .split(separator: ".")
    .last
  return base == "ObservationSource"
}

private func parseArguments(
  _ attribute: AttributeSyntax,
  declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  shouldDiagnose: Bool,
) -> ObservationStateArguments? {
  switch ObservationStateArguments.parse(from: attribute) {
  case .success(let arguments):
    return arguments

  case .failure(.invalidArguments):
    diagnose(declaration, in: context, with: .invalidArguments, if: shouldDiagnose)
    return nil

  case .failure(.invalidCustomName):
    diagnose(declaration, in: context, with: .invalidCustomName, if: shouldDiagnose)
    return nil
  }
}

private func validateGeneratedNames(
  stateName: String,
  sequenceName: String,
  channelName: String?,
  mutationName: String? = nil,
  declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  shouldDiagnose: Bool,
) -> Bool {
  let generatedNames = [sequenceName] + [channelName, mutationName].compactMap { $0 }
  var reservedNames = Set([stateName])
  for name in generatedNames where !reservedNames.insert(name).inserted {
    diagnose(
      declaration,
      in: context,
      with: .generatedNameCollision(name),
      if: shouldDiagnose,
    )
    return false
  }

  let names = enclosingMemberNames(
    excludingStateNamed: stateName,
    around: declaration,
    in: context,
  )
  if
    names.contains(sequenceName)
    || channelName.map(names.contains) == true
    || mutationName.map(names.contains) == true
  {
    let collision =
      if names.contains(sequenceName) {
        sequenceName
      } else if let channelName, names.contains(channelName) {
        channelName
      } else {
        mutationName ?? sequenceName
      }
    diagnose(declaration, in: context, with: .generatedNameCollision(collision), if: shouldDiagnose)
    return false
  }
  return true
}

private func enclosingMemberNames(
  excludingStateNamed stateName: String,
  around declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
) -> Set<String> {
  let ancestorMembers: MemberBlockItemListSyntax? = {
    var ancestor = Syntax(declaration).parent
    while let node = ancestor {
      if let memberBlock = node.as(MemberBlockSyntax.self) {
        return memberBlock.members
      }
      ancestor = node.parent
    }
    return nil
  }()

  let members: MemberBlockItemListSyntax? =
    if let ancestorMembers {
      ancestorMembers
    } else if let type = context.lexicalContext.first?.as(ClassDeclSyntax.self) {
      type.memberBlock.members
    } else if let type = context.lexicalContext.first?.as(ActorDeclSyntax.self) {
      type.memberBlock.members
    } else if let type = context.lexicalContext.first?.as(ProtocolDeclSyntax.self) {
      type.memberBlock.members
    } else {
      nil
    }

  var names = Set<String>()
  for member in members ?? [] {
    if
      let variable = member.decl.as(VariableDeclSyntax.self),
      variable.bindings.count == 1,
      let binding = variable.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
    {
      let name = identifier.identifier.text
      names.insert(name)
      if
        name != stateName,
        let attribute = variable.attributes.visorAttribute(named: AttributeName.observationState),
        case .success(let arguments) = ObservationStateArguments.parse(from: attribute)
      {
        names.insert(arguments.sequenceNaming.memberName(for: name))
      }
      continue
    }

    if let function = member.decl.as(FunctionDeclSyntax.self) {
      names.insert(function.name.text)
    } else if let typealiasDeclaration = member.decl.as(TypeAliasDeclSyntax.self) {
      names.insert(typealiasDeclaration.name.text)
    } else if let classDeclaration = member.decl.as(ClassDeclSyntax.self) {
      names.insert(classDeclaration.name.text)
    } else if let actorDeclaration = member.decl.as(ActorDeclSyntax.self) {
      names.insert(actorDeclaration.name.text)
    } else if let structDeclaration = member.decl.as(StructDeclSyntax.self) {
      names.insert(structDeclaration.name.text)
    } else if let enumDeclaration = member.decl.as(EnumDeclSyntax.self) {
      names.insert(enumDeclaration.name.text)
    } else if let protocolDeclaration = member.decl.as(ProtocolDeclSyntax.self) {
      names.insert(protocolDeclaration.name.text)
    }
  }
  return names
}

private func sequenceModifiers(from variable: VariableDeclSyntax) -> String {
  "nonisolated " + variable.modifiers.compactMap { modifier -> String? in
    guard modifier.detail == nil else { return nil }
    switch modifier.name.tokenKind {
    case .keyword(.public), .keyword(.package), .keyword(.fileprivate),
         .keyword(.private):
      return "\(modifier.trimmedDescription) "
    case .keyword(.open):
      return "public "
    default:
      return nil
    }
  }.joined()
}

private func protocolSequenceModifiers(from _: VariableDeclSyntax) -> String {
  "nonisolated "
}

private func isStaticModifier(_ modifier: DeclModifierSyntax) -> Bool {
  modifier.name.tokenKind == .keyword(.static)
    || modifier.name.tokenKind == .keyword(.class)
}

private func isUnsupportedStorageModifier(_ modifier: DeclModifierSyntax) -> Bool {
  switch modifier.name.tokenKind {
  case .keyword(.lazy), .keyword(.weak), .keyword(.unowned):
    true
  default:
    false
  }
}

private func isReadOnlyRequirement(_ binding: PatternBindingSyntax) -> Bool {
  guard
    let accessorBlock = binding.accessorBlock,
    case .accessors(let accessors) = accessorBlock.accessors
  else {
    return false
  }
  return accessors.count == 1
    && accessors.first?.accessorSpecifier.tokenKind == .keyword(.get)
}

private func isObservationSource(_ type: TypeSyntax) -> Bool {
  if let identifier = type.as(IdentifierTypeSyntax.self) {
    return identifier.name.text == "ObservationSource"
  }
  if let member = type.as(MemberTypeSyntax.self) {
    return member.name.text == "ObservationSource"
  }
  return false
}

private func isObservable(_ owner: Syntax?) -> Bool {
  if let owner = owner?.as(ClassDeclSyntax.self) {
    return owner.attributes.visorContains(named: "Observable")
  }
  if let owner = owner?.as(ActorDeclSyntax.self) {
    return owner.attributes.visorContains(named: "Observable")
  }
  return false
}

private func hasRequiredObservationIgnoredPlacement(
  _ variable: VariableDeclSyntax
) -> Bool {
  let names = variable.attributes.compactMap { element -> String? in
    guard let attribute = element.as(AttributeSyntax.self) else { return nil }
    return attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init)
  }
  guard
    let stateIndex = names.firstIndex(of: AttributeName.observationState),
    names.indices.contains(stateIndex + 1)
  else {
    return false
  }
  return names[stateIndex + 1] == "ObservationIgnored"
}

private func diagnoseInvalidDeclaration(
  _ declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  if shouldDiagnose: Bool,
) {
  diagnose(declaration, in: context, with: .invalidDeclaration, if: shouldDiagnose)
}

private func diagnoseMissingObservationIgnored(
  _ declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  if shouldDiagnose: Bool,
) {
  diagnose(
    declaration,
    in: context,
    with: .missingObservationIgnored,
    if: shouldDiagnose,
  )
}

private func diagnose(
  _ declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  with message: ObservationStateDiagnostic,
  if shouldDiagnose: Bool,
) {
  guard shouldDiagnose else { return }
  context.diagnose(Diagnostic(node: Syntax(declaration), message: message))
}

// MARK: - ObservationStateDiagnostic

private enum ObservationStateDiagnostic: DiagnosticMessage {
  case invalidDeclaration
  case uninferableConcreteType
  case invalidArguments
  case invalidCustomName
  case missingObservationIgnored
  case generatedNameCollision(String)
  case invalidProtocol
  case missingObservationStateRequirements

  // MARK: Internal

  var message: String {
    switch self {
    case .invalidDeclaration:
      "@ObservationState requires mutable class or actor State with an explicit or inferable concrete type and no initial: argument, or a get-only protocol State"
    case .uninferableConcreteType:
      "@ObservationState cannot infer the concrete State type from this initialiser; add an explicit type annotation"
    case .invalidArguments:
      "@ObservationState accepts only initial: and observedAs: .snapshots, .values, or .named(\"memberName\")"
    case .invalidCustomName:
      "@ObservationState observedAs: .named requires a valid Swift identifier string literal"
    case .missingObservationIgnored:
      "@ObservationState properties in an @Observable type require @ObservationIgnored immediately below @ObservationState"
    case .generatedNameCollision(let name):
      "@ObservationState cannot generate '\(name)' because that member name is already in use"
    case .invalidProtocol:
      "@ObservationStateRequirements can only be attached to a protocol"
    case .missingObservationStateRequirements:
      "protocol @ObservationState requirements require @ObservationStateRequirements on the enclosing protocol"
    }
  }

  var diagnosticID: MessageID {
    let id =
      switch self {
      case .invalidDeclaration: "invalidDeclaration"
      case .uninferableConcreteType: "uninferableConcreteType"
      case .invalidArguments: "invalidArguments"
      case .invalidCustomName: "invalidCustomName"
      case .missingObservationIgnored: "missingObservationIgnored"
      case .generatedNameCollision: "generatedNameCollision"
      case .invalidProtocol: "invalidProtocol"
      case .missingObservationStateRequirements: "missingObservationStateRequirements"
      }
    return MessageID(domain: "VISOR", id: id)
  }

  var severity: DiagnosticSeverity {
    .error
  }
}
