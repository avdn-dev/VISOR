//
//  SharedExtensions.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ProtocolPropertyInfo

struct ProtocolPropertyInfo {
  let name: String
  let type: String
  let hasSetter: Bool
  let stubbableDefault: String?
}

// MARK: - ParameterInfo

struct ParameterInfo {
  let externalLabel: String? // nil means no external label (e.g., `_ item: Item`)
  let internalName: String
  let type: String
}

// MARK: - ProtocolMethodInfo

struct ProtocolMethodInfo {
  let name: String
  let parameters: [ParameterInfo]
  let isAsync: Bool
  let isThrowing: Bool
  let returnType: String? // nil means Void
}

// MARK: - ProtocolAnalysis

/// Single-pass analysis of a `ProtocolDeclSyntax` member list.
/// Replaces 5 separate computed-property traversals with one iteration.
struct ProtocolAnalysis {
  var properties: [ProtocolPropertyInfo] = []
  var methods: [ProtocolMethodInfo] = []
  var staticMembers: [String] = []
  var hasAssociatedTypes = false
  var hasSubscripts = false

  init(_ protocolDecl: ProtocolDeclSyntax) {
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
              attrSyntax.attributeName.trimmedDescription == "StubbableDefault",
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
  }
}

// MARK: - Property Declaration Helper

func generatePropertyDeclarations(_ properties: [ProtocolPropertyInfo], access: String = "") -> [String] {
  let prefix = access.isEmpty ? "" : "\(access) "
  return properties.map { prop in
    if let customDefault = prop.stubbableDefault {
      return "  \(prefix)var \(prop.name): \(prop.type) = \(customDefault)"
    } else {
      let defaultVal = defaultValue(for: prop.type) ?? "nil"
      let typeStr = defaultVal == "nil" && !prop.type.hasSuffix("?") && !prop.type.hasPrefix("Optional<")
        ? "\(prop.type)!"
        : prop.type
      return "  \(prefix)var \(prop.name): \(typeStr) = \(defaultVal)"
    }
  }
}

// MARK: - Default Value Helper

func defaultValue(for type: String) -> String? {
  let trimmed = type.trimmingCharacters(in: .whitespaces)

  // Optional
  if trimmed.hasSuffix("?") { return "nil" }
  if trimmed.hasPrefix("Optional<") { return "nil" }

  // Bool
  if trimmed == "Bool" { return "false" }

  // Numeric
  let intTypes: Set<String> = ["Int", "Int8", "Int16", "Int32", "Int64",
                                "UInt", "UInt8", "UInt16", "UInt32", "UInt64"]
  if intTypes.contains(trimmed) { return "0" }
  if trimmed == "Float" { return "0.0" }
  if trimmed == "Double" { return "0.0" }
  if trimmed == "CGFloat" { return "0.0" }
  if trimmed == "Decimal" { return "0" }

  // String
  if trimmed == "String" { return "\"\"" }

  // Data
  if trimmed == "Data" { return "Data()" }

  // Array
  if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && !trimmed.contains(":") { return "[]" }
  if trimmed.hasPrefix("Array<") { return "[]" }

  // Dictionary
  if trimmed.hasPrefix("[") && trimmed.contains(":") && trimmed.hasSuffix("]") { return "[:]" }
  if trimmed.hasPrefix("Dictionary<") { return "[:]" }

  // Set
  if trimmed.hasPrefix("Set<") { return "[]" }

  // Void
  if trimmed == "Void" || trimmed == "()" { return "()" }

  // AsyncStream
  if trimmed.hasPrefix("AsyncStream<") { return "AsyncStream { $0.finish() }" }

  return nil
}

// MARK: - Method Signature Helper

