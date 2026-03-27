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

  // MARK: - MemberMacro (generates init, Factory typealias, _state, updateState, observe methods)

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
      attr.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text == AttributeName.observable
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

    // 1. State diagnostics (early — before init generation)
    if !analysis.hasStateClass {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.missingState))
      return []
    }

    if !analysis.stateClassIsFinal {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.stateClassNotFinal))
    }

    if !analysis.stateClassHasObservable {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.stateClassMissingObservable))
    }

    if !analysis.stateClassHasInit {
      let boundNames = analysis.stateBoundProperties.map(\.propertyName)
      let polledNames = analysis.statePolledProperties.map(\.propertyName)
      let paramNames = boundNames + polledNames
      let sig = paramNames.isEmpty
        ? "nonisolated init() {}"
        : "nonisolated init(\(paramNames.joined(separator: ":, ")):) { ... }"
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.stateClassMissingInit(expectedSignature: sig)))
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

    // 2b. @Polled on let inside State
    for name in analysis.polledOnLetProperties {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.polledOnLetProperty(propertyName: name)))
    }

    // 2c. @Bound/@Polled on class-level properties (misplaced)
    for _ in analysis.boundOutsideState {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.boundOutsideState))
    }
    for _ in analysis.polledOutsideState {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.polledOutsideState))
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

    // 3b. Validate @Polled properties
    let polledProps = analysis.statePolledProperties
    var validPolled: [PolledPropertyInfo] = []
    for prop in polledProps {
      if storedLetNames.contains(prop.dependencyName) {
        validPolled.append(prop)
      } else {
        context.diagnose(Diagnostic(
          node: Syntax(declaration),
          message: VISORDiagnostic.invalidPolledDependency(
            name: prop.dependencyName,
            propertyName: prop.propertyName)))
      }
    }

    for propertyName in analysis.malformedStatePolledAttributes {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.malformedPolledKeyPath(propertyName: propertyName, className: className)))
    }

    for propertyName in analysis.polledMissingInterval {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.polledMissingInterval(propertyName: propertyName)))
    }

    // 4. Error if any @Bound property has a default value
    for prop in validBounds where prop.hasDefault {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.boundPropertyHasDefault(propertyName: prop.propertyName)))
    }

    // 4b. Error if any @Polled property has a default value
    for prop in validPolled where prop.hasDefault {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.polledPropertyHasDefault(propertyName: prop.propertyName)))
    }

    let hasServiceInitProps = !validBounds.isEmpty || !validPolled.isEmpty

    // 5. Generate @ObservationIgnored _state + computed state (unless user declared var state)
    if !analysis.hasStateProperty {
      let backingDecl: DeclSyntax = hasServiceInitProps
        ? "@ObservationIgnored private var _state: State"
        : "@ObservationIgnored private var _state: State = State()"
      let computedDecl: DeclSyntax = """
        \(raw: prefix)var state: State {
            get { access(keyPath: \\.state); return _state }
            set { withMutation(keyPath: \\.state) { _state = newValue } }
        }
        """
      members.append(backingDecl)
      members.append(computedDecl)
    }

    // 5. Always generate updateState using _state directly
    let updateEquatable: DeclSyntax = """
      func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
          guard _state[keyPath: keyPath] != value else { return }
          _state[keyPath: keyPath] = value
      }
      """
    let updateNonEquatable: DeclSyntax = """
      func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
          _state[keyPath: keyPath] = value
      }
      """
    members.append(updateEquatable)
    members.append(updateNonEquatable)

    // 6. Generate memberwise init (if none exists)
    if !analysis.hasInitializer {
      if !properties.isEmpty || hasServiceInitProps {
        let params = properties.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        var assignments = properties.map { "self.\($0.name) = \($0.name)" }

        if hasServiceInitProps {
          // Merge @Bound and @Polled args, sorted by declaration order.
          // Calls the user-declared State memberwise init.
          let boundArgs: [(order: Int, arg: String)] = validBounds.map { prop in
            (prop.declarationOrder, "\(prop.propertyName): \(prop.sourceExpression)")
          }
          let polledArgs: [(order: Int, arg: String)] = validPolled.map { prop in
            (prop.declarationOrder, "\(prop.propertyName): \(prop.sourceExpression)")
          }
          let combinedArgs = (boundArgs + polledArgs)
            .sorted(by: { $0.order < $1.order })
            .map(\.arg)
            .joined(separator: ", ")

          assignments.append("self._state = State(\(combinedArgs))")
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

    // 7. Generate Factory typealias
    let typealiasDecl: DeclSyntax = """
      \(raw: prefix)typealias Factory = ViewModelFactory<\(raw: className)>
      """
    members.append(typealiasDecl)

    // 8. Generate observe methods from @Bound properties inside State
    var allObserveMethodNames: [String] = []
    allObserveMethodNames.reserveCapacity(validBounds.count + validPolled.count + analysis.reactionMethods.count)

    for prop in validBounds {
      let methodName = "observe\(prop.propertyName.capitalizedFirst)"
      allObserveMethodNames.append(methodName)
      let keyPath = "\\." + prop.propertyName
      let observeMethod: DeclSyntax
      if let throttleExpr = prop.throttleExpression {
        observeMethod = """
          func \(raw: methodName)() async {
              for await value in VISOR.valuesOf({ self.\(raw: prop.sourceExpression) }) {
                  self.updateState(\(raw: keyPath), to: value)
                  do {
                      try await Task.sleep(for: \(raw: throttleExpr))
                  } catch {}
              }
          }
          """
      } else {
        observeMethod = """
          func \(raw: methodName)() async {
              for await value in VISOR.valuesOf({ self.\(raw: prop.sourceExpression) }) {
                  self.updateState(\(raw: keyPath), to: value)
              }
          }
          """
      }
      members.append(observeMethod)
    }

    // 8b. Generate observe methods from @Polled properties inside State
    for prop in validPolled {
      let methodName = "observe\(prop.propertyName.capitalizedFirst)"
      allObserveMethodNames.append(methodName)
      let keyPath = "\\." + prop.propertyName
      let observeMethod: DeclSyntax = """
        func \(raw: methodName)() async {
            self.updateState(\(raw: keyPath), to: self.\(raw: prop.sourceExpression))
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: \(raw: prop.intervalExpression))
                    self.updateState(\(raw: keyPath), to: self.\(raw: prop.sourceExpression))
                }
            } catch {}
        }
        """
      members.append(observeMethod)
    }

    // 8c. Diagnose invalid @Reaction methods
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
        let observeMethod: DeclSyntax
        if let throttleExpr = reaction.throttleExpression {
          observeMethod = """
            func \(raw: methodName)() async {
                for await \(raw: reaction.parameterName) in VISOR.valuesOf({ \(raw: reaction.observeExpression) }) {
                    await self.\(raw: reaction.methodName)(\(raw: reaction.parameterName): \(raw: reaction.parameterName))
                    do {
                        try await Task.sleep(for: \(raw: throttleExpr))
                    } catch {}
                }
            }
            """
        } else {
          observeMethod = """
            func \(raw: methodName)() async {
                for await \(raw: reaction.parameterName) in VISOR.valuesOf({ \(raw: reaction.observeExpression) }) {
                    await self.\(raw: reaction.methodName)(\(raw: reaction.parameterName): \(raw: reaction.parameterName))
                }
            }
            """
        }
        members.append(observeMethod)
      } else {
        let observeMethod: DeclSyntax
        if let throttleExpr = reaction.throttleExpression {
          observeMethod = """
            func \(raw: methodName)() async {
                for await \(raw: reaction.parameterName) in VISOR.valuesOf({ \(raw: reaction.observeExpression) }) {
                    self.\(raw: reaction.methodName)(\(raw: reaction.parameterName): \(raw: reaction.parameterName))
                    do {
                        try await Task.sleep(for: \(raw: throttleExpr))
                    } catch {}
                }
            }
            """
        } else {
          observeMethod = """
            func \(raw: methodName)() async {
                for await \(raw: reaction.parameterName) in VISOR.valuesOf({ \(raw: reaction.observeExpression) }) {
                    self.\(raw: reaction.methodName)(\(raw: reaction.parameterName): \(raw: reaction.parameterName))
                }
            }
            """
        }
        members.append(observeMethod)
      }
    }

    // 9. Generate startObserving() or warn about missing calls in manual implementation
    if !allObserveMethodNames.isEmpty {
      if analysis.hasStartObserving {
        let body = analysis.startObservingBodyText ?? ""
        let bodyTokens = Set(body.split(whereSeparator: { !$0.isLetter && $0 != "_" && !$0.isNumber }).map(String.init))
        for methodName in allObserveMethodNames {
          if !bodyTokens.contains(methodName) {
            context.diagnose(Diagnostic(
              node: Syntax(declaration),
              message: VISORDiagnostic.manualStartObservingMissingMethod(methodName: methodName)))
          }
        }
      } else if allObserveMethodNames.count == 1 {
        let observingDecl: DeclSyntax = """
          \(raw: prefix)func startObserving() async {
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
          \(raw: prefix)func startObserving() async {
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
