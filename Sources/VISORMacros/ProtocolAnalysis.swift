//
//  ProtocolAnalysis.swift
//  VISOR
//
//  Extracted from SharedExtensions.swift
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftParser

// MARK: - ProtocolPropertyInfo

struct ProtocolPropertyInfo {
  let name: String
  var type: String
  let hasSetter: Bool
  let stubbableDefault: String?
}

// MARK: - ParameterInfo

struct ParameterInfo {
  let externalLabel: String? // nil means no external label (e.g., `_ item: Item`)
  let internalName: String
  var type: String
}

// MARK: - ProtocolMethodInfo

struct ProtocolMethodInfo {
  let name: String
  var parameters: [ParameterInfo]
  let isAsync: Bool
  let isThrowing: Bool
  var returnType: String? // nil means Void
}

// MARK: - ProtocolTypeAliasInfo

struct ProtocolTypeAliasInfo {
  let name: String
  let type: TypeSyntax
}

// MARK: - ProtocolAnalysis

/// Single-pass analysis of a `ProtocolDeclSyntax` member list.
/// Replaces 5 separate computed-property traversals with one iteration.
struct ProtocolAnalysis {
  var properties: [ProtocolPropertyInfo] = []
  var methods: [ProtocolMethodInfo] = []
  var staticMembers: [String] = []
  var typeAliases: [ProtocolTypeAliasInfo] = []
  var hasAssociatedTypes = false
  var hasSubscripts = false
  
  init(_ protocolDecl: ProtocolDeclSyntax) {
    
    // We must find typealiases first
    for member in protocolDecl.memberBlock.members {
      guard let typeAliasDecl = member.decl.as(TypeAliasDeclSyntax.self) else { continue }
      let name = typeAliasDecl.name.text
      let typeSyntax = typeAliasDecl.initializer.value
      typeAliases.append(ProtocolTypeAliasInfo(
        name: name,
        type: typeSyntax))
    }
    
    // Keep track of all typealiases
    let typeAliasNames = Set(typeAliases.map(\.name))
    let protocolName = protocolDecl.name.text
    
    let taHandler = TypeAliasHandler(protocolName: protocolName, typeAliasNames: typeAliasNames)
    
    for member in protocolDecl.memberBlock.members {
      // Associated types
      if member.decl.is(AssociatedTypeDeclSyntax.self) {
        hasAssociatedTypes = true
        continue
      }
      
      // Subscripts
      if member.decl.is(SubscriptDeclSyntax.self) {
        hasSubscripts = true
        continue
      }
      
      // Variable declarations (properties)
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
        
        guard
          let binding = varDecl.bindings.first,
          let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
          let typeAnnotation = binding.typeAnnotation
        else {
          continue
        }
        
        let hasSetter: Bool
        if let accessorBlock = binding.accessorBlock,
           case .accessors(let accessors) = accessorBlock.accessors
        {
          hasSetter = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
        } else {
          hasSetter = false
        }
        
        let stubbableDefault: String? = {
          for attr in varDecl.attributes {
            guard
              let attrSyntax = attr.as(AttributeSyntax.self),
              attrSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text == AttributeName.stubbableDefault,
              let arguments = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first
            else {
              continue
            }
            return firstArg.expression.trimmedDescription
          }
          return nil
        }()
        
        properties.append(ProtocolPropertyInfo(
          name: identifier.identifier.text,
          type: taHandler.protocolQualifiedTypeName(for: typeAnnotation.type),
          hasSetter: hasSetter,
          stubbableDefault: stubbableDefault))
        continue
      }
      
      // Function declarations (methods)
      if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
        let isStatic = funcDecl.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
        if isStatic {
          staticMembers.append(funcDecl.name.text)
          continue
        }
        
        let params = funcDecl.signature.parameterClause.parameters.map { param in
          let externalLabel = param.firstName.tokenKind == .wildcard ? nil : param.firstName.text
          let internalName = param.secondName?.text ?? param.firstName.text
          let type = taHandler.protocolQualifiedTypeName(for: param.type)
          return ParameterInfo(externalLabel: externalLabel, internalName: internalName, type: type)
        }
        
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = funcDecl.signature.effectSpecifiers?.throwsClause != nil
        
        
        let returnType: String?
        if let returnClause = funcDecl.signature.returnClause {
          returnType = taHandler.protocolQualifiedTypeName(for: returnClause.type)
        } else {
          returnType = nil
        }
        
        methods.append(ProtocolMethodInfo(
          name: funcDecl.name.text,
          parameters: params,
          isAsync: isAsync,
          isThrowing: isThrowing,
          returnType: returnType))
      }
    }
  }
}

// MARK: - Typealias Handling

private struct TypeAliasHandler {
  let protocolName: String
  let typeAliasNames: Set<String>
  
  let protocolTypeSyntax: IdentifierTypeSyntax
  
  init(protocolName: String, typeAliasNames: Set<String>) {
    self.protocolName = protocolName
    self.typeAliasNames = typeAliasNames
    
    self.protocolTypeSyntax = IdentifierTypeSyntax(name: TokenSyntax(.identifier(protocolName), presence: .present))
  }
  
  // Handle protocol types in different places
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
    
    // If the type is already qualified by another member,
    // we should not attempt to qualify it by the protocol type as well
    case .memberType:
      return typeSyntax
      
    // Other type Syntaxes we can ignore
    case .missingType, .suppressedType, .classRestrictionType:
      return typeSyntax
    
    // To handle future TypeSyntaxes
    @unknown default:
      return typeSyntax
    }
  }
  
  func qualifiedType(
    for identifierTypeSyntax: IdentifierTypeSyntax
  ) -> TypeSyntax {
    var identifierTypeSyntax = identifierTypeSyntax
    
    // TODO: Handle 6.3 module selectors
    
    // Check any generic arguments
    if var genericArgumentClause = identifierTypeSyntax.genericArgumentClause {
      for i in genericArgumentClause.arguments.indices {
        genericArgumentClause.arguments[i] = qualifiedType(for: genericArgumentClause.arguments[i])
      }
      identifierTypeSyntax.genericArgumentClause = genericArgumentClause
    }
    
    // Check if the type is a typealias
    guard typeAliasNames.contains(identifierTypeSyntax.name.text) else {
      return TypeSyntax(identifierTypeSyntax)
    }
    
    // If it is, qualify the type name
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

/// Validates a protocol analysis for test double generation (Stubbable/Spyable).
/// Returns `false` if the protocol has associated types (emits error).
/// Emits warnings for subscripts and static members.
func validateProtocolForTestDouble(
  _ analysis: ProtocolAnalysis,
  protocolDecl: ProtocolDeclSyntax,
  macroName: String,
  context: some MacroExpansionContext)
  -> Bool
{
  if analysis.hasAssociatedTypes {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.associatedTypesNotSupported(macroName: macroName)))
    return false
  }

  if analysis.hasSubscripts {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.subscriptsSkipped(macroName: macroName)))
  }

  if !analysis.staticMembers.isEmpty {
    context.diagnose(Diagnostic(
      node: Syntax(protocolDecl),
      message: TestDoubleDiagnostic.staticMembersSkipped(macroName: macroName)))
  }

  return true
}

// accessLevel(of:) — use the generic version from CodeGenHelpers.swift.
// ProtocolDeclSyntax conforms to DeclGroupSyntax, so it matches directly.
