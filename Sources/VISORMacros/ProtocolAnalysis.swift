//
//  ProtocolAnalysis.swift
//  VISOR
//
//  Extracted from SharedExtensions.swift
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

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
    for member in protocolDecl.memberBlock.members {
      // Associated types
      if member.decl.is(AssociatedTypeDeclSyntax.self) {
        hasAssociatedTypes = true
        continue
      }
      
      // Typealiases
      if let typeAliasDecl = member.decl.as(TypeAliasDeclSyntax.self) {
        let name = typeAliasDecl.name.text
        let typeSyntax = typeAliasDecl.initializer.value
        typeAliases.append(ProtocolTypeAliasInfo(
          name: name,
          type: typeSyntax))
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
          type: typeAnnotation.type.trimmedDescription,
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
          let type = param.type.trimmedDescription
          return ParameterInfo(externalLabel: externalLabel, internalName: internalName, type: type)
        }

        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = funcDecl.signature.effectSpecifiers?.throwsClause != nil
        let returnType = funcDecl.signature.returnClause?.type.trimmedDescription

        methods.append(ProtocolMethodInfo(
          name: funcDecl.name.text,
          parameters: params,
          isAsync: isAsync,
          isThrowing: isThrowing,
          returnType: returnType))
      }
    }
    
    // Prefix the protocol type for every type that matches the typealias
    let typeAliasNames = Set(typeAliases.map(\.name))
    let protocolName = protocolDecl.name.text
    
    func prefixProtocolName(_ type: inout String) {
      type = "\(protocolName).\(type)"
    }
    
    // Methods
    for i in methods.indices {
      
      // Method parameters
      for j in methods[i].parameters.indices {
        if typeAliasNames.contains(methods[i].parameters[j].type) {
          prefixProtocolName(&methods[i].parameters[j].type)
        }
      }
      
      // Method return types
      if let name = methods[i].returnType, typeAliasNames.contains(name) {
        prefixProtocolName(&methods[i].returnType!)
      }
      
    }
    
    // Properties
    for i in properties.indices {
      if typeAliasNames.contains(properties[i].type) {
        prefixProtocolName(&properties[i].type)
      }
    }
    
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
