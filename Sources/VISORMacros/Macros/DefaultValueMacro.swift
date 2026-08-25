//
//  DefaultValueMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 19/2/2026.
//

import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - DefaultValueMacro

/// No-op peer macro — exists purely as a marker for generated stubs and spies to read.
/// `@DefaultValue` and `@DefaultReturn` both use this implementation.
public struct DefaultValueMacro: PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf _: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    []
  }
}
