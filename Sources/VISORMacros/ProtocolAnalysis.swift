import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftParser

struct ProtocolPropertyInfo {
  let name: String
  let type: String
  let defaultValueExpression: String?
  let observationState: ProtocolObservationStateInfo?
}

struct ProtocolObservationStateInfo {
  let initialValueExpression: String?
  let sequenceNaming: ObservationStateSequenceNaming

  func sequenceName(for propertyName: String) -> String {
    sequenceNaming.memberName(for: propertyName)
  }
}

struct ParameterInfo {
  let externalLabel: String?
  let internalName: String
  let type: String
  let isInout: Bool
}

enum ThrowsEffect {
  case none
  case `throws`(errorType: String?)
  case `rethrows`

  var keyword: String? {
    switch self {
    case .none:
      return nil
    case .throws(let errorType):
      return errorType.map { "throws(\($0))" } ?? "throws"
    case .rethrows:
      return "rethrows"
    }
  }

  var resultFailureType: String? {
    switch self {
    case .none, .rethrows:
      return nil
    case .throws(let errorType):
      return errorType ?? "any Error"
    }
  }

  var explicitErrorType: String? {
    switch self {
    case .none, .rethrows:
      return nil
    case .throws(let errorType):
      return errorType
    }
  }
}

struct ProtocolMethodInfo {
  let name: String
  let genericParameterClause: String
  let genericWhereClause: String?
  let genericParameterNames: [String]
  let explicitlySendableGenericParameterNames: Set<String>
  let parameters: [ParameterInfo]
  let isAsync: Bool
  let isConcurrent: Bool
  let throwsEffect: ThrowsEffect
  let returnType: String?
  let defaultReturnExpression: String?

  var isThrowing: Bool {
    if case .none = throwsEffect { return false }
    return true
  }

  var isRethrowing: Bool {
    if case .rethrows = throwsEffect { return true }
    return false
  }
}

struct ProtocolAnalysis {
  var properties: [ProtocolPropertyInfo] = []
  var methods: [ProtocolMethodInfo] = []
  var staticMembers: [String] = []
  var typeAliasNames: [String] = []
  var hasAssociatedTypes = false
  var hasSubscripts = false
  var hasInitialiserRequirements = false
  var unsupportedRequirementKinds: [String] = []
  
