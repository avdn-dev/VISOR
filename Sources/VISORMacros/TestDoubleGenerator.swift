//
//  TestDoubleGenerator.swift
//  VISOR
//
//  Created by Anh Nguyen on 4/6/2026.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - TestDoubleKind

enum TestDoubleKind {
  case stub
  case spy

  var macroName: String {
    switch self {
    case .stub:
      return "GenerateStub"
    case .spy:
      return "GenerateSpy"
    }
  }

  var generatedTypePrefix: String {
    switch self {
    case .stub:
      return "Stub"
    case .spy:
      return "Spy"
    }
  }
}

// MARK: - TestDoubleGenerator

struct TestDoubleGenerator {
  let kind: TestDoubleKind

  func expand(
    _ declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: TestDoubleDiagnostic.notAProtocol(macroName: kind.macroName)))
      return []
    }

    let protocolName = protocolDecl.name.trimmedDescription
    let analysis = ProtocolAnalysis(protocolDecl)

    guard validateProtocolForTestDouble(analysis, protocolDecl: protocolDecl, macroName: kind.macroName, context: context) else {
      return []
    }

    let properties = analysis.properties
    let methods = analysis.methods
    let access = accessLevel(of: protocolDecl)
    let prefix = access.isEmpty ? "" : "\(access) "

    if hasUnknownTypeDefaults(properties: properties, methods: methods) {
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.unknownTypeDefaults(macroName: kind.macroName)))
    }

    var members = generatePropertyDeclarations(properties, access: access)

    switch kind {
    case .stub:
      members.append(contentsOf: generateStubMethodMembers(methods, access: access))
    case .spy:
      members.append(contentsOf: generateSpyMethodMembers(
        methods,
        properties: properties,
        access: access,
        protocolDecl: protocolDecl,
        context: context))
    }

    // Public classes need an explicit init (the synthesized default init is internal).
    if access == "public" {
      members.append("  public init() {}")
    }

    let body = members.joined(separator: "\n")
    let typeName = "\(kind.generatedTypePrefix)\(protocolName)"

    let result: DeclSyntax = """
      @Observable
      \(raw: prefix)final class \(raw: typeName): \(raw: protocolName) {
      \(raw: body)
      }
      """
    return [result]
  }

  private func generateStubMethodMembers(
    _ methods: [ProtocolMethodInfo],
    access: String)
    -> [String]
  {
    let methodPrefixes = uniqueMethodPrefixes(for: methods)
    var members: [String] = []

    for (method, methodPrefix) in zip(methods, methodPrefixes) {
      members.append(contentsOf: generateReturnStorage(method: method, methodPrefix: methodPrefix, access: access))

      let sig = buildMethodSignature(method, access: access)
      let bodyLines = generateFallbackBodyLines(method: method, methodPrefix: methodPrefix, style: .expression)

      if bodyLines.isEmpty {
        members.append("  \(sig) { }")
      } else if bodyLines.count == 1 {
        members.append("  \(sig) { \(bodyLines[0].trimmingWhitespace) }")
      } else {
        members.append("  \(sig) {")
        members.append(contentsOf: bodyLines)
        members.append("  }")
      }
    }

    return members
  }

  private func generateSpyMethodMembers(
    _ methods: [ProtocolMethodInfo],
    properties: [ProtocolPropertyInfo],
    access: String,
    protocolDecl: ProtocolDeclSyntax,
    context: some MacroExpansionContext)
    -> [String]
  {
    let prefix = access.isEmpty ? "" : "\(access) "
    let methodPrefixes = uniqueMethodPrefixes(for: methods)
    let implementationNames = implementationStorageNames(
      for: methods,
      methodPrefixes: methodPrefixes,
      properties: properties)

    var members: [String] = []
    // Each method generates ~6-8 member lines + 1 Call case; reserve to avoid reallocations.
    members.reserveCapacity(methods.count * 8 + (methods.isEmpty ? 0 : 3))

    var callCases: [String] = []
    callCases.reserveCapacity(methods.count)

    for ((method, methodPrefix), implementationName) in zip(zip(methods, methodPrefixes), implementationNames) {
      let preferredImplementationName = "\(methodPrefix)Implementation"
      let supportsImplementation = supportsImplementationClosure(for: method)

      if supportsImplementation && implementationName != preferredImplementationName {
        context.diagnose(Diagnostic(
          node: Syntax(protocolDecl),
          message: TestDoubleDiagnostic.implementationNameCollision(
            methodName: method.name,
            preferredName: preferredImplementationName,
            generatedName: implementationName,
            macroName: kind.macroName)))
      }

      members.append("  // -- \(methodPrefix) --")
      members.append("  \(prefix)var \(methodPrefix)CallCount = 0")

      let receivedParams = method.parameters.filter { !$0.isInout }
      let storableParams = receivedParams.filter { spyStorageType(for: $0, method: method) != nil }
      members.append(contentsOf: generateReceivedArgumentStorage(
        method: method,
        methodPrefix: methodPrefix,
        storableParams: storableParams,
        access: access))

      members.append(contentsOf: generateReturnStorage(method: method, methodPrefix: methodPrefix, access: access))
      if supportsImplementation {
        members.append(contentsOf: generateImplementationStorage(method: method, implementationName: implementationName, access: access))
      }

      let sig = buildMethodSignature(method, access: access)
      var bodyLines = generateSpyRecordingBodyLines(
        method: method,
        methodPrefix: methodPrefix,
        storableParams: storableParams,
        callCases: &callCases)

      bodyLines.append(contentsOf: generateSpyImplementationBodyLines(
        method: method,
        methodPrefix: methodPrefix,
        implementationName: supportsImplementation ? implementationName : nil))

      let body = bodyLines.joined(separator: "\n")
      members.append("  \(sig) {")
      members.append(body)
      members.append("  }")
    }

    if !methods.isEmpty {
      members.append("  \(prefix)enum Call {")
      for callCase in callCases {
        members.append(callCase)
      }
      members.append("  }")
      members.append("  \(prefix)var calls: [Call] = []")
    }

    return members
  }

  private func generateReceivedArgumentStorage(
    method: ProtocolMethodInfo,
    methodPrefix: String,
    storableParams: [ParameterInfo],
    access: String)
    -> [String]
  {
    let prefix = access.isEmpty ? "" : "\(access) "

    if storableParams.count == 1 {
      let param = storableParams[0]
      let capName = param.internalName.capitalisedFirst
      guard let strippedType = spyStorageType(for: param, method: method) else { return [] }
      // Wrap function types in parens so ? applies to the whole function, not just the return type.
      let wrappedType = isFunctionType(strippedType) ? "(\(strippedType))" : strippedType
      let fnIgnored = isFunctionType(strippedType) ? "  @ObservationIgnored\n" : ""
      return [
        "\(fnIgnored)  \(prefix)var \(methodPrefix)Received\(capName): \(wrappedType)?",
        "\(fnIgnored)  \(prefix)var \(methodPrefix)ReceivedInvocations: [\(wrappedType)] = []"
      ]
    }

    if storableParams.count > 1 {
      let innerTypes = storableParams.compactMap { spyStorageType(for: $0, method: method) }
      let anyFn = innerTypes.contains(where: isFunctionType)
      let tupleType = "(" + zip(storableParams, innerTypes).map { "\($0.0.internalName): \($0.1)" }.joined(separator: ", ") + ")"
      let wrappedType = anyFn ? "(\(tupleType))" : tupleType
      let fnIgnored = anyFn ? "  @ObservationIgnored\n" : ""
      return [
        "\(fnIgnored)  \(prefix)var \(methodPrefix)ReceivedArguments: \(wrappedType)?",
        "\(fnIgnored)  \(prefix)var \(methodPrefix)ReceivedInvocations: [\(wrappedType)] = []"
      ]
    }

    return []
  }

  private func generateSpyRecordingBodyLines(
    method: ProtocolMethodInfo,
    methodPrefix: String,
    storableParams: [ParameterInfo],
    callCases: inout [String])
    -> [String]
  {
    var bodyLines: [String] = []
    bodyLines.append("    \(methodPrefix)CallCount += 1")

    if storableParams.count == 1 {
      let param = storableParams[0]
      let capName = param.internalName.capitalisedFirst
      bodyLines.append("    \(methodPrefix)Received\(capName) = \(param.internalName)")
      bodyLines.append("    \(methodPrefix)ReceivedInvocations.append(\(param.internalName))")
    } else if storableParams.count > 1 {
      let tupleVal = "(" + storableParams.map(\.internalName).joined(separator: ", ") + ")"
      bodyLines.append("    \(methodPrefix)ReceivedArguments = \(tupleVal)")
      bodyLines.append("    \(methodPrefix)ReceivedInvocations.append(\(tupleVal))")
    }

    let callParams = method.parameters.filter { spyStorageType(for: $0, method: method) != nil }

    if callParams.isEmpty {
      callCases.append("    case \(method.name)")
      bodyLines.append("    calls.append(.\(method.name))")
    } else {
      let caseParams = callParams
        .compactMap { param -> String? in
          guard let storageType = spyStorageType(for: param, method: method) else { return nil }
          return "\(param.internalName): \(storageType)"
        }
        .joined(separator: ", ")
      callCases.append("    case \(method.name)(\(caseParams))")

      let callArgs = callParams
        .map { "\($0.internalName): \($0.internalName)" }
        .joined(separator: ", ")
      bodyLines.append("    calls.append(.\(method.name)(\(callArgs)))")
    }

    return bodyLines
  }

  private func generateSpyImplementationBodyLines(
    method: ProtocolMethodInfo,
    methodPrefix: String,
    implementationName: String?)
    -> [String]
  {
    guard let implementationName else {
      return generateFallbackBodyLines(method: method, methodPrefix: methodPrefix, style: .explicitReturn)
    }

    let implArgs = implementationInvocationArguments(for: method)

    guard method.returnType != nil || method.isAsync || method.isThrowing else {
      return ["    \(implementationName)?(\(implArgs))"]
    }

    let tryAwait = [
      method.isThrowing ? "try " : "",
      method.isAsync ? "await " : ""
    ].joined()

    var bodyLines: [String] = []
    bodyLines.append("    if let \(implementationName) {")
    if method.returnType != nil {
      bodyLines.append("      return \(tryAwait)\(implementationName)(\(implArgs))")
    } else {
      bodyLines.append("      \(tryAwait)\(implementationName)(\(implArgs))")
      bodyLines.append("      return")
    }
    bodyLines.append("    }")
    bodyLines.append(contentsOf: generateFallbackBodyLines(method: method, methodPrefix: methodPrefix, style: .explicitReturn))
    return bodyLines
  }
}
