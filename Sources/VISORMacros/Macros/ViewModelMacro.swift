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

    // Warn if @Observable is missing
    let hasObservable = classDecl.attributes.contains { attr in
      attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Observable"
    }
    if !hasObservable {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.missingObservable))
    }

    let className = classDecl.name.trimmedDescription
    let analysis = ClassAnalysis(classDecl)
    let properties = analysis.storedLetProperties
    var members: [DeclSyntax] = []

    // 1. Generate memberwise init (if none exists)
    if !analysis.hasInitializer {
      if !properties.isEmpty {
        let params = properties.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        let assignments = properties.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n    ")

        let initDecl: DeclSyntax = """
          init(\(raw: params)) {
              \(raw: assignments)
          }
          """
        members.append(initDecl)
      }
    }

    // 2. Generate Factory typealias
    let typealiasDecl: DeclSyntax = """
      typealias Factory = ViewModelFactory<\(raw: className)>
      """
    members.append(typealiasDecl)

    // 3. Generate observe methods from @Bound properties
    let boundProps = analysis.boundProperties
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

    // 3a. Diagnose malformed @Bound key paths
    for propertyName in analysis.malformedBoundAttributes {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.malformedBoundKeyPath(propertyName: propertyName)))
    }

    var allObserveMethodNames: [String] = []

    // Generate observe methods for each @Bound property
    for prop in validBounds {
      let methodName = "observe\(prop.propertyName.capitalizedFirst)"
      allObserveMethodNames.append(methodName)
      let observeMethod: DeclSyntax = """
        func \(raw: methodName)() async {
            for await value in VISOR.valuesOf({ self.\(raw: prop.dependencyName).\(raw: prop.propertyName) }) {
                self.\(raw: prop.propertyName) = value
            }
        }
        """
      members.append(observeMethod)
    }

    // 3b. Diagnose invalid @Reaction methods
    for methodName in analysis.invalidReactionMethods {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.invalidReactionParameter(methodName: methodName)))
    }

    // Generate observe wrappers for @Reaction methods
    let reactions = analysis.reactionMethods
    for reaction in reactions {
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

    // 3c. Generate startObserving() combining @Bound + @Reaction (if no manual implementation)
    if !allObserveMethodNames.isEmpty && !analysis.hasStartObserving {
      if allObserveMethodNames.count == 1 {
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

    // 4. Generate static var preview
    let preview: DeclSyntax
    if properties.isEmpty {
      preview = """
        #if DEBUG
        static var preview: \(raw: className) {
          \(raw: className)()
        }
        #endif
        """
    } else {
      let stubArgs = properties.map { prop in
        if prop.isRouterType {
          return "\(prop.name): \(prop.type)()"
        }
        return "\(prop.name): Stub\(prop.type)()"
      }.joined(separator: ",\n      ")

      preview = """
        #if DEBUG
        static var preview: \(raw: className) {
          \(raw: className)(
            \(raw: stubArgs)
          )
        }
        #endif
        """
    }
    members.append(preview)

    return members
  }

  // MARK: - ExtensionMacro (adds ViewModel + PreviewProviding conformance)

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo _: [TypeSyntax],
    in _: some MacroExpansionContext)
    throws -> [ExtensionDeclSyntax]
  {
    let name = type.trimmedDescription

    let viewModelExt = makeProtocolExtension(for: type, conformingTo: "ViewModel")

    // PreviewProviding conformance.
    // In DEBUG the witness is the generated `static var preview` member.
    // In release a fatalError fallback satisfies the requirement (never called).
    let previewExt: DeclSyntax = """
      extension \(raw: name): PreviewProviding {
        #if !DEBUG
        static var preview: \(raw: name) { fatalError() }
        #endif
      }
      """

    return [viewModelExt, previewExt.cast(ExtensionDeclSyntax.self)]
  }
}
