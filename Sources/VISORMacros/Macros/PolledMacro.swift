//
//  PolledMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/3/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - PolledMacro

/// Marker macro for `@ViewModel` — validates placement inside `struct State`.
/// The actual code generation is handled by `@ViewModel` via `ClassAnalysis`.
public struct PolledMacro: PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    if !isInsideStateStruct(declaration) {
      context.diagnose(Diagnostic(node: Syntax(attribute), message: VISORDiagnostic.polledOutsideState))
    }
    return []
  }
}