  init(_ protocolDecl: ProtocolDeclSyntax) {
    
    // Qualifying requirement types requires the complete alias set, regardless
    // of declaration order within the protocol.
    for member in protocolDecl.memberBlock.members {
      guard let typeAliasDecl = member.decl.as(TypeAliasDeclSyntax.self) else { continue }
      typeAliasNames.append(typeAliasDecl.name.text)
    }
    
    let typeAliasNameSet = Set(typeAliasNames)
    let protocolName = protocolDecl.name.text
    
    let typeAliasHandler = TypeAliasHandler(
      protocolName: protocolName,
      typeAliasNames: typeAliasNameSet)
    
    for member in protocolDecl.memberBlock.members {
      if member.decl.is(AssociatedTypeDeclSyntax.self) {
        hasAssociatedTypes = true
        continue
      }
      
      if member.decl.is(SubscriptDeclSyntax.self) {
        hasSubscripts = true
        continue
      }

      if member.decl.is(InitializerDeclSyntax.self) {
        hasInitialiserRequirements = true
        continue
      }

      if member.decl.is(TypeAliasDeclSyntax.self) {
        continue
      }
      
      if let varDecl = member.decl.as(VariableDeclSyntax.self) {
        let isStatic = varDecl.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
        if isStatic {
          if let binding = varDecl.bindings.first,
             let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
          {
            staticMembers.append(identifier.identifier.text)
          }
          continue
        }
        
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var),
          varDecl.bindings.count == 1,
          let binding = varDecl.bindings.first,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          let typeAnnotation = binding.typeAnnotation
        else {
          recordUnsupportedRequirement("property declaration")
          continue
        }

        if let accessorBlock = binding.accessorBlock,
           case .accessors(let accessors) = accessorBlock.accessors,
           accessors.contains(where: { $0.effectSpecifiers != nil })
        {
          recordUnsupportedRequirement("effectful property accessor")
          continue
        }
        
        let observationStateAttribute = varDecl.attributes.visorAttribute(
          named: AttributeName.observationState)
        let observationState: ProtocolObservationStateInfo? =
          observationStateAttribute.flatMap { attribute in
            guard case .success(let arguments) = ObservationStateArguments.parse(from: attribute) else {
              return nil
            }
            return ProtocolObservationStateInfo(
              initialValueExpression: arguments.initialValueExpression,
              sequenceNaming: arguments.sequenceNaming)
          }
        let defaultValueExpression = observationState?.initialValueExpression
          ?? extractAttributeExpression(
            named: AttributeName.defaultValue,
            in: varDecl.attributes)
        
        properties.append(ProtocolPropertyInfo(
          name: identifier.identifier.text,
          type: typeAliasHandler.protocolQualifiedTypeName(for: typeAnnotation.type),
          defaultValueExpression: defaultValueExpression,
          observationState: observationState))
        continue
      }
      
      if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
        let isStatic = funcDecl.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
        if isStatic {
          staticMembers.append(funcDecl.name.text)
          continue
        }

        if funcDecl.signature.parameterClause.parameters.contains(where: { $0.ellipsis != nil }) {
          recordUnsupportedRequirement("variadic method")
          continue
        }

        let genericParameterClause = funcDecl.genericParameterClause?.trimmedDescription ?? ""
        let genericWhereClause = funcDecl.genericWhereClause?.trimmedDescription
        let genericParameterNames = funcDecl.genericParameterClause?.parameters.map(\.name.text) ?? []
        let explicitlySendableGenericParameterNames = explicitlySendableGenericParameterNames(
          in: funcDecl)
        
        let params = funcDecl.signature.parameterClause.parameters.map { param in
          let externalLabel = param.firstName.tokenKind == .wildcard ? nil : param.firstName.text
          let internalName = param.secondName?.text ?? param.firstName.text
          let type = typeAliasHandler.protocolQualifiedTypeName(for: param.type)
          let isInout = param.type.hasInoutSpecifier
          return ParameterInfo(externalLabel: externalLabel, internalName: internalName, type: type, isInout: isInout)
        }
        
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isConcurrent = funcDecl.attributes.contains { element in
          guard let attribute = element.as(AttributeSyntax.self) else { return false }
          return attribute.attributeName.trimmedDescription == "concurrent"
        }
        let throwsEffect: ThrowsEffect
        if let throwsClause = funcDecl.signature.effectSpecifiers?.throwsClause {
          if throwsClause.throwsSpecifier.tokenKind == .keyword(.rethrows) {
            throwsEffect = .rethrows
          } else {
            let errorType = throwsClause.type.map {
              typeAliasHandler.protocolQualifiedTypeName(for: $0)
            }
            throwsEffect = .throws(errorType: errorType)
          }
        } else {
          throwsEffect = .none
        }

        let returnType: String?
        if let returnClause = funcDecl.signature.returnClause {
          returnType = typeAliasHandler.protocolQualifiedTypeName(for: returnClause.type)
        } else {
          returnType = nil
        }
        
        methods.append(ProtocolMethodInfo(
          name: funcDecl.name.text,
          genericParameterClause: genericParameterClause,
          genericWhereClause: genericWhereClause,
          genericParameterNames: genericParameterNames,
          explicitlySendableGenericParameterNames: explicitlySendableGenericParameterNames,
          parameters: params,
          isAsync: isAsync,
          isConcurrent: isConcurrent,
          throwsEffect: throwsEffect,
          returnType: returnType,
          defaultReturnExpression: extractAttributeExpression(
            named: AttributeName.defaultReturn,
            in: funcDecl.attributes)))
        continue
      }


      // Nested declarations do not add conformance requirements.
      if member.decl.is(StructDeclSyntax.self)
        || member.decl.is(ClassDeclSyntax.self)
        || member.decl.is(EnumDeclSyntax.self)
        || member.decl.is(ActorDeclSyntax.self)
      {
        continue
      }

      recordUnsupportedRequirement("unrecognised protocol member")
    }
  }

  private mutating func recordUnsupportedRequirement(_ kind: String) {
    guard !unsupportedRequirementKinds.contains(kind) else { return }
    unsupportedRequirementKinds.append(kind)
  }
}

private func explicitlySendableGenericParameterNames(
  in function: FunctionDeclSyntax)
  -> Set<String>
{
  let genericParameterNames = Set(
    function.genericParameterClause?.parameters.map(\.name.text) ?? [])
  let inlineSendableNames: [String] = function.genericParameterClause.map { clause in
    clause.parameters.compactMap { parameter -> String? in
      guard let inheritedType = parameter.inheritedType,
            typeIncludesSendable(inheritedType)
      else {
        return nil
      }
      return parameter.name.text
    }
  } ?? []
  var sendableNames = Set(inlineSendableNames)

  for requirement in function.genericWhereClause?.requirements ?? [] {
    guard case .conformanceRequirement(let conformance) = requirement.requirement,
          let identifier = conformance.leftType.as(IdentifierTypeSyntax.self),
          genericParameterNames.contains(identifier.name.text),
          typeIncludesSendable(conformance.rightType)
    else {
      continue
    }
    sendableNames.insert(identifier.name.text)
  }

  return sendableNames
}

