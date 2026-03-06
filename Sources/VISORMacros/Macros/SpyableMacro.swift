//
//  SpyableMacro.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - SpyableMacro

public struct SpyableMacro: PeerMacro {
  public static func expansion(
    of _: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: TestDoubleDiagnostic.notAProtocol(macroName: "Spyable")))
      return []
    }

    let protocolName = protocolDecl.name.trimmedDescription
    let analysis = ProtocolAnalysis(protocolDecl)

    guard validateProtocolForTestDouble(analysis, protocolDecl: protocolDecl, macroName: "Spyable", context: context) else {
      return []
    }

    let properties = analysis.properties
    let methods = analysis.methods
    let access = accessLevel(of: protocolDecl)
    let prefix = access.isEmpty ? "" : "\(access) "

    var members = generatePropertyDeclarations(properties, access: access)
    // Each method generates ~6-8 member lines + 1 Call case; reserve to avoid reallocations.
    members.reserveCapacity(members.count + methods.count * 8 + (methods.isEmpty ? 0 : 3))

    // Generate method spies
    var callCases: [String] = []
    callCases.reserveCapacity(methods.count)

    for method in methods {
      members.append("  // -- \(method.name) --")
      members.append("  \(prefix)var \(method.name)CallCount = 0")

      // Track received args
      if method.parameters.count == 1 {
        let param = method.parameters[0]
        let capName = param.internalName.capitalizedFirst
        members.append("  \(prefix)var \(method.name)Received\(capName): \(param.type)?")
        members.append("  \(prefix)var \(method.name)ReceivedInvocations: [\(param.type)] = []")
      } else if method.parameters.count > 1 {
        let tupleType = "(" + method.parameters.map { "\($0.internalName): \($0.type)" }.joined(separator: ", ") + ")"
        members.append("  \(prefix)var \(method.name)ReceivedArguments: \(tupleType)?")
        members.append("  \(prefix)var \(method.name)ReceivedInvocations: [\(tupleType)] = []")
      }

      // Return value storage
      if let returnType = method.returnType {
        let defaultVal = defaultValue(for: returnType)
        if let defaultVal {
          members.append("  \(prefix)var \(method.name)ReturnValue: \(returnType) = \(defaultVal)")
        } else {
          members.append("  \(prefix)var \(method.name)ReturnValue: \(returnType)!")
        }
      }

      // Method implementation
      let sig = buildMethodSignature(method, access: access)
      var bodyLines: [String] = []
      bodyLines.append("    \(method.name)CallCount += 1")

      if method.parameters.count == 1 {
        let param = method.parameters[0]
        let capName = param.internalName.capitalizedFirst
        bodyLines.append("    \(method.name)Received\(capName) = \(param.internalName)")
        bodyLines.append("    \(method.name)ReceivedInvocations.append(\(param.internalName))")
      } else if method.parameters.count > 1 {
        let tupleVal = "(" + method.parameters.map(\.internalName).joined(separator: ", ") + ")"
        bodyLines.append("    \(method.name)ReceivedArguments = \(tupleVal)")
        bodyLines.append("    \(method.name)ReceivedInvocations.append(\(tupleVal))")
      }

      // Build Call enum case (uses internalName labels — enum cases don't support external/internal split)
      if method.parameters.isEmpty {
        callCases.append("    case \(method.name)")
        bodyLines.append("    calls.append(.\(method.name))")
      } else {
        let caseParams = method.parameters.map { "\($0.internalName): \($0.type)" }.joined(separator: ", ")
        callCases.append("    case \(method.name)(\(caseParams))")
        let callArgs = method.parameters.map { "\($0.internalName): \($0.internalName)" }.joined(separator: ", ")
        bodyLines.append("    calls.append(.\(method.name)(\(callArgs)))")
      }

      if method.returnType != nil {
        bodyLines.append("    return \(method.name)ReturnValue")
      }

      let body = bodyLines.joined(separator: "\n")
      members.append("  \(sig) {")
      members.append(body)
      members.append("  }")
    }

    // Call enum and calls array
    if !methods.isEmpty {
      members.append("  \(prefix)enum Call {")
      for c in callCases {
        members.append(c)
      }
      members.append("  }")
      members.append("  \(prefix)var calls: [Call] = []")
    }

    // Public classes need an explicit init (the synthesized default init is internal)
    if access == "public" {
      members.append("  public init() {}")
    }

    let bodyStr = members.joined(separator: "\n")
    let spyName = "Spy\(protocolName)"

    let result: DeclSyntax = """
      @Observable
      \(raw: prefix)class \(raw: spyName): \(raw: protocolName) {
      \(raw: bodyStr)
      }
      """
    return [result]
  }

}
