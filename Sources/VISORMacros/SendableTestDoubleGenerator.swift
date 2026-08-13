//
//  SendableTestDoubleGenerator.swift
//  VISOR
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - SendableStoredProperty

private struct SendableStoredProperty {
  let name: String
  let exposedType: String
  let storageType: String
  let defaultExpression: String
  let isObservationIgnored: Bool
}

// MARK: - SendableTestDoubleGenerator

struct SendableTestDoubleGenerator {
  let kind: TestDoubleKind

  func expand(
    _ protocolDecl: ProtocolDeclSyntax,
    analysis: ProtocolAnalysis,
    in context: some MacroExpansionContext)
    throws -> [DeclSyntax]
  {
    if kind == .spy,
       let unsupportedMethod = analysis.methods.lazy.compactMap({ method -> (ProtocolMethodInfo, [String])? in
         let genericNames = unconstrainedGenericParameterNamesRequiringStorage(in: method)
         return genericNames.isEmpty ? nil : (method, genericNames)
       }).first
    {
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.sendableSpyUnconstrainedGenericValues(
          methodName: unsupportedMethod.0.name,
          genericNames: unsupportedMethod.1)))
      return []
    }

    if hasUnknownTypeDefaults(properties: analysis.properties, methods: analysis.methods) {
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.unknownTypeDefaults(macroName: kind.macroName)))
    }

    let protocolName = protocolDecl.name.trimmedDescription
    let access = accessLevel(of: protocolDecl)
    let prefix = access.isEmpty ? "" : "\(access) "
    let methods = analysis.methods
    let methodPrefixes = uniqueMethodPrefixes(for: methods)
    let implementationNames = implementationStorageNames(
      for: methods,
      methodPrefixes: methodPrefixes,
      properties: analysis.properties)

    var storedProperties = analysis.properties.map(sendableProtocolProperty)
    var callCases: [String] = []

    for ((method, methodPrefix), implementationName) in
      zip(zip(methods, methodPrefixes), implementationNames)
    {
      switch kind {
      case .stub:
        if let returnProperty = sendableReturnProperty(method: method, methodPrefix: methodPrefix) {
          storedProperties.append(returnProperty)
        }

      case .spy:
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

        storedProperties.append(SendableStoredProperty(
          name: "\(methodPrefix)CallCount",
          exposedType: "Int",
          storageType: "Int",
          defaultExpression: "0",
          isObservationIgnored: false))
        storedProperties.append(contentsOf: sendableReceivedProperties(
          method: method,
          methodPrefix: methodPrefix))
        if let returnProperty = sendableReturnProperty(method: method, methodPrefix: methodPrefix) {
          storedProperties.append(returnProperty)
        }
        if supportsImplementation {
          storedProperties.append(SendableStoredProperty(
            name: implementationName,
            exposedType: sendableImplementationClosureType(for: method),
            storageType: sendableImplementationClosureType(for: method),
            defaultExpression: "nil",
            isObservationIgnored: true))
        }
        callCases.append(sendableCallCase(for: method))
      }
    }

    if kind == .spy, !methods.isEmpty {
      storedProperties.append(SendableStoredProperty(
        name: "calls",
        exposedType: "[Call]",
        storageType: "[Call]",
        defaultExpression: "[]",
        isObservationIgnored: false))
    }

    var members = generateStorageMembers(storedProperties)
    members.append(contentsOf: storedProperties.flatMap { generateComputedProperty($0, access: access) })

    switch kind {
    case .stub:
      members.append(contentsOf: generateStubMethods(
        methods,
        methodPrefixes: methodPrefixes,
        access: access))
    case .spy:
      members.append(contentsOf: generateSpyMethods(
        methods,
        methodPrefixes: methodPrefixes,
        implementationNames: implementationNames,
        access: access))
      if !methods.isEmpty {
        members.append("  \(prefix)enum Call: Sendable {")
        members.append(contentsOf: callCases.map { "    \($0)" })
        members.append("  }")
      }
    }

    if access == "public" || access == "package" {
      members.append("  \(access) init() {}")
    }

    let body = members.joined(separator: "\n")
    let typeName = "\(kind.generatedTypePrefix)\(protocolName)"
    let result: DeclSyntax = """
      @Observable
      nonisolated \(raw: prefix)final class \(raw: typeName): \(raw: protocolName), Sendable {
      \(raw: body)
      }
      """
    return [result]
  }

  // MARK: Storage

  private func generateStorageMembers(_ properties: [SendableStoredProperty]) -> [String] {
    var members = ["  private struct _Storage: Sendable {"]
    members.append(contentsOf: properties.map {
      "    var \($0.name): \($0.storageType) = \($0.defaultExpression)"
    })
    members.append("  }")
    members.append("  @ObservationIgnored")
    members.append(
      "  private let _testDoubleStorage = VISORTestDoubles._TestDoubleStorage(_Storage())")
    return members
  }

  private func generateComputedProperty(
    _ property: SendableStoredProperty,
    access: String)
    -> [String]
  {
    let prefix = access.isEmpty ? "" : "\(access) "
    var lines = ["  \(prefix)var \(property.name): \(property.exposedType) {"]
    lines.append("    get {")
    if !property.isObservationIgnored {
      lines.append("      access(keyPath: \\.\(property.name))")
    }
    lines.append("      return _testDoubleStorage.withValue { $0.\(property.name) }")
    lines.append("    }")
    lines.append("    set {")
    if property.isObservationIgnored {
      lines.append("      _testDoubleStorage.withValue { $0.\(property.name) = newValue }")
    } else {
      lines.append("      withMutation(keyPath: \\.\(property.name)) {")
      lines.append("        _testDoubleStorage.withValue { $0.\(property.name) = newValue }")
      lines.append("      }")
    }
    lines.append("    }")
    lines.append("  }")
    return lines
  }

  // MARK: Stub Methods

  private func generateStubMethods(
    _ methods: [ProtocolMethodInfo],
    methodPrefixes: [String],
    access: String)
    -> [String]
  {
    var members: [String] = []
    for (method, methodPrefix) in zip(methods, methodPrefixes) {
      if method.isConcurrent {
        members.append("  @concurrent")
      }
      members.append("  \(buildMethodSignature(method, access: access)) {")
      if let returnProperty = sendableReturnProperty(method: method, methodPrefix: methodPrefix) {
        members.append(
          "    let \(returnProperty.name) = _testDoubleStorage.withValue { $0.\(returnProperty.name) }")
      }
      members.append(contentsOf: generateFallbackBodyLines(
        method: method,
        methodPrefix: methodPrefix,
        style: .explicitReturn))
      members.append("  }")
    }
    return members
  }

  // MARK: Spy Methods

  private func generateSpyMethods(
    _ methods: [ProtocolMethodInfo],
    methodPrefixes: [String],
    implementationNames: [String],
    access: String)
    -> [String]
  {
    var members: [String] = []
    for ((method, methodPrefix), implementationName) in
      zip(zip(methods, methodPrefixes), implementationNames)
    {
      if method.isConcurrent {
        members.append("  @concurrent")
      }
      members.append("  \(buildMethodSignature(method, access: access)) {")
      members.append(contentsOf: generateStorageSnapshots(for: method))
      members.append(contentsOf: generateAtomicRecording(
        method: method,
        methodPrefix: methodPrefix,
        implementationName: supportsImplementationClosure(for: method) ? implementationName : nil))
      members.append(contentsOf: generateImplementationBody(
        method: method,
        methodPrefix: methodPrefix,
        implementationName: supportsImplementationClosure(for: method) ? implementationName : nil))
      members.append("  }")
    }
    return members
  }

  private func generateAtomicRecording(
    method: ProtocolMethodInfo,
    methodPrefix: String,
    implementationName: String?)
    -> [String]
  {
    let receivedParams = method.parameters.filter { !$0.isInout }
    let storableParams = receivedParams.filter {
      sendableSpyStorageType(for: $0, method: method) != nil
    }
    let callParams = method.parameters.filter {
      sendableSpyStorageType(for: $0, method: method) != nil
    }

    var mutationNames = ["\(methodPrefix)CallCount"]
    if storableParams.count == 1 {
      let capName = storableParams[0].internalName.capitalisedFirst
      mutationNames.append("\(methodPrefix)Received\(capName)")
      mutationNames.append("\(methodPrefix)ReceivedInvocations")
    } else if storableParams.count > 1 {
      mutationNames.append("\(methodPrefix)ReceivedArguments")
      mutationNames.append("\(methodPrefix)ReceivedInvocations")
    }
    mutationNames.append("calls")

    var snapshotNames: [String] = []
    if let implementationName {
      snapshotNames.append(implementationName)
    }
    if let returnProperty = sendableReturnProperty(method: method, methodPrefix: methodPrefix) {
      snapshotNames.append(returnProperty.name)
    }

    var storageBody = ["state.\(methodPrefix)CallCount += 1"]
    if storableParams.count == 1 {
      let param = storableParams[0]
      let capName = param.internalName.capitalisedFirst
      let value = storageValueExpression(for: param)
      storageBody.append("state.\(methodPrefix)Received\(capName) = \(value)")
      storageBody.append("state.\(methodPrefix)ReceivedInvocations.append(\(value))")
    } else if storableParams.count > 1 {
      let tuple = "(" + storableParams.map(storageValueExpression).joined(separator: ", ") + ")"
      storageBody.append("state.\(methodPrefix)ReceivedArguments = \(tuple)")
      storageBody.append("state.\(methodPrefix)ReceivedInvocations.append(\(tuple))")
    }

    if callParams.isEmpty {
      storageBody.append("state.calls.append(.\(method.name))")
    } else {
      let arguments = callParams.map { param in
        let value = storageValueExpression(for: param)
        return "\(param.internalName): \(value)"
      }.joined(separator: ", ")
      storageBody.append("state.calls.append(.\(method.name)(\(arguments)))")
    }

    return wrapAtomicRecording(
      mutationNames: mutationNames,
      snapshotNames: snapshotNames,
      storageBody: storageBody)
  }

  private func wrapAtomicRecording(
    mutationNames: [String],
    snapshotNames: [String],
    storageBody: [String])
    -> [String]
  {
    let binding: String
    switch snapshotNames.count {
    case 0:
      binding = ""
    case 1:
      binding = "let \(snapshotNames[0]) = "
    default:
      binding = "let (\(snapshotNames.joined(separator: ", "))) = "
    }

    var lines: [String] = []
    var indent = "    "
    for (index, name) in mutationNames.enumerated() {
      let assignment = index == 0 ? binding : ""
      lines.append("\(indent)\(assignment)withMutation(keyPath: \\.\(name)) {")
      indent += "  "
    }
    lines.append("\(indent)_testDoubleStorage.withValue { state in")
    indent += "  "
    lines.append(contentsOf: storageBody.map { "\(indent)\($0)" })
    if snapshotNames.count == 1 {
      lines.append("\(indent)return state.\(snapshotNames[0])")
    } else if snapshotNames.count > 1 {
      let values = snapshotNames.map { "state.\($0)" }.joined(separator: ", ")
      lines.append("\(indent)return (\(values))")
    }
    indent.removeLast(2)
    lines.append("\(indent)}")
    for _ in mutationNames.reversed() {
      indent.removeLast(2)
      lines.append("\(indent)}")
    }
    return lines
  }

  private func generateImplementationBody(
    method: ProtocolMethodInfo,
    methodPrefix: String,
    implementationName: String?)
    -> [String]
  {
    guard let implementationName else {
      return generateFallbackBodyLines(
        method: method,
        methodPrefix: methodPrefix,
        style: .explicitReturn)
    }

    let invocationArguments = sendableImplementationInvocationArguments(for: method)
    guard method.returnType != nil || method.isAsync || method.isThrowing else {
      return ["    \(implementationName)?(\(invocationArguments))"]
    }

    let tryAwait = [
      method.isThrowing ? "try " : "",
      method.isAsync ? "await " : "",
    ].joined()

    var lines = ["    if let \(implementationName) {"]
    if method.returnType != nil {
      lines.append("      return \(tryAwait)\(implementationName)(\(invocationArguments))")
    } else {
      lines.append("      \(tryAwait)\(implementationName)(\(invocationArguments))")
      lines.append("      return")
    }
    lines.append("    }")
    lines.append(contentsOf: generateFallbackBodyLines(
      method: method,
      methodPrefix: methodPrefix,
      style: .explicitReturn))
    return lines
  }

  private func generateStorageSnapshots(for method: ProtocolMethodInfo) -> [String] {
    method.parameters.compactMap { parameter in
      guard sendableSpyStorageType(for: parameter, method: method) != nil
      else {
        return nil
      }
      if parameter.isInout {
        return "    let \(storageSnapshotName(for: parameter)) = \(parameter.internalName)"
      }
      switch storageSnapshotStrategy(for: parameter.type) {
      case .copy:
        return "    let \(storageSnapshotName(for: parameter)) = copy \(parameter.internalName)"
      case .consume:
        return "    let \(storageSnapshotName(for: parameter)) = consume \(parameter.internalName)"
      case .none:
        return nil
      }
    }
  }

  private func storageSnapshotName(for parameter: ParameterInfo) -> String {
    "_visor\(parameter.internalName.capitalisedFirst)Snapshot"
  }

  private func storageValueExpression(for parameter: ParameterInfo) -> String {
    if parameter.isInout || storageSnapshotStrategy(for: parameter.type) != .none {
      return storageSnapshotName(for: parameter)
    }
    return parameter.internalName
  }

  private func sendableImplementationInvocationArguments(
    for method: ProtocolMethodInfo)
    -> String
  {
    method.parameters.map { parameter in
      if parameter.isInout {
        return "&\(parameter.internalName)"
      }
      if storageSnapshotStrategy(for: parameter.type) == .consume {
        return storageSnapshotName(for: parameter)
      }
      return parameter.internalName
    }.joined(separator: ", ")
  }

  // MARK: Stored Property Models

  private func sendableProtocolProperty(_ property: ProtocolPropertyInfo) -> SendableStoredProperty {
    if let customDefault = property.defaultValueExpression {
      return SendableStoredProperty(
        name: property.name,
        exposedType: property.type,
        storageType: property.type,
        defaultExpression: customDefault,
        isObservationIgnored: isFunctionType(property.type))
    }

    if let knownDefault = defaultValue(for: property.type) {
      return SendableStoredProperty(
        name: property.name,
        exposedType: property.type,
        storageType: property.type,
        defaultExpression: knownDefault,
        isObservationIgnored: isFunctionType(property.type))
    }

    return SendableStoredProperty(
      name: property.name,
      exposedType: "\(property.type)!",
      storageType: "\(property.type)?",
      defaultExpression: "nil",
      isObservationIgnored: isFunctionType(property.type))
  }

  private func sendableReturnProperty(
    method: ProtocolMethodInfo,
    methodPrefix: String)
    -> SendableStoredProperty?
  {
    guard !method.isRethrowing else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.returnType) else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.throwsEffect.explicitErrorType) else {
      return nil
    }

    if method.isThrowing {
      guard let failureType = method.throwsEffect.resultFailureType else { return nil }
      let name = "\(methodPrefix)Result"
      if let rawReturnType = method.returnType {
        let returnType = storageValueType(from: rawReturnType)
        let resultType = "Result<\(returnType), \(failureType)>"
        if let initialValue = returnDefaultValue(for: method) {
          return SendableStoredProperty(
            name: name,
            exposedType: resultType,
            storageType: resultType,
            defaultExpression: ".success(\(initialValue))",
            isObservationIgnored: false)
        }
        return SendableStoredProperty(
          name: name,
          exposedType: "\(resultType)?",
          storageType: "\(resultType)?",
          defaultExpression: "nil",
          isObservationIgnored: false)
      }

      let resultType = "Result<Void, \(failureType)>"
      return SendableStoredProperty(
        name: name,
        exposedType: resultType,
        storageType: resultType,
        defaultExpression: ".success(())",
        isObservationIgnored: false)
    }

    guard let rawReturnType = method.returnType else { return nil }
    let returnType = storageValueType(from: rawReturnType)
    let name = "\(methodPrefix)ReturnValue"
    if let initialValue = returnDefaultValue(for: method) {
      return SendableStoredProperty(
        name: name,
        exposedType: returnType,
        storageType: returnType,
        defaultExpression: initialValue,
        isObservationIgnored: isFunctionType(returnType))
    }
    return SendableStoredProperty(
      name: name,
      exposedType: "\(returnType)?",
      storageType: "\(returnType)?",
      defaultExpression: "nil",
      isObservationIgnored: isFunctionType(returnType))
  }

  private func sendableReceivedProperties(
    method: ProtocolMethodInfo,
    methodPrefix: String)
    -> [SendableStoredProperty]
  {
    let receivedParams = method.parameters.filter { !$0.isInout }
    let storableParams = receivedParams.filter {
      sendableSpyStorageType(for: $0, method: method) != nil
    }

    if storableParams.count == 1 {
      let parameter = storableParams[0]
      guard let type = sendableSpyStorageType(for: parameter, method: method) else { return [] }
      let wrappedType = type.hasPrefix("any ") || isFunctionType(type) ? "(\(type))" : type
      let ignored = isFunctionType(type)
      return [
        SendableStoredProperty(
          name: "\(methodPrefix)Received\(parameter.internalName.capitalisedFirst)",
          exposedType: "\(wrappedType)?",
          storageType: "\(wrappedType)?",
          defaultExpression: "nil",
          isObservationIgnored: ignored),
        SendableStoredProperty(
          name: "\(methodPrefix)ReceivedInvocations",
          exposedType: "[\(wrappedType)]",
          storageType: "[\(wrappedType)]",
          defaultExpression: "[]",
          isObservationIgnored: ignored),
      ]
    }

    if storableParams.count > 1 {
      let types = storableParams.compactMap {
        sendableSpyStorageType(for: $0, method: method)
      }
      let containsFunction = types.contains(where: isFunctionType)
      let tupleType = "(" + zip(storableParams, types).map {
        "\($0.0.internalName): \($0.1)"
      }.joined(separator: ", ") + ")"
      let wrappedType = containsFunction ? "(\(tupleType))" : tupleType
      return [
        SendableStoredProperty(
          name: "\(methodPrefix)ReceivedArguments",
          exposedType: "\(wrappedType)?",
          storageType: "\(wrappedType)?",
          defaultExpression: "nil",
          isObservationIgnored: containsFunction),
        SendableStoredProperty(
          name: "\(methodPrefix)ReceivedInvocations",
          exposedType: "[\(wrappedType)]",
          storageType: "[\(wrappedType)]",
          defaultExpression: "[]",
          isObservationIgnored: containsFunction),
      ]
    }

    return []
  }

  private func sendableImplementationClosureType(for method: ProtocolMethodInfo) -> String {
    let parameters = method.parameters.map { stripEscaping(from: $0.type) }.joined(separator: ", ")
    var effects = ""
    if method.isAsync { effects += " async" }
    if let throwsKeyword = method.throwsEffect.keyword {
      effects += " \(throwsKeyword)"
    }
    return "(@Sendable (\(parameters))\(effects) -> \(method.returnType ?? "Void"))?"
  }

  private func sendableCallCase(for method: ProtocolMethodInfo) -> String {
    let parameters = method.parameters.compactMap { parameter -> String? in
      guard let type = sendableSpyStorageType(for: parameter, method: method) else { return nil }
      return "\(parameter.internalName): \(type)"
    }
    guard !parameters.isEmpty else { return "case \(method.name)" }
    return "case \(method.name)(\(parameters.joined(separator: ", ")))"
  }

  private func unconstrainedGenericParameterNamesRequiringStorage(
    in method: ProtocolMethodInfo)
    -> [String]
  {
    let referencedNames = method.parameters
      .filter { !isNonEscapingFunctionType($0.type) }
      .flatMap { genericParameterNamesReferenced(by: method, in: $0.type) }
    let uniqueNames = Set(referencedNames)
    return method.genericParameterNames.filter {
      uniqueNames.contains($0)
        && !method.explicitlySendableGenericParameterNames.contains($0)
    }
  }

  private func sendableSpyStorageType(
    for parameter: ParameterInfo,
    method: ProtocolMethodInfo)
    -> String?
  {
    let strippedType = storageValueType(from: parameter.type)
    guard !isNonEscapingFunctionType(parameter.type) else { return nil }

    let genericNames = genericParameterNamesReferenced(by: method, in: strippedType)
    guard !genericNames.isEmpty else { return strippedType }
    guard genericNames.allSatisfy(method.explicitlySendableGenericParameterNames.contains) else {
      return nil
    }
    return "any Sendable"
  }
}
