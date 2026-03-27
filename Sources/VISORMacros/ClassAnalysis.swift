//
//  ClassAnalysis.swift
//  VISOR
//
//  Extracted from SharedExtensions.swift
//

import SwiftSyntax

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
}

// MARK: - BoundPropertyInfo

struct BoundPropertyInfo {
  let propertyName: String       // State var name
  let dependencyName: String     // First keypath component (for dependency validation)
  let sourceExpression: String   // Full dot-path for observation (e.g. "profileService.isLoggedIn")
  let hasDefault: Bool           // Whether the State property has a default value
  let declarationOrder: Int      // Position among @Bound/@Polled properties (for init arg ordering)
  let throttleExpression: String?  // Optional Duration expression for throttling (e.g. ".seconds(0.5)")
}

// MARK: - PolledPropertyInfo

struct PolledPropertyInfo {
  let propertyName: String       // State var name
  let dependencyName: String     // First keypath component (for dependency validation)
  let sourceExpression: String   // Full dot-path for reading (e.g. "batteryMonitor.level")
  let intervalExpression: String // Duration expression (e.g. ".seconds(30)")
  let hasDefault: Bool           // Whether the State property has a default value
  let declarationOrder: Int      // Position among @Bound/@Polled properties (for init arg ordering)
}

// MARK: - ReactionMethodInfo

struct ReactionMethodInfo {
  let methodName: String        // "handleDeepLink"
  let parameterName: String     // "destination"
  let observeExpression: String // "self.deepLinkRouter.pendingDestination"
  let isAsync: Bool
  let throttleExpression: String? // Optional Duration expression for throttling
}

// MARK: - StateStoredPropertyInfo

struct StateStoredPropertyInfo {
  let name: String
  let type: String
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
  // v3: State/Action detection
  var hasStateClass = false
  var hasStateProperty = false
  var hasActionEnum = false
  var hasHandleMethod = false
  var handleHasWrongLabel = false

  // v3: State class metadata
  var stateStoredProperties: [StateStoredPropertyInfo] = []
  var stateClassIsFinal = false
  var stateClassHasObservable = false
  var stateClassHasInit = false

  // v2: @Bound inside State
  var stateBoundProperties: [BoundPropertyInfo] = []
  var malformedStateBoundAttributes: [String] = []
  var boundOnLetProperties: [String] = []

  // v2: @Polled inside State
  var statePolledProperties: [PolledPropertyInfo] = []
  var malformedStatePolledAttributes: [String] = []
  var polledOnLetProperties: [String] = []
  var polledMissingInterval: [String] = []

  // @Bound/@Polled on class-level properties (misplaced — should be inside State)
  var boundOutsideState: [String] = []
  var polledOutsideState: [String] = []

  init(_ classDecl: ClassDeclSyntax) {
    for member in classDecl.memberBlock.members {
      // Initializer check
      if member.decl.is(InitializerDeclSyntax.self) {
        hasInitializer = true
        continue
      }

      // Nested class declarations — detect State class
      if let nestedClassDecl = member.decl.as(ClassDeclSyntax.self) {
        if nestedClassDecl.name.text == "State" {
          hasStateClass = true
          stateClassIsFinal = nestedClassDecl.modifiers.contains { $0.name.text == "final" }
          stateClassHasObservable = nestedClassDecl.attributes.contains { attr in
            attr.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text == AttributeName.observable
          }
          scanState(nestedClassDecl)
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
        // Detect @Bound/@Polled on class-level properties (should be inside State)
        for attr in varDecl.attributes {
          guard let attrSyntax = attr.as(AttributeSyntax.self),
                let attrName = attrSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text
          else { continue }
          if attrName == AttributeName.bound {
            if let name = varDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
              boundOutsideState.append(name)
            }
          } else if attrName == AttributeName.polled {
            if let name = varDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
              polledOutsideState.append(name)
            }
          }
        }

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

          // Detect `var state` property
          if identifier.identifier.text == "state" {
            hasStateProperty = true
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
          .first(where: { $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text == AttributeName.reaction })
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

        var throttleExpr: String? = nil
        let secondIndex = arguments.index(after: arguments.startIndex)
        if secondIndex != arguments.endIndex {
          let secondArg = arguments[secondIndex]
          if secondArg.label?.text == "throttledBy" {
            throttleExpr = secondArg.expression.trimmedDescription
          }
        }

        reactionMethods.append(ReactionMethodInfo(
          methodName: funcDecl.name.text,
          parameterName: parameterName,
          observeExpression: "self." + components.joined(separator: "."),
          isAsync: isAsync,
          throttleExpression: throttleExpr))
      }
    }
  }

