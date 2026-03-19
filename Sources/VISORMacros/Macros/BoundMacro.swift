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

/// Marker macro for `@ViewModel` — validates placement inside `struct State`.
/// The actual code generation is handled by `@ViewModel` via `ClassAnalysis`.
public struct BoundMacro: PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    if !isInsideStateStruct(declaration) {
      context.diagnose(Diagnostic(node: Syntax(attribute), message: VISORDiagnostic.boundOutsideState))
    }
    return []
  }
}
