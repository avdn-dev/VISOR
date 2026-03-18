//
//  ViewModelMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ViewModelMacro

public struct ViewModelMacro: MemberMacro, ExtensionMacro {

  // MARK: - MemberMacro (generates init, Factory typealias, and preview)

  public static func expansion(
    of _: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      context.diagnose(Diagnostic(node: Syntax(declaration), message: VISORDiagnostic.notAClass))
      return []
    }

    // Error if @Observable is missing — observation code will silently fail without it
    let hasObservable = classDecl.attributes.contains { attr in
      attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription == AttributeName.observable
    }
    if !hasObservable {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.missingObservable))
      return []
    }

    let className = classDecl.name.trimmedDescription
    let access = accessLevel(of: classDecl)
    let prefix = access.isEmpty ? "" : "\(access) "
    let analysis = ClassAnalysis(classDecl)
    let properties = analysis.storedLetProperties
    var members: [DeclSyntax] = []

    // 1. State/Action diagnostics (early — before init generation)
    if !analysis.hasStateStruct {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.missingState))
      return []
    }

    if analysis.hasActionEnum && !analysis.hasHandleMethod {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.actionWithoutHandle))
    }

    if analysis.handleHasWrongLabel {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.handleWrongLabel))
    }

    // 2. @Bound on let inside State
    for name in analysis.boundOnLetProperties {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.boundOnLetProperty(propertyName: name)))
    }

    // 3. Validate @Bound properties
    let boundProps = analysis.stateBoundProperties
    let storedLetNames = Set(properties.map(\.name))
    var validBounds: [BoundPropertyInfo] = []
    for prop in boundProps {
      if storedLetNames.contains(prop.dependencyName) {
        validBounds.append(prop)
      } else {
        context.diagnose(Diagnostic(
          node: Syntax(declaration),
          message: VISORDiagnostic.invalidBoundDependency(
            name: prop.dependencyName,
            propertyName: prop.propertyName)))
      }
    }

    for propertyName in analysis.malformedStateBoundAttributes {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.malformedBoundKeyPath(propertyName: propertyName, className: className)))
    }

    // 4. Error if any @Bound property has a default value
    for prop in validBounds where prop.hasDefault {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.boundPropertyHasDefault(propertyName: prop.propertyName)))
    }

    // 5. Generate `var state` if not declared by user
    if !analysis.hasStateProperty {
      if !validBounds.isEmpty {
        // @Observable won't track macro-generated stored vars. Generate manual
        // observation accessors that call access/withMutation (provided by @Observable).
        let backingDecl: DeclSyntax = "private var _state: State"
        let computedDecl: DeclSyntax = """
          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }
          """
        members.append(backingDecl)
        members.append(computedDecl)
      } else if analysis.nonBoundPropertiesLackDefaults {
        context.diagnose(Diagnostic(
          node: Syntax(declaration),
          message: VISORDiagnostic.stateNotDefaultInitializable))
        return []
      } else {
        let stateDecl: DeclSyntax = """
          var state = State()
          """
        members.append(stateDecl)
      }
    } else if analysis.statePropertyMissingInitializer && validBounds.isEmpty {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.statePropertyMissingInitializer))
      return []
    }

    // 6. Generate memberwise init (if none exists)
    if !analysis.hasInitializer {
      if !properties.isEmpty || !validBounds.isEmpty {
        let params = properties.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        var assignments = properties.map { "self.\($0.name) = \($0.name)" }

        if !validBounds.isEmpty {
          let stateArgs = validBounds.map { prop in
            "\(prop.propertyName): \(prop.sourceExpression)"
          }.joined(separator: ", ")
          // Use _state directly to avoid triggering observation during init
          let stateTarget = analysis.hasStateProperty ? "self.state" : "self._state"
          assignments.append("\(stateTarget) = State(\(stateArgs))")
        }

        let body = assignments.joined(separator: "\n        ")
        let initDecl: DeclSyntax = """
          \(raw: prefix)init(\(raw: params)) {
              \(raw: body)
          }
          """
        members.append(initDecl)
      }
    }

    // 6. Generate Factory typealias
    let typealiasDecl: DeclSyntax = """
      \(raw: prefix)typealias Factory = ViewModelFactory<\(raw: className)>
      """
    members.append(typealiasDecl)

    // 7. Generate observe methods from @Bound properties inside State
    var allObserveMethodNames: [String] = []
    allObserveMethodNames.reserveCapacity(validBounds.count + analysis.reactionMethods.count)

    for prop in validBounds {
      let methodName = "observe\(prop.propertyName.capitalizedFirst)"
      allObserveMethodNames.append(methodName)
      let keyPath = "\\." + prop.propertyName
      let observeMethod: DeclSyntax = """
        func \(raw: methodName)() async {
            for await value in VISOR.valuesOf({ self.\(raw: prop.sourceExpression) }) {
                self.updateState(\(raw: keyPath), to: value)
            }
        }
        """
      members.append(observeMethod)
    }

    // 8. Diagnose invalid @Reaction methods
    for methodName in analysis.invalidReactionMethods {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.invalidReactionParameter(methodName: methodName)))
    }

    for methodName in analysis.malformedReactionKeyPaths {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.malformedReactionKeyPath(methodName: methodName)))
    }

    // Generate observe wrappers for @Reaction methods
    for reaction in analysis.reactionMethods {
      let methodName = "observe\(reaction.methodName.capitalizedFirst)"
      allObserveMethodNames.append(methodName)
      if reaction.isAsync {
        let observeMethod: DeclSyntax = """
          func \(raw: methodName)() async {
              await VISOR.latestValuesOf({ \(raw: reaction.observeExpression) }) { \(raw: reaction.parameterName) in
                  await self.\(raw: reaction.methodName)(\(raw: reaction.parameterName): \(raw: reaction.parameterName))
              }
          }
          """
        members.append(observeMethod)
      } else {
        let observeMethod: DeclSyntax = """
          func \(raw: methodName)() async {
              for await \(raw: reaction.parameterName) in VISOR.valuesOf({ \(raw: reaction.observeExpression) }) {
                  self.\(raw: reaction.methodName)(\(raw: reaction.parameterName): \(raw: reaction.parameterName))
              }
          }
          """
        members.append(observeMethod)
      }
    }

    // 9. Generate startObserving() or warn about missing calls in manual implementation
    if !allObserveMethodNames.isEmpty {
      if analysis.hasStartObserving {
        let body = analysis.startObservingBodyText ?? ""
        for methodName in allObserveMethodNames {
          if !body.contains(methodName) {
            context.diagnose(Diagnostic(
              node: Syntax(declaration),
              message: VISORDiagnostic.manualStartObservingMissingMethod(methodName: methodName)))
          }
        }
      } else if allObserveMethodNames.count == 1 {
        let observingDecl: DeclSyntax = """
          func startObserving() async {
              await \(raw: allObserveMethodNames[0])()
          }
          """
        members.append(observingDecl)
      } else {
        let tasks = allObserveMethodNames.map { name in
          return """
                      group.addTask { await self.\(name)() }
          """
        }.joined(separator: "\n")
        let observingDecl: DeclSyntax = """
          func startObserving() async {
              await withDiscardingTaskGroup { group in
          \(raw: tasks)
              }
          }
          """
        members.append(observingDecl)
      }
    }

    return members
  }

  // MARK: - ExtensionMacro (adds ViewModel conformance)

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo _: [TypeSyntax],
    in _: some MacroExpansionContext)
    throws -> [ExtensionDeclSyntax]
  {
    guard declaration.is(ClassDeclSyntax.self) else { return [] }
    let viewModelExt = makeProtocolExtension(for: type, conformingTo: "ViewModel")

    return [viewModelExt]
  }
}