  /// Scans the nested `class State` for @Bound/@Polled attributes and stored properties.
  private mutating func scanState(_ classDecl: ClassDeclSyntax) {
    var declarationOrder = 0

    // Check for user-declared init
    for member in classDecl.memberBlock.members {
      if member.decl.is(InitializerDeclSyntax.self) {
        stateClassHasInit = true
        break
      }
    }

    for member in classDecl.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
        continue
      }

      // Single-pass attribute scan — find @Bound or @Polled in one iteration
      var boundAttr: AttributeSyntax?
      var polledAttr: AttributeSyntax?
      for attr in varDecl.attributes {
        guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
        guard let name = attrSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { continue }
        if name == AttributeName.bound { boundAttr = attrSyntax }
        else if name == AttributeName.polled { polledAttr = attrSyntax }
      }

      // Track ALL stored var properties
      if varDecl.bindingSpecifier.text == "var" || varDecl.bindingSpecifier.text == "let" {
        for binding in varDecl.bindings where binding.accessorBlock == nil {
          if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
            let type: String
            if let typeAnnotation = binding.typeAnnotation {
              type = typeAnnotation.type.trimmedDescription
            } else {
              // Type inferred from initializer — can't determine statically
              type = ""
            }
            if !type.isEmpty {
              stateStoredProperties.append(StateStoredPropertyInfo(
                name: identifier.identifier.text,
                type: type))
            }
          }
        }
      }

      if boundAttr == nil && polledAttr == nil {
        continue
      }

      guard
        let binding = varDecl.bindings.first,
        let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
      else {
        continue
      }

      let bindingKind = varDecl.bindingSpecifier.text
      let hasDefault = binding.initializer != nil

      // Handle @Bound
      if let boundAttr {
        if bindingKind == "let" {
          boundOnLetProperties.append(identifier.identifier.text)
          declarationOrder += 1
          continue
        }

        guard
          let arguments = boundAttr.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = arguments.first,
          let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self)
        else {
          malformedStateBoundAttributes.append(identifier.identifier.text)
          declarationOrder += 1
          continue
        }

        let components = keyPathExpr.components.compactMap { component -> String? in
          if case .property(let property) = component.component {
            return property.declName.baseName.text
          }
          return nil
        }

        var throttleExpr: String? = nil
        let secondIndex = arguments.index(after: arguments.startIndex)
        if secondIndex != arguments.endIndex {
          let secondArg = arguments[secondIndex]
          if secondArg.label?.text == "throttledBy" {
            throttleExpr = secondArg.expression.trimmedDescription
          }
        }

        if components.count >= 2 {
          stateBoundProperties.append(BoundPropertyInfo(
            propertyName: identifier.identifier.text,
            dependencyName: components[0],
            sourceExpression: components.joined(separator: "."),
            hasDefault: hasDefault,
            declarationOrder: declarationOrder,
            throttleExpression: throttleExpr))
        } else {
          malformedStateBoundAttributes.append(identifier.identifier.text)
        }
        declarationOrder += 1
        continue
      }

      // Handle @Polled
      if let polledAttr {
        if bindingKind == "let" {
          polledOnLetProperties.append(identifier.identifier.text)
          declarationOrder += 1
          continue
        }

        guard
          let arguments = polledAttr.arguments?.as(LabeledExprListSyntax.self),
          let firstArg = arguments.first,
          let keyPathExpr = firstArg.expression.as(KeyPathExprSyntax.self)
        else {
          malformedStatePolledAttributes.append(identifier.identifier.text)
          declarationOrder += 1
          continue
        }

        let components = keyPathExpr.components.compactMap { component -> String? in
          if case .property(let property) = component.component {
            return property.declName.baseName.text
          }
          return nil
        }

        guard components.count >= 2 else {
          malformedStatePolledAttributes.append(identifier.identifier.text)
          declarationOrder += 1
          continue
        }

        // Extract `every:` second argument
        let secondIndex = arguments.index(after: arguments.startIndex)
        guard secondIndex != arguments.endIndex else {
          polledMissingInterval.append(identifier.identifier.text)
          declarationOrder += 1
          continue
        }
        let secondArg = arguments[secondIndex]
        guard secondArg.label?.text == "every" else {
          polledMissingInterval.append(identifier.identifier.text)
          declarationOrder += 1
          continue
        }
        let intervalExpr = secondArg.expression.trimmedDescription

        statePolledProperties.append(PolledPropertyInfo(
          propertyName: identifier.identifier.text,
          dependencyName: components[0],
          sourceExpression: components.joined(separator: "."),
          intervalExpression: intervalExpr,
          hasDefault: hasDefault,
          declarationOrder: declarationOrder))
        declarationOrder += 1
      }
    }
  }
}
