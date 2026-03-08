//
//  LazyViewModelsMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - LazyViewModelsMacro

public struct LazyViewModelsMacro: MemberMacro {

  // MARK: Public

  // MARK: MemberMacro - generates all ViewModel infrastructure

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo _: [TypeSyntax],
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.notAStruct(macroName: "LazyViewModels")))
      return []
    }

    // Parse variadic tuple arguments: (ViewModel.self, Factory.self)
    guard let viewModels = parseViewModelTuples(from: node, in: context) else {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.missingArguments(macroName: "LazyViewModels")))
      return []
    }

    if viewModels.count == 1 {
      context.diagnose(Diagnostic(node: node, message: VISORDiagnostic.singleViewModelInLazyViewModels))
    }

    // Validate content property exists
    if !structDecl.hasContentProperty {
      context.diagnose(
        Diagnostic(
          node: node,
          message: VISORDiagnostic.missingContent(macroName: "LazyViewModels")))
    }

    var members: [DeclSyntax] = []

    // Router context for auto-bridging (non-routed factories ignore it)
    members.append("@Environment(\\.router) private var containerRouter")

    // Generate for each ViewModel pair:
    // - @Environment(FactoryType.self) private var <propertyName>Factory
    // - @State private var _<propertyName>: ViewModelType?
    // - var <propertyName>: ViewModelType { _<propertyName>! }
    for vm in viewModels {
      members.append("@Environment(\(raw: vm.factoryType).self) private var \(raw: vm.propertyName)Factory")
      members.append("@State private var _\(raw: vm.propertyName): \(raw: vm.viewModelType)?")
      members.append("var \(raw: vm.propertyName): \(raw: vm.viewModelType) { _\(raw: vm.propertyName)! }")
    }

    // Build nil checks: _propertyName != nil && ...
    let nilChecks = viewModels.map { "_\($0.propertyName) != nil" }.joined(separator: " && ")

    // Build initialization logic
    let initCode = generateInitialization(viewModels)

    // Build per-VM .task(id:) modifiers for startObserving
    let observingTasks = viewModels.map { vm in
      """
              .task(id: _\(vm.propertyName) != nil) {
                  guard let vm = _\(vm.propertyName) else { return }
                  await vm.startObserving()
              }
      """
    }.joined(separator: "\n")

    members.append("""
      var body: some View {
          Group {
              if \(raw: nilChecks) {
                  content
              } else {
                  Color.clear
              }
          }
          .task {
              \(raw: initCode)
          }
      \(raw: observingTasks)
      }
      """)

    return members
  }

  // MARK: Private

  private static func parseViewModelTuples(
    from node: AttributeSyntax,
    in context: some MacroExpansionContext
  ) -> [ViewModelPairInfo]? {
    guard case .argumentList(let arguments) = node.arguments else {
      return nil
    }

    var pairs: [ViewModelPairInfo] = []
    var hasMalformed = false

    for argument in arguments {
      guard
        let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
        memberAccess.declName.baseName.text == "self",
        let baseType = memberAccess.base?.as(DeclReferenceExprSyntax.self)
      else {
        context.diagnose(Diagnostic(
          node: Syntax(argument),
          message: VISORDiagnostic.malformedLazyViewModelsArgument))
        hasMalformed = true
        continue
      }

      let vmType = baseType.baseName.text
      let factoryType = "\(vmType).Factory"
      let propertyName = vmType.lowercasedFirst

      pairs.append(ViewModelPairInfo(
        viewModelType: vmType,
        factoryType: factoryType,
        propertyName: propertyName))
    }

    // Fail entirely if any argument was malformed — never generate partial code
    guard !hasMalformed, !pairs.isEmpty else {
      return nil
    }

    return pairs
  }

  private static func generateInitialization(_ viewModels: [ViewModelPairInfo]) -> String {
    if viewModels.count == 1 {
      let vm = viewModels[0]
      return """
        if _\(vm.propertyName) == nil {
                    _\(vm.propertyName) = \(vm.propertyName)Factory.makeViewModel(router: containerRouter)
                }
        """
    }

    // Multiple VMs: sequential initialization (avoids async let sending warnings)
    let anyNilCheck = viewModels.map { "_\($0.propertyName) == nil" }.joined(separator: " || ")

    let assignments = viewModels.map { vm in
      "    _\(vm.propertyName) = \(vm.propertyName)Factory.makeViewModel(router: containerRouter)"
    }.joined(separator: "\n")

    return """
      if \(anyNilCheck) {
      \(assignments)
      }
      """
  }

}