func buildMethodSignature(_ method: ProtocolMethodInfo, access: String = "") -> String {
  let params = method.parameters.map { param in
    if let label = param.externalLabel {
      if label == param.internalName {
        return "\(label): \(param.type)"
      }
      return "\(label) \(param.internalName): \(param.type)"
    }
    return "_ \(param.internalName): \(param.type)"
  }.joined(separator: ", ")

  let prefix = access.isEmpty ? "" : "\(access) "
  var sig = "\(prefix)func \(method.name)(\(params))"
  if method.isAsync { sig += " async" }
  if method.isThrowing { sig += " throws" }
  if let ret = method.returnType { sig += " -> \(ret)" }
  return sig
}

// MARK: - ViewModelPairInfo

struct ViewModelPairInfo {
  let viewModelType: String
  let factoryType: String
  let propertyName: String // e.g., "cameraViewModel" derived from "CameraViewModel"
}

// MARK: - StructDeclSyntax Extensions

extension StructDeclSyntax {
  var hasContentProperty: Bool {
    memberBlock.members.contains { member in
      guard
        let varDecl = member.decl.as(VariableDeclSyntax.self),
        let binding = varDecl.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
      else {
        return false
      }
      return identifier.identifier.text == "content"
    }
  }

}

// MARK: - StoredProperty

struct StoredProperty {
  let name: String
  let type: String
  /// Whether this property's type is `Router<...>` (not a protocol, so no Stub prefix).
  var isRouterType: Bool { type.hasPrefix("Router<") }
}

// MARK: - BoundPropertyInfo

struct BoundPropertyInfo {
  let propertyName: String
  let dependencyName: String
}

// MARK: - ReactionMethodInfo

struct ReactionMethodInfo {
  let methodName: String        // "handleDeepLink"
  let parameterName: String     // "destination"
  let observeExpression: String // "self.deepLinkRouter.pendingDestination"
  let isAsync: Bool
}

// MARK: - ClassAnalysis

/// Single-pass analysis of a `ClassDeclSyntax` member list.
struct ClassAnalysis {
  var storedLetProperties: [StoredProperty] = []
  var reactionMethods: [ReactionMethodInfo] = []
  var invalidReactionMethods: [String] = []
  var hasStartObserving = false
  var startObservingBodyText: String?
  var hasInitializer = false
  // v2: Action/handle detection
  var hasActionEnum = false
  var hasHandleMethod = false
  var handleIsAsync = false

  // v2: @Bound inside State struct
  var stateBoundProperties: [BoundPropertyInfo] = []
  var malformedStateBoundAttributes: [String] = []
  var boundOnLetProperties: [String] = []

  // v2: @Bound on class-level var (migration warning)
  var classLevelBoundProperties: [String] = []

