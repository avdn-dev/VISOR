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

/// Marker macro for `@ViewModel` — validates that it's on a method at the class level.
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

    // Walk up to find containing type — must be a class, not a nested struct/enum
    var current: Syntax? = Syntax(declaration).parent
    while let node = current {
      if node.is(ClassDeclSyntax.self) {
        return [] // Valid — at class level
      }
      if node.is(StructDeclSyntax.self) || node.is(EnumDeclSyntax.self) {
        context.diagnose(Diagnostic(node: Syntax(attribute), message: VISORDiagnostic.reactionInsideNestedType))
        return []
      }
      current = node.parent
    }

    return []
  }
}
