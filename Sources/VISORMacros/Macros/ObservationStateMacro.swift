import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ObservationStateMacro: AccessorMacro, PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    if observationStateRequirement(
      from: declaration,
      attribute: attribute,
      in: context,
      diagnose: false) != nil
    {
      return []
    }

    guard let property = observationStateProperty(
      from: declaration,
      attribute: attribute,
      in: context,
      diagnose: false
    ) else {
      return []
    }

    let channel: DeclSyntax = """
      \(raw: property.channelModifiers)let _\(raw: property.name)Channel:
        VISORObservation.ObservationChannel<\(raw: property.valueType)> =
        VISORObservation.ObservationChannel(\(raw: property.initialValue))
      """

    switch property {
    case .source(let source):
      let publisher: DeclSyntax = """
        private func publish\(raw: source.name.capitalisedFirst)(
          _ snapshot: sending \(raw: source.valueType)
        ) {
          _\(raw: source.name)Channel.publish(snapshot)
        }
        """
      return [channel, publisher]

    case .value(let value):
      let source: DeclSyntax = """
        \(raw: value.sourceModifiers)var \(raw: value.name)Source:
          VISORObservation.ObservationSource<\(raw: value.valueType)> {
          _\(raw: value.name)Channel.source
        }
        """
      return [channel, source]
    }
  }

  public static func expansion(
    of attribute: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AccessorDeclSyntax] {
    if observationStateRequirement(
      from: declaration,
      attribute: attribute,
      in: context,
      diagnose: false) != nil
    {
      return []
    }

    guard let property = observationStateProperty(
      from: declaration,
      attribute: attribute,
      in: context,
      diagnose: true
    ) else {
      return []
    }

    switch property {
    case .source(let source):
      let getter: AccessorDeclSyntax = """
        get {
          _\(raw: source.name)Channel.source
        }
        """
      return [getter]

    case .value(let value):
      let initialiser: AccessorDeclSyntax = """
        @storageRestrictions(accesses: _\(raw: value.name)Channel)
        init(initialValue) {
          _\(raw: value.name)Channel.publish(initialValue)
        }
        """
      let getter: AccessorDeclSyntax = """
        get {
          _\(raw: value.name)Channel.source.currentSnapshot()
        }
        """
      let setter: AccessorDeclSyntax = """
        set {
          _\(raw: value.name)Channel.publish(newValue)
        }
        """

      return [initialiser, getter, setter]
    }
  }
}

private func observationStateRequirement(
  from declaration: some DeclSyntaxProtocol,
  attribute: AttributeSyntax,
  in context: any MacroExpansionContext,
  diagnose: Bool
) -> Bool? {
  guard context.lexicalContext.first?.is(ProtocolDeclSyntax.self) == true else {
    return nil
  }
  guard
    let variable = declaration.as(VariableDeclSyntax.self),
    variable.bindingSpecifier.tokenKind == .keyword(.var),
    variable.bindings.count == 1,
    let binding = variable.bindings.first,
    binding.pattern.is(IdentifierPatternSyntax.self),
    let type = binding.typeAnnotation?.type,
    binding.initializer == nil,
    binding.accessorBlock != nil,
    !variable.modifiers.contains(where: isStaticModifier)
  else {
    diagnoseInvalidObservationState(declaration, in: context, if: diagnose)
    return nil
  }

  let initialValue = observationStateInitialValue(from: attribute)
  let sourceValueType = observationSourceValueType(from: type)
  let isValid = if initialValue != nil {
    sourceValueType != nil && isReadOnlyRequirement(binding)
  } else {
    sourceValueType == nil
  }

  guard isValid else {
    diagnoseInvalidObservationState(declaration, in: context, if: diagnose)
    return nil
  }
  return true
}

private enum ObservationStateProperty {
  case source(ObservationSourceProperty)
  case value(ObservationValueProperty)

  var name: String {
    switch self {
    case .source(let property): property.name
    case .value(let property): property.name
    }
  }

  var valueType: String {
    switch self {
    case .source(let property): property.valueType
    case .value(let property): property.valueType
    }
  }

  var initialValue: String {
    switch self {
    case .source(let property): property.initialValue
    case .value(let property): property.initialValue
    }
  }

  var channelModifiers: String {
    switch self {
    case .source(let property): property.channelModifiers
    case .value(let property): property.channelModifiers
    }
  }
}