  init(_ classDecl: ClassDeclSyntax) {
    for member in classDecl.memberBlock.members {
      // Initializer check
      if member.decl.is(InitializerDeclSyntax.self) {
        hasInitializer = true
        continue
      }

      // Nested struct/enum declarations
      if let structDecl = member.decl.as(StructDeclSyntax.self) {
        if structDecl.name.text == "State" {
          scanStateStruct(structDecl)
        }
        continue
      }

      if let enumDecl = member.decl.as(EnumDeclSyntax.self) {
        if enumDecl.name.text == "Action" {
          hasActionEnum = true
        }
        continue
      }

      // Variable declarations
      if let varDecl = member.decl.as(VariableDeclSyntax.self) {
        let bindingKind = varDecl.bindingSpecifier.text

        if bindingKind == "let" {
          // Stored let properties (no default, no accessor)
          for binding in varDecl.bindings {
            guard
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              binding.initializer == nil,
              binding.accessorBlock == nil
            else {
              continue
            }
            storedLetProperties.append(StoredProperty(
              name: identifier.identifier.text,
              type: typeAnnotation.type.trimmedDescription))
          }
        } else if bindingKind == "var" {
          guard
            let binding = varDecl.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
          else {
            continue
          }

          // Detect v1 @Bound on class-level var (migration warning)
          if let _ = varDecl.attributes.lazy
            .compactMap({ $0.as(AttributeSyntax.self) })
            .first(where: { $0.attributeName.trimmedDescription == "Bound" })
          {
            classLevelBoundProperties.append(identifier.identifier.text)
          }
        }
        continue
      }

      // Function declarations
      if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
        // startObserving check
        if funcDecl.name.text == "startObserving" {
          hasStartObserving = true
          startObservingBodyText = funcDecl.body?.statements.trimmedDescription
        }

        // handle detection
        if funcDecl.name.text == "handle" {
          let params = funcDecl.signature.parameterClause.parameters
          if params.count == 1 {
            hasHandleMethod = true
            handleIsAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
          }
        }

        // @Reaction methods
        guard let reactionAttr = funcDecl.attributes.lazy
          .compactMap({ $0.as(AttributeSyntax.self) })
          .first(where: { $0.attributeName.trimmedDescription == "Reaction" })
        else {
          continue
        }

        let paramCount = funcDecl.signature.parameterClause.parameters.count
        guard paramCount == 1, let param = funcDecl.signature.parameterClause.parameters.first else {
          if paramCount != 1 {
            invalidReactionMethods.append(funcDecl.name.text)
          }
          continue
        }

        guard
          let arguments = reactionAttr.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = arguments.first,
          let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self)
        else {
          continue
        }

        let components = keyPathExpr.components.compactMap { component -> String? in
          if case .property(let property) = component.component {
            return property.declName.baseName.text
          }
          return nil
        }
        guard !components.isEmpty else {
          continue
        }

        let parameterName = param.secondName?.text ?? param.firstName.text
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil

        reactionMethods.append(ReactionMethodInfo(
          methodName: funcDecl.name.text,
          parameterName: parameterName,
          observeExpression: "self." + components.joined(separator: "."),
          isAsync: isAsync))
      }
    }
  }

  /// Scans the nested `struct State` for @Bound attributes.
  private mutating func scanStateStruct(_ structDecl: StructDeclSyntax) {
    for member in structDecl.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
        continue
      }

      guard let boundAttr = varDecl.attributes.lazy
        .compactMap({ $0.as(AttributeSyntax.self) })
        .first(where: { $0.attributeName.trimmedDescription == "Bound" })
      else {
        continue
      }

      guard
        let binding = varDecl.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
      else {
        continue
      }

      let bindingKind = varDecl.bindingSpecifier.text
      if bindingKind == "let" {
        boundOnLetProperties.append(identifier.identifier.text)
        continue
      }

      // Try to parse the key-path argument
      if let arguments = boundAttr.arguments?.as(LabeledExprListSyntax.self),
         let firstArg = arguments.first,
         let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self),
         let firstComponent = keyPathExpr.components.first,
         case .property(let property) = firstComponent.component
      {
        stateBoundProperties.append(BoundPropertyInfo(
          propertyName: identifier.identifier.text,
          dependencyName: property.declName.baseName.text))
      } else {
        malformedStateBoundAttributes.append(identifier.identifier.text)
      }
    }
  }
}

// MARK: - String Extension

extension String {
  var capitalizedFirst: String {
    guard let first else { return self }
    return first.uppercased() + dropFirst()
  }

  var lowercasedFirst: String {
    guard let first else { return self }
    return first.lowercased() + dropFirst()
  }
}

// MARK: - Helper Functions

func makeProtocolExtension(
  for type: some TypeSyntaxProtocol,
  conformingTo protocolName: String)
  -> ExtensionDeclSyntax
{
  let extensionDecl: DeclSyntax = """
    extension \(type.trimmed): @MainActor \(raw: protocolName) {}
    """
  return extensionDecl.cast(ExtensionDeclSyntax.self)
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

/// Returns the access-level keyword for a protocol (e.g. "public") or empty string.
/// `internal` is omitted (returns "") because it's Swift's default access level —
/// emitting it explicitly would just add noise to the generated code.
func accessLevel(of protocolDecl: ProtocolDeclSyntax) -> String {
  for modifier in protocolDecl.modifiers {
    switch modifier.name.text {
    case "open", "public", "package", "fileprivate", "private":
      return modifier.name.text
    default:
      continue
    }
  }
  return ""
}
