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
    _ node: AttributeSyntax,
    declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: TestDoubleDiagnostic.notAProtocol(macroName: kind.macroName)))
      return []
    }

    guard let traits = TestDoubleTraits.parse(from: node, macroName: kind.macroName, in: context) else {
      return []
    }

    let protocolName = protocolDecl.name.trimmedDescription
    let analysis = ProtocolAnalysis(protocolDecl)

    guard validateProtocolForTestDouble(
      analysis,
      protocolDecl: protocolDecl,
      traits: traits,
      macroName: kind.macroName,
      context: context)
    else {
      return []
    }

    let typeName = "\(kind.generatedTypePrefix)\(protocolName)"
    let namePlan = TestDoubleNamePlan(
      kind: kind,
      analysis: analysis,
      isSendable: traits.isSendable)
    if traits.isSendable {
      return try SendableTestDoubleGenerator(kind: kind).expand(
        protocolDecl,
        analysis: analysis,
        typeName: typeName,
        names: namePlan,
        in: context)
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
    namePlan.diagnose(
      protocolDecl: protocolDecl,
      macroName: kind.macroName,
      context: context)

    var members = generatePropertyDeclarations(properties, access: access)

    switch kind {
    case .stub:
      members.append(contentsOf: generateStubMethodMembers(
        methods,
        names: namePlan.methods,
        access: access))
    case .spy:
      members.append(contentsOf: generateSpyMethodMembers(
        methods,
        names: namePlan.methods,
        callTypeName: namePlan.callType,
        callLogName: namePlan.callLog,
        access: access))
    }

    // Public classes need an explicit init (the synthesized default init is internal).
    if access == "public" {
      members.append("  public init() {}")
    }

    let body = members.joined(separator: "\n")
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
    names: [TestDoubleMethodNamePlan],
    access: String)
    -> [String]
  {
    var members: [String] = []

    for (method, methodNames) in zip(methods, names) {
      members.append(contentsOf: generateReturnStorage(
        method: method,
        storageName: methodNames.returnStorage,
        access: access))

      let sig = buildMethodSignature(method, access: access)
      let bodyLines = generateFallbackBodyLines(
        method: method,
        returnStorageName: methodNames.returnStorage,
        style: .expression)

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
    names: [TestDoubleMethodNamePlan],
    callTypeName: String?,
    callLogName: String?,
    access: String)
    -> [String]
  {
    let prefix = access.isEmpty ? "" : "\(access) "
    var members: [String] = []
    // Each method generates ~6-8 member lines + 1 Call case; reserve to avoid reallocations.
    members.reserveCapacity(methods.count * 8 + (methods.isEmpty ? 0 : 3))

    var callCases: [String] = []
    callCases.reserveCapacity(methods.count)

    for (method, methodNames) in zip(methods, names) {
      let methodPrefix = methodNames.prefix
      let callCountName = methodNames.callCount ?? "\(methodPrefix)CallCount"

      members.append("  // -- \(methodPrefix) --")
      members.append("  \(prefix)var \(callCountName) = 0")

      let receivedParams = method.parameters.filter { !$0.isInout }
      let storableParams = receivedParams.filter { spyStorageType(for: $0, method: method) != nil }
      members.append(contentsOf: generateReceivedArgumentStorage(
        method: method,
        names: methodNames,
        storableParams: storableParams,
        access: access))

      members.append(contentsOf: generateReturnStorage(
        method: method,
        storageName: methodNames.returnStorage,
        access: access))
      if let implementationName = methodNames.implementation {
        members.append(contentsOf: generateImplementationStorage(
          method: method,
          implementationName: implementationName,
          access: access))
      }

      let sig = buildMethodSignature(method, access: access)
      var bodyLines = generateSpyRecordingBodyLines(
        method: method,
        names: methodNames,
        storableParams: storableParams,
        callLogName: callLogName,
        callCases: &callCases)

      bodyLines.append(contentsOf: generateSpyImplementationBodyLines(
        method: method,
        returnStorageName: methodNames.returnStorage,
        implementationName: methodNames.implementation))

      let body = bodyLines.joined(separator: "\n")
      members.append("  \(sig) {")
      members.append(body)
      members.append("  }")
    }

    if !methods.isEmpty,
       let callTypeName,
       let callLogName
    {
      members.append("  \(prefix)enum \(callTypeName) {")
      for callCase in callCases {
        members.append(callCase)
      }
      members.append("  }")
      members.append("  \(prefix)var \(callLogName): [\(callTypeName)] = []")
    }

    return members
  }

  private func generateReceivedArgumentStorage(
    method: ProtocolMethodInfo,
    names: TestDoubleMethodNamePlan,
    storableParams: [ParameterInfo],
    access: String)
    -> [String]
  {
    let prefix = access.isEmpty ? "" : "\(access) "

    if storableParams.count == 1 {
      let param = storableParams[0]
      guard let strippedType = spyStorageType(for: param, method: method) else { return [] }
      // Wrap function types in parens so ? applies to the whole function, not just the return type.
      let wrappedType = isFunctionType(strippedType) ? "(\(strippedType))" : strippedType
      let fnIgnored = isFunctionType(strippedType) ? "  @ObservationIgnored\n" : ""
      guard let receivedArgument = names.receivedArgument,
            let receivedInvocations = names.receivedInvocations
      else {
        return []
      }
      return [
        "\(fnIgnored)  \(prefix)var \(receivedArgument): \(wrappedType)?",
        "\(fnIgnored)  \(prefix)var \(receivedInvocations): [\(wrappedType)] = []"
      ]
    }

    if storableParams.count > 1 {
      let innerTypes = storableParams.compactMap { spyStorageType(for: $0, method: method) }
      let anyFn = innerTypes.contains(where: isFunctionType)
      let tupleType = "(" + zip(storableParams, innerTypes).map { "\($0.0.internalName): \($0.1)" }.joined(separator: ", ") + ")"
      let wrappedType = anyFn ? "(\(tupleType))" : tupleType
      let fnIgnored = anyFn ? "  @ObservationIgnored\n" : ""
      guard let receivedArguments = names.receivedArguments,
            let receivedInvocations = names.receivedInvocations
      else {
        return []
      }
      return [
        "\(fnIgnored)  \(prefix)var \(receivedArguments): \(wrappedType)?",
        "\(fnIgnored)  \(prefix)var \(receivedInvocations): [\(wrappedType)] = []"
      ]
    }

    return []
  }

  private func generateSpyRecordingBodyLines(
    method: ProtocolMethodInfo,
    names: TestDoubleMethodNamePlan,
    storableParams: [ParameterInfo],
    callLogName: String?,
    callCases: inout [String])
    -> [String]
  {
    let methodPrefix = names.prefix
    let callCountName = names.callCount ?? "\(methodPrefix)CallCount"
    let callCaseName = names.callCase ?? method.name
    let callLogName = callLogName ?? "calls"
    var bodyLines: [String] = []
    bodyLines.append("    \(callCountName) += 1")

    if storableParams.count == 1 {
      let param = storableParams[0]
      if let receivedArgument = names.receivedArgument,
         let receivedInvocations = names.receivedInvocations
      {
        bodyLines.append("    \(receivedArgument) = \(param.internalName)")
        bodyLines.append("    \(receivedInvocations).append(\(param.internalName))")
      }
    } else if storableParams.count > 1 {
      let tupleVal = "(" + storableParams.map(\.internalName).joined(separator: ", ") + ")"
      if let receivedArguments = names.receivedArguments,
         let receivedInvocations = names.receivedInvocations
      {
        bodyLines.append("    \(receivedArguments) = \(tupleVal)")
        bodyLines.append("    \(receivedInvocations).append(\(tupleVal))")
      }
    }

    let callParams = method.parameters.filter { spyStorageType(for: $0, method: method) != nil }

    if callParams.isEmpty {
      callCases.append("    case \(callCaseName)")
      bodyLines.append("    \(callLogName).append(.\(callCaseName))")
    } else {
      let caseParams = callParams
        .compactMap { param -> String? in
          guard let storageType = spyStorageType(for: param, method: method) else { return nil }
          return "\(param.internalName): \(storageType)"
        }
        .joined(separator: ", ")
      callCases.append("    case \(callCaseName)(\(caseParams))")

      let callArgs = callParams
        .map { "\($0.internalName): \($0.internalName)" }
        .joined(separator: ", ")
      bodyLines.append("    \(callLogName).append(.\(callCaseName)(\(callArgs)))")
    }

    return bodyLines
  }

  private func generateSpyImplementationBodyLines(
    method: ProtocolMethodInfo,
    returnStorageName: String?,
    implementationName: String?)
    -> [String]
  {
    guard let implementationName else {
      return generateFallbackBodyLines(
        method: method,
        returnStorageName: returnStorageName,
        style: .explicitReturn)
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
    bodyLines.append(contentsOf: generateFallbackBodyLines(
      method: method,
      returnStorageName: returnStorageName,
      style: .explicitReturn))
    return bodyLines
  }
}