private struct ObservationSourceProperty {
  let name: String
  let valueType: String
  let initialValue: String
  let isNonisolated: Bool

  var channelModifiers: String {
    isNonisolated ? "nonisolated private " : "private "
  }
}

private struct ObservationValueProperty {
  let name: String
  let valueType: String
  let initialValue: String
  let sourceModifiers: String

  var channelModifiers: String {
    sourceModifiers.contains("nonisolated ")
      ? "nonisolated private "
      : "private "
  }
}

private func observationStateProperty(
  from declaration: some DeclSyntaxProtocol,
  attribute: AttributeSyntax,
  in context: any MacroExpansionContext,
  diagnose: Bool
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
    let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
    let type = binding.typeAnnotation?.type,
    binding.accessorBlock == nil,
    !variable.modifiers.contains(where: isStaticModifier)
  else {
    diagnoseInvalidObservationState(declaration, in: context, if: diagnose)
    return nil
  }

  let initialArgument = observationStateInitialValue(from: attribute)
  let sourceValueType = observationSourceValueType(from: type)

  if let initialArgument, let sourceValueType {
    return .source(ObservationSourceProperty(
      name: name,
      valueType: sourceValueType,
      initialValue: initialArgument,
      isNonisolated: variable.modifiers.contains(where: isNonisolatedModifier)))
  }

  if initialArgument == nil,
     sourceValueType == nil,
     let initialiser = binding.initializer?.value.trimmedDescription
  {
    return .value(ObservationValueProperty(
      name: name,
      valueType: type.trimmedDescription,
      initialValue: initialiser,
      sourceModifiers: sourceModifiers(from: variable)))
  }

  diagnoseInvalidObservationState(declaration, in: context, if: diagnose)
  return nil
}

private func observationStateInitialValue(from attribute: AttributeSyntax) -> String? {
  guard
    let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
    arguments.count == 1,
    let argument = arguments.first,
    argument.label?.text == "initial"
  else {
    return nil
  }
  return argument.expression.trimmedDescription
}

private func observationSourceValueType(from type: TypeSyntax) -> String? {
  let arguments: GenericArgumentListSyntax?
  if let identifier = type.as(IdentifierTypeSyntax.self),
     identifier.name.text == "ObservationSource"
  {
    arguments = identifier.genericArgumentClause?.arguments
  } else if let member = type.as(MemberTypeSyntax.self),
            member.name.text == "ObservationSource"
  {
    arguments = member.genericArgumentClause?.arguments
  } else {
    return nil
  }

  guard arguments?.count == 1, let valueType = arguments?.first?.argument else {
    return nil
  }
  return valueType.trimmedDescription
}

private func sourceModifiers(from variable: VariableDeclSyntax) -> String {
  variable.modifiers.compactMap { modifier -> String? in
    guard modifier.detail == nil else { return nil }
    switch modifier.name.tokenKind {
    case .keyword(.public), .keyword(.package), .keyword(.fileprivate),
      .keyword(.private), .keyword(.nonisolated):
      return "\(modifier.trimmedDescription) "
    case .keyword(.open):
      return "public "
    default:
      return nil
    }
  }.joined()
}

private func isStaticModifier(_ modifier: DeclModifierSyntax) -> Bool {
  modifier.name.tokenKind == .keyword(.static)
    || modifier.name.tokenKind == .keyword(.class)
}

private func isNonisolatedModifier(_ modifier: DeclModifierSyntax) -> Bool {
  modifier.name.tokenKind == .keyword(.nonisolated)
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

private func diagnoseInvalidObservationState(
  _ declaration: some DeclSyntaxProtocol,
  in context: any MacroExpansionContext,
  if shouldDiagnose: Bool
) {
  guard shouldDiagnose else { return }
  context.diagnose(Diagnostic(
    node: Syntax(declaration),
    message: ObservationStateDiagnostic.invalidDeclaration))
}

private enum ObservationStateDiagnostic: String, DiagnosticMessage {
  case invalidDeclaration

  var message: String {
    "@ObservationState requires either a stored value with an explicit type and initial value, or an ObservationSource property with an explicit initial: argument"
  }

  var diagnosticID: MessageID {
    MessageID(domain: "VISOR", id: rawValue)
  }

  var severity: DiagnosticSeverity { .error }
}
