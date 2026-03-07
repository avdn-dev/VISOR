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

    guard let (viewModelType, factoryType) = parseArguments(from: node) else {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingArguments(macroName: "LazyViewModel")))
      return []
    }

    let hasContent = structDecl.hasContentProperty

    // Validate: must have content
    if !hasContent {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingContent(macroName: "LazyViewModel")))
    }

    // Content property — simplified body, no makeViewModel, no state switch
    return [
      "@Environment(\\.router) private var containerRouter",
      "@Environment(\(raw: factoryType).self) private var factory",
      "@State private var _viewModel: \(raw: viewModelType)?",
      "var viewModel: \(raw: viewModelType) { _viewModel! }",
      """
      var body: some View {
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
          .task(id: _viewModel != nil) {
              guard let vm = _viewModel else { return }
              await vm.startObserving()
          }
      }
      """,
    ]
  }

  // MARK: Private

  private static func parseArguments(from node: AttributeSyntax) -> (viewModelType: String, factoryType: String)? {
    guard
      case .argumentList(let arguments) = node.arguments,
      let firstArg = arguments.first,
      let memberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
      memberAccess.declName.baseName.text == "self",
      let baseType = memberAccess.base?.as(DeclReferenceExprSyntax.self)
    else {
      return nil
    }

    let vm = baseType.baseName.text
    return (vm, "\(vm).Factory")
  }
}
