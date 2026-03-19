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

/// Marker macro for `@ViewModel` — validates that it's on a method.
/// Context validation (class-level vs nested type) is handled by `ClassAnalysis`.
public struct ReactionMacro: PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    // @Reaction must be on a function declaration
    guard declaration.is(FunctionDeclSyntax.self) else {
      context.diagnose(Diagnostic(node: Syntax(attribute), message: VISORDiagnostic.reactionNotOnMethod))
      return []
    }

    return []
  }
}
