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

    if hasUnknownTypeDefaults(properties: properties, methods: methods) {
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.unknownTypeDefaults(macroName: "Stubbable")))
    }

    var members = generatePropertyDeclarations(properties, access: access)

    // Generate methods
    let prefixes = uniqueMethodPrefixes(for: methods)
    for (method, methodPrefix) in zip(methods, prefixes) {
      members.append(contentsOf: generateReturnStorage(method: method, methodPrefix: methodPrefix, access: access))
      let sig = buildMethodSignature(method, access: access)
      if method.isThrowing {
        let needsGuard = method.returnType.flatMap({ defaultValue(for: $0) }) == nil && method.returnType != nil
        if needsGuard {
          members.append(contentsOf: [
            "  \(sig) {",
            "    guard let result = \(methodPrefix)Result else { fatalError(\"Configure \\(String(describing: \(methodPrefix)Result)) before calling \(method.name)()\") }",
            "    return try result.get()",
            "  }",
          ])
        } else {
          members.append("  \(sig) { try \(methodPrefix)Result.get() }")
        }
      } else if let returnType = method.returnType {
        let needsGuard = defaultValue(for: returnType) == nil
        if needsGuard {
          members.append(contentsOf: [
            "  \(sig) {",
            "    guard let value = \(methodPrefix)ReturnValue else { fatalError(\"Configure \\(String(describing: \(methodPrefix)ReturnValue)) before calling \(method.name)()\") }",
            "    return value",
            "  }",
          ])
        } else {
          members.append("  \(sig) { \(methodPrefix)ReturnValue }")
        }
      } else {
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
      \(raw: prefix)final class \(raw: stubName): \(raw: protocolName) {
      \(raw: body)
      }
      """
    return [result]
  }
}
