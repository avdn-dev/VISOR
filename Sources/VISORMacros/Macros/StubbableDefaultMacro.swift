//
//  StubbableDefaultMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - StubbableDefaultMacro

/// No-op peer macro — exists purely as a marker for `@Stubbable` / `@Spyable` to read.
public struct StubbableDefaultMacro: PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf _: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    []
  }
}
