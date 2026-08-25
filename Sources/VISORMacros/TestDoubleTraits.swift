//
//  TestDoubleTraits.swift
//  VISOR
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct TestDoubleTraits {
  var isSendable = false

  static func parse(
    from node: AttributeSyntax,
    macroName: String,
    in context: some MacroExpansionContext,
  ) -> TestDoubleTraits? {
    guard case .argumentList(let arguments) = node.arguments else {
      return TestDoubleTraits()
    }

    var traits = TestDoubleTraits()
    for argument in arguments {
      guard argument.label == nil else {
        context.diagnose(Diagnostic(
          node: Syntax(argument),
          message: TestDoubleDiagnostic.unsupportedTrait(
            trait: argument.expression.trimmedDescription,
            macroName: macroName,
          ),
        ))
        return nil
      }

      guard let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) else {
        context.diagnose(Diagnostic(
          node: Syntax(argument),
          message: TestDoubleDiagnostic.unsupportedTrait(
            trait: argument.expression.trimmedDescription,
            macroName: macroName,
          ),
        ))
        return nil
      }

      let trait = memberAccess.declName.baseName.text
      guard trait == "sendable" else {
        context.diagnose(Diagnostic(
          node: Syntax(argument),
          message: TestDoubleDiagnostic.unsupportedTrait(trait: trait, macroName: macroName),
        ))
        return nil
      }

      guard !traits.isSendable else {
        context.diagnose(Diagnostic(
          node: Syntax(argument),
          message: TestDoubleDiagnostic.duplicateTrait(trait: trait, macroName: macroName),
        ))
        return nil
      }
      traits.isSendable = true
    }

    return traits
  }
}
