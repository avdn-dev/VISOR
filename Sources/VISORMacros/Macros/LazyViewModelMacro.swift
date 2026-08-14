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

    guard let (viewModelType, observationPolicy) = parseArguments(from: node, in: context) else {
      return []
    }

    let hasContent = structDecl.hasContentProperty
    let hasStateMember = structDecl.hasMemberNamed("state")

    // Validate: must have content
    if !hasContent {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingContent(macroName: "LazyViewModel")))
      return []
    }

    let access = accessLevel(of: structDecl)
    // Only propagate public/open to generated members. Other access levels
    // (internal, package, fileprivate, private) are inherited from the type,
    // avoiding "more accessible than enclosing type" build errors.
    let prefix = (access == "public" || access == "open") ? "\(access) " : ""

    var members: [DeclSyntax] = [
      "@Environment(\\.router) private var containerRouter",
      "@Environment(VISOR.ViewModelFactory<\(raw: viewModelType)>.self) private var factory",
    ]

    members.append(contentsOf: [
      "@State private var _viewModel: \(raw: viewModelType)?",
      """
      var viewModel: \(raw: viewModelType) {
          guard let vm = _viewModel else {
              preconditionFailure("@LazyViewModel internal error: \(raw: viewModelType) viewModel accessed while _viewModel is nil — content should only render after initialisation.")
          }
          return vm
      }
      """,
    ])

    if hasStateMember {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.lazyViewModelStateAliasCollision))
    } else {
      members.append("var state: \(raw: viewModelType).State { viewModel.state }")
    }

    members.append(contentsOf: [
      "var bindableState: Bindable<\(raw: viewModelType).State> { Bindable(viewModel.state) }",
      """
      \(raw: prefix)var body: some View {
          Group {
              if let viewModel = _viewModel {
                  VISOR._visorOwnedViewModelContent(
                      for: viewModel,
                      observationPolicy: \(raw: observationPolicy)
                  ) { _ in
                      content
                  }
              } else {
                  Color.clear
              }
          }
          .task {
              if _viewModel == nil {
                  _viewModel = factory.makeViewModel(router: containerRouter)
              }
          }
      }
      """,
    ])

    return members
  }

  // MARK: Private

  private static func parseArguments(
    from node: AttributeSyntax,
    in context: some MacroExpansionContext
  ) -> (viewModelType: String, observationPolicy: String)? {
    // Stage 1: Must have an argument list
    guard case .argumentList(let arguments) = node.arguments, let firstArg = arguments.first else {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingArguments(macroName: "LazyViewModel")))
      return nil
    }

    // Stage 2: Preserve the complete type expression before `.self`. The macro
    // declaration's VM.Type constraint remains the source of truth for whether
    // the expression names a ViewModel type.
    guard
      let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
      memberAccess.declName.baseName.text == "self",
      let baseType = memberAccess.base
    else {
      context.diagnose(Diagnostic(node: Syntax(firstArg), message: VISORDiagnostic.missingSelfSuffix(macroName: "LazyViewModel")))
      return nil
    }

    let viewModelType = baseType.trimmedDescription

    // Stage 3: Preserve any valid ObservationPolicy expression. Swift type
    // checks it against the public macro declaration, avoiding a duplicated
    // case list that can drift when ObservationPolicy evolves.
    let observationPolicy = arguments.dropFirst().first {
      $0.label?.text == "observationPolicy"
    }?.expression.trimmedDescription ?? ".alwaysObserving"

    return (viewModelType, observationPolicy)
  }
}
