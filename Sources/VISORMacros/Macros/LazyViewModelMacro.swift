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

public struct LazyViewModelMacro: MemberMacro, ExtensionMacro {

  // MARK: Public

  // MARK: ExtensionMacro - adds LazyViewModelView conformance (Mode A only)

  public static func expansion(
    of _: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo _: [TypeSyntax],
    in _: some MacroExpansionContext)
    throws -> [ExtensionDeclSyntax]
  {
    // Mode B (content property) — no LazyViewModelView conformance needed
    if let structDecl = declaration.as(StructDeclSyntax.self), structDecl.hasContentProperty {
      return []
    }
    return [makeProtocolExtension(for: type, conformingTo: "LazyViewModelView")]
  }

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

    let hasLoadedView = structDecl.hasLoadedViewMethod
    let hasContent = structDecl.hasContentProperty

    // Validate: can't have both
    if hasLoadedView && hasContent {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.bothLoadedViewAndContent))
      return []
    }

    // Validate: must have one
    if !hasLoadedView && !hasContent {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingLoadedView))
    }

    if hasContent {
      // Mode B: content property — simplified body, no makeViewModel, no state switch
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

    // Mode A: loadedView method — full state switch with makeViewModel
    return [
      "@Environment(\\.router) private var containerRouter",
      "@Environment(\(raw: factoryType).self) private var factory",
      "@State private var _viewModel: \(raw: viewModelType)?",
      "var viewModel: \(raw: viewModelType) { _viewModel! }",
      "func makeViewModel() -> \(raw: viewModelType) { factory.makeViewModel(router: containerRouter) }",
      """
      var body: some View {
          Group {
              if let viewModel = _viewModel {
                  switch viewModel.state {
                  case .loading:
                      loadingView
                  case .empty:
                      emptyView
                  case .loaded(let state):
                      loadedView(state: state)
                  case .error(let message):
                      errorView(message: message)
                  }
              } else {
                  Color.clear
              }
          }
          .task {
              if _viewModel == nil {
                  _viewModel = makeViewModel()
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
