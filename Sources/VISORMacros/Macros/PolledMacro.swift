//
//  PolledMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/3/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - PolledMacro

/// Marker macro for `@ViewModel` — placement is validated by `ClassAnalysis`.
/// This peer macro is intentionally a no-op; it exists only so the compiler
/// recognises `@Polled(…)` as a valid attribute on variable declarations.
public struct PolledMacro: PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf _: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    []
  }
}