private func typeIncludesSendable(_ type: TypeSyntax) -> Bool {
  if let identifier = type.as(IdentifierTypeSyntax.self) {
    return identifier.name.text == "Sendable"
  }
  if let member = type.as(MemberTypeSyntax.self) {
    return member.name.text == "Sendable"
  }
  if let composition = type.as(CompositionTypeSyntax.self) {
    return composition.elements.contains { typeIncludesSendable($0.type) }
  }
  return false
}

private func extractAttributeExpression(named attributeName: String, in attributes: AttributeListSyntax) -> String? {
  guard
    let attribute = attributes.visorAttribute(named: attributeName),
    let expression = extractAttributeExpression(from: attribute)
  else {
    return nil
  }
  return expression
}

private func extractAttributeExpression(from attribute: AttributeSyntax) -> String? {
  guard
    let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
    let firstArgument = arguments.first
  else {
    return nil
  }
  return firstArgument.expression.trimmedDescription
}

// MARK: - Typealias Handling

private struct TypeAliasHandler {
  let typeAliasNames: Set<String>
  
  let protocolTypeSyntax: IdentifierTypeSyntax
  
  init(protocolName: String, typeAliasNames: Set<String>) {
    self.typeAliasNames = typeAliasNames
    
    self.protocolTypeSyntax = IdentifierTypeSyntax(name: TokenSyntax(.identifier(protocolName), presence: .present))
  }
  
  func protocolQualifiedTypeName(for typeSyntax: TypeSyntax) -> String {
    return qualifiedType(for: typeSyntax).trimmedDescription
  }
  
  func qualifiedType(
    for typeSyntax: TypeSyntax
  ) -> TypeSyntax {
    switch typeSyntax.as(TypeSyntaxEnum.self) {
      
    case .identifierType(let syntax):
      return qualifiedType(for: syntax)
      
    case .arrayType(var syntax):
      let newElement = qualifiedType(for: syntax.element)
      syntax.element = newElement
      return TypeSyntax(syntax)
      
    case .attributedType(var syntax):
      let newBaseType = qualifiedType(for: syntax.baseType)
      syntax.baseType = newBaseType
      return TypeSyntax(syntax)
      
    case .compositionType(var syntax):
      let newElements = qualifiedType(for: syntax.elements)
      syntax.elements = newElements
      return TypeSyntax(syntax)
      
    case .dictionaryType(var syntax):
      let newKey    = qualifiedType(for: syntax.key)
      let newValue  = qualifiedType(for: syntax.value)
      syntax.key    = newKey
      syntax.value  = newValue
      return TypeSyntax(syntax)
    
    case .functionType(var syntax):
      let newParameters = qualifiedType(for: syntax.parameters)
      let newReturnType = qualifiedType(for: syntax.returnClause.type)
      syntax.parameters = newParameters
      syntax.returnClause.type = newReturnType
      return TypeSyntax(syntax)
      
    case .implicitlyUnwrappedOptionalType(var syntax):
      let newWrappedType = qualifiedType(for: syntax.wrappedType)
      syntax.wrappedType = newWrappedType
      return TypeSyntax(syntax)
    
    case .inlineArrayType(var syntax):
      let newCount = qualifiedType(for: syntax.count)
      let newElement = qualifiedType(for: syntax.element)
      syntax.count = newCount
      syntax.element = newElement
      return TypeSyntax(syntax)
      
    case .metatypeType(var syntax):
      let newBaseType = qualifiedType(for: syntax.baseType)
      syntax.baseType = newBaseType
      return TypeSyntax(syntax)
      
    case .namedOpaqueReturnType(var syntax):
      let newType = qualifiedType(for: syntax.type)
      syntax.type = newType
      return TypeSyntax(syntax)
      
    case .optionalType(var syntax):
      let newWrappedType = qualifiedType(for: syntax.wrappedType)
      syntax.wrappedType = newWrappedType
      return TypeSyntax(syntax)
      
    case .packElementType(var syntax):
      let newPack = qualifiedType(for: syntax.pack)
      syntax.pack = newPack
      return TypeSyntax(syntax)
      
    case .packExpansionType(var syntax):
      let newRepetitionPattern = qualifiedType(for: syntax.repetitionPattern)
      syntax.repetitionPattern = newRepetitionPattern
      return TypeSyntax(syntax)
      
    case .someOrAnyType(var syntax):
      let newConstraint = qualifiedType(for: syntax.constraint)
      syntax.constraint = newConstraint
      return TypeSyntax(syntax)
      
    case .tupleType(var syntax):
      let newElements = qualifiedType(for: syntax.elements)
      syntax.elements = newElements
      return TypeSyntax(syntax)
    
    // Preserve an existing qualification rather than prepending the protocol.
    case .memberType:
      return typeSyntax
      
    case .missingType, .suppressedType, .classRestrictionType:
      return typeSyntax
    
    @unknown default:
      return typeSyntax
    }
  }
  
