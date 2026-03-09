//
//  ClassAnalysis.swift
//  VISOR
//
//  Extracted from SharedExtensions.swift
//

import SwiftSyntax

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
  var malformedReactionKeyPaths: [String] = []
  var hasStartObserving = false
  var startObservingBodyText: String?
  var hasInitializer = false
  // v2: Action/handle detection
  var hasActionEnum = false
  var hasHandleMethod = false
  var handleHasWrongLabel = false

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
            .first(where: { $0.attributeName.trimmedDescription == AttributeName.bound })
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

        // handle detection — require exactly one parameter typed `Action`
        if funcDecl.name.text == "handle" {
          let params = funcDecl.signature.parameterClause.parameters
          if params.count == 1,
             let param = params.first,
             param.type.trimmedDescription == "Action"
          {
            if param.firstName.text == "_" {
              hasHandleMethod = true
            } else {
              handleHasWrongLabel = true
            }
          }
        }

        // @Reaction methods
        guard let reactionAttr = funcDecl.attributes.lazy
          .compactMap({ $0.as(AttributeSyntax.self) })
          .first(where: { $0.attributeName.trimmedDescription == AttributeName.reaction })
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
          malformedReactionKeyPaths.append(funcDecl.name.text)
          continue
        }

        let components = keyPathExpr.components.compactMap { component -> String? in
          if case .property(let property) = component.component {
            return property.declName.baseName.text
          }
          return nil
        }
        guard !components.isEmpty else {
          malformedReactionKeyPaths.append(funcDecl.name.text)
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
        .first(where: { $0.attributeName.trimmedDescription == AttributeName.bound })
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

      // Try to parse the key-path argument (must be single-level: \ClassName.dep)
      if let arguments = boundAttr.arguments?.as(LabeledExprListSyntax.self),
         let firstArg = arguments.first,
         let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self),
         keyPathExpr.components.count == 1,
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
