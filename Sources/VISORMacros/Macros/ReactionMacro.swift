//
//  ReactionMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ReactionMacro

/// Marker macro for source-backed `@ViewModel` reaction methods.
public struct ReactionMacro: PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    guard context.isDirectViewModelContext else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.invalidSourceReactionPlacement,
      ))
      return []
    }
    guard
      let function = declaration.as(FunctionDeclSyntax.self),
      function.signature.parameterClause.parameters.count == 1,
      function.signature.returnClause == nil,
      function.signature.effectSpecifiers?.throwsClause == nil,
      !function.modifiers.hasStateTypeStorageModifier,
      attribute.sourceObservationSelection != nil
    else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.invalidSourceReactionDeclaration,
      ))
      return []
    }
    return []
  }
}
