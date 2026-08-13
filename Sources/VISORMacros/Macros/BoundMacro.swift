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

/// Marker macro for source-backed `@ViewModel` State fields.
public struct BoundMacro: PeerMacro {
  public static func expansion(
    of attribute: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    guard context.isDirectViewModelStateContext else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.invalidSourceBoundPlacement))
      return []
    }
    guard
      let variable = declaration.as(VariableDeclSyntax.self),
      let field = stateFieldSpec(from: variable),
      field.accessPrefix != "private ",
      attribute.sourceObservationSelection != nil
    else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: VISORDiagnostic.invalidSourceBoundDeclaration))
      return []
    }
    return []
  }
}
