//
//  GenerateStubMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - GenerateStubMacro

public struct GenerateStubMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    try TestDoubleGenerator(kind: .stub).expand(node, declaration: declaration, in: context)
  }
}
