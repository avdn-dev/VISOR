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

/// Marker macro for `@ViewModel` — placement validation is handled by `@ViewModel` itself.
/// This peer macro is intentionally a no-op; it exists only so the compiler
/// recognises `@Bound(…)` as a valid attribute on variable declarations.
public struct BoundMacro: PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf _: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    []
  }
}
