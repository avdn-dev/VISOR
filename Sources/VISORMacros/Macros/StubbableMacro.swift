//
//  StubbableMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - StubbableMacro

public struct StubbableMacro: PeerMacro {

  // MARK: - PeerMacro (generates Stub class for protocols)

  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    if let protocolDecl = declaration.as(ProtocolDeclSyntax.self) {
      return try expandProtocol(protocolDecl, in: context)
    }

    context.diagnose(Diagnostic(
      node: Syntax(declaration),
      message: TestDoubleDiagnostic.notAProtocol(macroName: "Stubbable")))
    return []
  }

  // MARK: - Protocol Branch

  private static func expandProtocol(
    _ protocolDecl: ProtocolDeclSyntax,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    let protocolName = protocolDecl.name.trimmedDescription
    let analysis = ProtocolAnalysis(protocolDecl)

    guard validateProtocolForTestDouble(analysis, protocolDecl: protocolDecl, macroName: "Stubbable", context: context) else {
      return []
    }

    let properties = analysis.properties
    let methods = analysis.methods
    let access = accessLevel(of: protocolDecl)
    let prefix = access.isEmpty ? "" : "\(access) "

    var members = generatePropertyDeclarations(properties, access: access)

    // Generate methods
    for method in methods {
      if let returnType = method.returnType {
        let defaultVal = defaultValue(for: returnType)
        let retVarName = "\(method.name)ReturnValue"
        if let defaultVal {
          members.append("  \(prefix)var \(retVarName): \(returnType) = \(defaultVal)")
        } else {
          members.append("  \(prefix)var \(retVarName): \(returnType)!")
        }
        let sig = buildMethodSignature(method, access: access)
        members.append("  \(sig) { \(retVarName) }")
      } else {
        let sig = buildMethodSignature(method, access: access)
        members.append("  \(sig) { }")
      }
    }

    // Public classes need an explicit init (the synthesized default init is internal)
    if access == "public" {
      members.append("  public init() {}")
    }

    let body = members.joined(separator: "\n")
    let stubName = "Stub\(protocolName)"

    let result: DeclSyntax = """
      @Observable
      \(raw: prefix)class \(raw: stubName): \(raw: protocolName) {
      \(raw: body)
      }
      """
    return [result]
  }
}
