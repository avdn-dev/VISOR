//
//  BoundMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - BoundMacro

/// Marker macro for `@ViewModel` — validates that it's on a `var` inside `struct State`.
public struct BoundMacro: PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    // @Bound must be on a variable declaration (var or let — let is caught separately by @ViewModel)
    guard declaration.is(VariableDeclSyntax.self) else {
      context.diagnose(Diagnostic(node: Syntax(attribute), message: VISORDiagnostic.boundOutsideState))
      return []
    }

    // Walk up to find the containing type — must be struct State
    var current: Syntax? = Syntax(declaration).parent
    while let node = current {
      if let structDecl = node.as(StructDeclSyntax.self) {
        if structDecl.name.text != "State" {
          context.diagnose(Diagnostic(node: Syntax(attribute), message: VISORDiagnostic.boundOutsideState))
        }
        return []
      }
      if node.is(ClassDeclSyntax.self) || node.is(EnumDeclSyntax.self) {
        break
      }
      current = node.parent
    }

    // Reached class/enum/top-level without finding struct State
    context.diagnose(Diagnostic(node: Syntax(attribute), message: VISORDiagnostic.boundOutsideState))
    return []
  }
}