  func qualifiedType(
    for identifierTypeSyntax: IdentifierTypeSyntax
  ) -> TypeSyntax {
    var identifierTypeSyntax = identifierTypeSyntax
    
    // TODO: Handle 6.3 module selectors
    
    if var genericArgumentClause = identifierTypeSyntax.genericArgumentClause {
      for i in genericArgumentClause.arguments.indices {
        genericArgumentClause.arguments[i] = qualifiedType(for: genericArgumentClause.arguments[i])
      }
      identifierTypeSyntax.genericArgumentClause = genericArgumentClause
    }
    
    guard typeAliasNames.contains(identifierTypeSyntax.name.text) else {
      return TypeSyntax(identifierTypeSyntax)
    }
    
    let syntax = MemberTypeSyntax(
      baseType: protocolTypeSyntax,
      name: identifierTypeSyntax.name)
    return TypeSyntax(syntax)
  }
  
  func qualifiedType(
    for tupleTypeElementListSyntax: TupleTypeElementListSyntax
  ) -> TupleTypeElementListSyntax {
    var tupleTypeElementListSyntax = tupleTypeElementListSyntax
    for i in tupleTypeElementListSyntax.indices {
      tupleTypeElementListSyntax[i].type = qualifiedType(for: tupleTypeElementListSyntax[i].type)
    }
    return tupleTypeElementListSyntax
  }
  
  func qualifiedType(
    for genericArgumentSyntax: GenericArgumentSyntax
  ) -> GenericArgumentSyntax {
    var genericArgumentSyntax = genericArgumentSyntax
    switch genericArgumentSyntax.argument {
    case .expr:
      return genericArgumentSyntax
    case .type(let syntax):
      genericArgumentSyntax.argument = .type(qualifiedType(for: syntax))
      return genericArgumentSyntax
    }
  }
  
  func qualifiedType(
    for compositionTypeElementListSyntax: CompositionTypeElementListSyntax
  ) -> CompositionTypeElementListSyntax {
    var compositionTypeElementListSyntax = compositionTypeElementListSyntax
    for i in compositionTypeElementListSyntax.indices {
      compositionTypeElementListSyntax[i].type = qualifiedType(for: compositionTypeElementListSyntax[i].type)
    }
    return compositionTypeElementListSyntax
  }
  
}

// MARK: - Shared Protocol Validation for Test Double Macros

/// Returns `false` unless the generator can model every conformance requirement.
func validateProtocolForTestDouble(
  _ analysis: ProtocolAnalysis,
  protocolDecl: ProtocolDeclSyntax,
  traits: TestDoubleTraits,
  macroName: String,
  context: some MacroExpansionContext)
  -> Bool
{
  var isValid = true

  if analysis.hasAssociatedTypes {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.associatedTypesNotSupported(macroName: macroName)))
    isValid = false
  }

  if analysis.hasSubscripts {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.subscriptsNotSupported(macroName: macroName)))
    isValid = false
  }

  if !analysis.staticMembers.isEmpty {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.staticRequirementsNotSupported(macroName: macroName)))
    isValid = false
  }

  if analysis.hasInitialiserRequirements {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.initialiserRequirementsNotSupported(macroName: macroName)))
    isValid = false
  }

  for kind in analysis.unsupportedRequirementKinds {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.unsupportedRequirement(kind: kind, macroName: macroName)))
    isValid = false
  }

  for inheritedType in protocolDecl.inheritanceClause?.inheritedTypes ?? [] {
    let inheritedName = inheritedType.type.trimmedDescription
    switch inheritedName {
    case "AnyObject", "Swift.AnyObject":
      continue
    case "Sendable", "Swift.Sendable":
      guard traits.isSendable else {
        context.diagnose(Diagnostic(
          node: Syntax(protocolDecl),
          message: TestDoubleDiagnostic.sendableTraitRequired(macroName: macroName)))
        isValid = false
        continue
      }
    default:
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.inheritedProtocolNotSupported(
          protocolName: inheritedName,
          macroName: macroName)))
      isValid = false
    }
  }

  return isValid
}

// MARK: - Inout Detection

extension TypeSyntax {
  var hasInoutSpecifier: Bool {
    guard let attributedType = self.as(AttributedTypeSyntax.self) else { return false }
    for specifier in attributedType.specifiers {
      if specifier.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind == .keyword(.inout) {
        return true
      }
    }
    return false
  }
}
