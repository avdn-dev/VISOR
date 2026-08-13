//
//  GenerateTestDoublesSpyMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - VISORTestDoubles spy macro

public struct GenerateTestDoublesSpyMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    try TestDoubleGenerator(kind: .spy).expand(
      node,
      declaration: declaration,
      in: context)
  }
}
