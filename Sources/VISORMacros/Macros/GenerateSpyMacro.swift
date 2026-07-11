//
//  GenerateSpyMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - GenerateSpyMacro

public struct GenerateSpyMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    try TestDoubleGenerator(kind: .spy).expand(node, declaration: declaration, in: context)
  }
}
