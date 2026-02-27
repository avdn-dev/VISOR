//
//  BoundMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - BoundMacro

/// No-op peer macro — exists purely as a marker for `@ViewModel` to read.
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
