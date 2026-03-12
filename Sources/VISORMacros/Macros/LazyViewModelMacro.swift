//
//  LazyViewModelMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - LazyViewModelMacro

public struct LazyViewModelMacro: MemberMacro {

  // MARK: Public

  // MARK: MemberMacro - generates all declarations

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.notAStruct(macroName: "LazyViewModel")))
      return []
    }

    guard let (viewModelType, factoryType, observationPolicy) = parseArguments(from: node, in: context) else {
      return []
    }

    let hasContent = structDecl.hasContentProperty

    // Validate: must have content
    if !hasContent {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingContent(macroName: "LazyViewModel")))
      return []
    }

    let access = accessLevel(of: structDecl)
    let prefix = access.isEmpty ? "" : "\(access) "

    let taskIdExpression: String
    let guardCondition: String

    switch observationPolicy {
    case "pauseInBackground":
      taskIdExpression = "scenePhase != .background && _viewModel != nil"
      guardCondition = "guard let vm = _viewModel, scenePhase != .background else { return }"
    case "pauseWhenInactive":
      taskIdExpression = "scenePhase == .active && _viewModel != nil"
      guardCondition = "guard let vm = _viewModel, scenePhase == .active else { return }"
    default:
      taskIdExpression = "_viewModel != nil"
      guardCondition = "guard let vm = _viewModel else { return }"
    }

    var members: [DeclSyntax] = [
      "@Environment(\\.router) private var containerRouter",
      "@Environment(\(raw: factoryType).self) private var factory",
    ]

    if observationPolicy != "alwaysObserving" {
      members.append("@Environment(\\.scenePhase) private var scenePhase")
    }

    members.append(contentsOf: [
      "@State private var _viewModel: \(raw: viewModelType)?",
      "var viewModel: \(raw: viewModelType) { _viewModel! }",
      """
      \(raw: prefix)var body: some View {
          Group {
              if _viewModel != nil {
                  content
              } else {
                  Color.clear
              }
          }
          .task {
              if _viewModel == nil {
                  _viewModel = factory.makeViewModel(router: containerRouter)
              }
          }
          .task(id: \(raw: taskIdExpression)) {
              \(raw: guardCondition)
              await vm.startObserving()
          }
      }
      """,
    ])

    return members
  }

  // MARK: Private

  private static let validPolicies: Set<String> = [
    "alwaysObserving", "pauseInBackground", "pauseWhenInactive",
  ]

  private static func parseArguments(
    from node: AttributeSyntax,
    in context: some MacroExpansionContext
  ) -> (viewModelType: String, factoryType: String, observationPolicy: String)? {
    // Stage 1: Must have an argument list
    guard case .argumentList(let arguments) = node.arguments, let firstArg = arguments.first else {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingArguments(macroName: "LazyViewModel")))
      return nil
    }

    // Stage 2: First arg must be a member access expression with `.self`
    guard
      let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
      memberAccess.declName.baseName.text == "self",
      let baseType = memberAccess.base?.as(DeclReferenceExprSyntax.self)
    else {
      context.diagnose(Diagnostic(node: Syntax(firstArg), message: VISORDiagnostic.missingSelfSuffix(macroName: "LazyViewModel")))
      return nil
    }

    let vm = baseType.baseName.text

    // Stage 3: Optional observationPolicy parameter
    var policy = "alwaysObserving"
    let secondIndex = arguments.index(after: arguments.startIndex)
    if secondIndex != arguments.endIndex {
      let secondArg = arguments[secondIndex]
      if secondArg.label?.text == "observationPolicy",
         let policyAccess = secondArg.expression.as(MemberAccessExprSyntax.self)
      {
        let value = policyAccess.declName.baseName.text
        guard validPolicies.contains(value) else {
          context.diagnose(Diagnostic(node: Syntax(secondArg), message: VISORDiagnostic.invalidObservationPolicy))
          return nil
        }
        policy = value
      }
    }

    return (vm, "\(vm).Factory", policy)
  }
}
