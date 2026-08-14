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
    typeName: String,
    names: TestDoubleNamePlan,
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
    names.diagnose(
      protocolDecl: protocolDecl,
      macroName: kind.macroName,
      context: context)

    let protocolName = protocolDecl.name.trimmedDescription
    let access = accessLevel(of: protocolDecl)
    let prefix = access.isEmpty ? "" : "\(access) "
    let methods = analysis.methods
    let storageTypeName = names.storageType ?? "_Storage"
    let storageName = names.storage ?? "_testDoubleStorage"

    var storedProperties = analysis.properties.map(sendableProtocolProperty)
    var callCases: [String] = []

    for (method, methodNames) in zip(methods, names.methods)
    {
      switch kind {
      case .stub:
        if let returnProperty = sendableReturnProperty(
          method: method,
          storageName: methodNames.returnStorage)
        {
          storedProperties.append(returnProperty)
        }

      case .spy:
        storedProperties.append(SendableStoredProperty(
          name: methodNames.callCount ?? "\(methodNames.prefix)CallCount",
          exposedType: "Int",
          storageType: "Int",
          defaultExpression: "0",
          isObservationIgnored: false))
        storedProperties.append(contentsOf: sendableReceivedProperties(
          method: method,
          names: methodNames))
        if let returnProperty = sendableReturnProperty(
          method: method,
          storageName: methodNames.returnStorage)
        {
          storedProperties.append(returnProperty)
        }
        if let implementationName = methodNames.implementation {
          storedProperties.append(SendableStoredProperty(
            name: implementationName,
            exposedType: sendableImplementationClosureType(for: method),
            storageType: sendableImplementationClosureType(for: method),
            defaultExpression: "nil",
            isObservationIgnored: true))
        }
        callCases.append(sendableCallCase(
          for: method,
          caseName: methodNames.callCase ?? method.name))
      }
    }

    if kind == .spy, !methods.isEmpty,
       let callLogName = names.callLog,
       let callTypeName = names.callType
    {
      storedProperties.append(SendableStoredProperty(
        name: callLogName,
        exposedType: "[\(callTypeName)]",
        storageType: "[\(callTypeName)]",
        defaultExpression: "[]",
        isObservationIgnored: false))
    }

    var members = generateStorageMembers(
      storedProperties,
      storageTypeName: storageTypeName,
      storageName: storageName)
    members.append(contentsOf: storedProperties.flatMap {
      generateComputedProperty($0, access: access, storageName: storageName)
    })

    switch kind {
    case .stub:
      members.append(contentsOf: generateStubMethods(
        methods,
        names: names.methods,
        storageName: storageName,
        access: access))
    case .spy:
      members.append(contentsOf: generateSpyMethods(
        methods,
        names: names.methods,
        callLogName: names.callLog ?? "calls",
        storageName: storageName,
        access: access))
      if !methods.isEmpty, let callTypeName = names.callType {
        members.append("  \(prefix)enum \(callTypeName): Sendable {")
        members.append(contentsOf: callCases.map { "    \($0)" })
        members.append("  }")
      }
    }

    if access == "public" || access == "package" {
      members.append("  \(access) init() {}")
    }

    let body = members.joined(separator: "\n")
    let result: DeclSyntax = """
      @Observable
      nonisolated \(raw: prefix)final class \(raw: typeName): \(raw: protocolName), Sendable {
      \(raw: body)
      }
      """
    return [result]
  }

  // MARK: Storage

  private func generateStorageMembers(
    _ properties: [SendableStoredProperty],
    storageTypeName: String,
    storageName: String)
    -> [String]
  {
    var members = ["  private struct \(storageTypeName): Sendable {"]
    members.append(contentsOf: properties.map {
      "    var \($0.name): \($0.storageType) = \($0.defaultExpression)"
    })
    members.append("  }")
    members.append("  @ObservationIgnored")
    members.append(
      "  private let \(storageName) = VISORTestDoubles._TestDoubleStorage(\(storageTypeName)())")
    return members
  }

  private func generateComputedProperty(
    _ property: SendableStoredProperty,
    access: String,
    storageName: String)
    -> [String]
  {
    let prefix = access.isEmpty ? "" : "\(access) "
    var lines = ["  \(prefix)var \(property.name): \(property.exposedType) {"]
    lines.append("    get {")
    if !property.isObservationIgnored {
      lines.append("      access(keyPath: \\.\(property.name))")
    }
    lines.append("      return \(storageName).withValue { $0.\(property.name) }")
    lines.append("    }")
    lines.append("    set {")
    if property.isObservationIgnored {
      lines.append("      \(storageName).withValue { $0.\(property.name) = newValue }")
    } else {
      lines.append("      withMutation(keyPath: \\.\(property.name)) {")
      lines.append("        \(storageName).withValue { $0.\(property.name) = newValue }")
      lines.append("      }")
    }
    lines.append("    }")
    lines.append("  }")
    return lines
  }

  // MARK: Stub Methods

  private func generateStubMethods(
    _ methods: [ProtocolMethodInfo],
    names: [TestDoubleMethodNamePlan],
    storageName: String,
    access: String)
    -> [String]
  {
    var members: [String] = []
    for (method, methodNames) in zip(methods, names) {
      if method.isConcurrent {
        members.append("  @concurrent")
      }
      members.append("  \(buildMethodSignature(method, access: access)) {")
      if let returnProperty = sendableReturnProperty(
        method: method,
        storageName: methodNames.returnStorage)
      {
        members.append(
          "    let \(returnProperty.name) = \(storageName).withValue { $0.\(returnProperty.name) }")
      }
      members.append(contentsOf: generateFallbackBodyLines(
        method: method,
        returnStorageName: methodNames.returnStorage,
        style: .explicitReturn))
      members.append("  }")
    }
    return members
  }

  // MARK: Spy Methods

  private func generateSpyMethods(
    _ methods: [ProtocolMethodInfo],
    names: [TestDoubleMethodNamePlan],
    callLogName: String,
    storageName: String,
    access: String)
    -> [String]
  {
    var members: [String] = []
    for (method, methodNames) in zip(methods, names)
    {
      if method.isConcurrent {
        members.append("  @concurrent")
      }
      members.append("  \(buildMethodSignature(method, access: access)) {")
      members.append(contentsOf: generateStorageSnapshots(for: method))
      members.append(contentsOf: generateAtomicRecording(
        method: method,
        names: methodNames,
        callLogName: callLogName,
        storageName: storageName))
      members.append(contentsOf: generateImplementationBody(
        method: method,
        returnStorageName: methodNames.returnStorage,
        implementationName: methodNames.implementation))
      members.append("  }")
    }
    return members
  }

  private func generateAtomicRecording(
    method: ProtocolMethodInfo,
    names: TestDoubleMethodNamePlan,
    callLogName: String,
    storageName: String)
    -> [String]
  {
    let receivedParams = method.parameters.filter { !$0.isInout }
    let storableParams = receivedParams.filter {
      sendableSpyStorageType(for: $0, method: method) != nil
    }
    let callParams = method.parameters.filter {
      sendableSpyStorageType(for: $0, method: method) != nil
    }

    let methodPrefix = names.prefix
    let callCountName = names.callCount ?? "\(methodPrefix)CallCount"
    var mutationNames = [callCountName]
    if storableParams.count == 1 {
      if let receivedArgument = names.receivedArgument {
        mutationNames.append(receivedArgument)
      }
      if let receivedInvocations = names.receivedInvocations {
        mutationNames.append(receivedInvocations)
      }
    } else if storableParams.count > 1 {
      if let receivedArguments = names.receivedArguments {
        mutationNames.append(receivedArguments)
      }
      if let receivedInvocations = names.receivedInvocations {
        mutationNames.append(receivedInvocations)
      }
    }
    mutationNames.append(callLogName)

    var snapshotNames: [String] = []
    if let implementationName = names.implementation {
      snapshotNames.append(implementationName)
    }
    if let returnProperty = sendableReturnProperty(
      method: method,
      storageName: names.returnStorage)
    {
      snapshotNames.append(returnProperty.name)
    }

    var storageBody = ["state.\(callCountName) += 1"]
    if storableParams.count == 1 {
      let param = storableParams[0]
      let value = storageValueExpression(for: param)
      if let receivedArgument = names.receivedArgument {
        storageBody.append("state.\(receivedArgument) = \(value)")
      }
      if let receivedInvocations = names.receivedInvocations {
        storageBody.append("state.\(receivedInvocations).append(\(value))")
      }
    } else if storableParams.count > 1 {
      let tuple = "(" + storableParams.map(storageValueExpression).joined(separator: ", ") + ")"
      if let receivedArguments = names.receivedArguments {
        storageBody.append("state.\(receivedArguments) = \(tuple)")
      }
      if let receivedInvocations = names.receivedInvocations {
        storageBody.append("state.\(receivedInvocations).append(\(tuple))")
      }
    }

    let callCaseName = names.callCase ?? method.name
    if callParams.isEmpty {
      storageBody.append("state.\(callLogName).append(.\(callCaseName))")
    } else {
      let arguments = callParams.map { param in
        let value = storageValueExpression(for: param)
        return "\(param.internalName): \(value)"
      }.joined(separator: ", ")
      storageBody.append("state.\(callLogName).append(.\(callCaseName)(\(arguments)))")
    }

    return wrapAtomicRecording(
      mutationNames: mutationNames,
      snapshotNames: snapshotNames,
      storageBody: storageBody,
      storageName: storageName)
  }

  private func wrapAtomicRecording(
    mutationNames: [String],
    snapshotNames: [String],
    storageBody: [String],
    storageName: String)
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
    lines.append("\(indent)\(storageName).withValue { state in")
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
      returnStorageName: returnStorageName,
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
    storageName: String?)
    -> SendableStoredProperty?
  {
    guard let storageName else { return nil }
    guard !method.isRethrowing else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.returnType) else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.throwsEffect.explicitErrorType) else {
      return nil
    }

    if method.isThrowing {
      guard let failureType = method.throwsEffect.resultFailureType else { return nil }
      if let rawReturnType = method.returnType {
        let returnType = storageValueType(from: rawReturnType)
        let resultType = "Result<\(returnType), \(failureType)>"
        if let initialValue = returnDefaultValue(for: method) {
          return SendableStoredProperty(
            name: storageName,
            exposedType: resultType,
            storageType: resultType,
            defaultExpression: ".success(\(initialValue))",
            isObservationIgnored: false)
        }
        return SendableStoredProperty(
          name: storageName,
          exposedType: "\(resultType)?",
          storageType: "\(resultType)?",
          defaultExpression: "nil",
          isObservationIgnored: false)
      }

      let resultType = "Result<Void, \(failureType)>"
      return SendableStoredProperty(
        name: storageName,
        exposedType: resultType,
        storageType: resultType,
        defaultExpression: ".success(())",
        isObservationIgnored: false)
    }

    guard let rawReturnType = method.returnType else { return nil }
    let returnType = storageValueType(from: rawReturnType)
    if let initialValue = returnDefaultValue(for: method) {
      return SendableStoredProperty(
        name: storageName,
        exposedType: returnType,
        storageType: returnType,
        defaultExpression: initialValue,
        isObservationIgnored: isFunctionType(returnType))
    }
    return SendableStoredProperty(
      name: storageName,
      exposedType: "\(returnType)?",
      storageType: "\(returnType)?",
      defaultExpression: "nil",
      isObservationIgnored: isFunctionType(returnType))
  }

  private func sendableReceivedProperties(
    method: ProtocolMethodInfo,
    names: TestDoubleMethodNamePlan)
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
      guard let receivedArgument = names.receivedArgument,
            let receivedInvocations = names.receivedInvocations
      else {
        return []
      }
      return [
        SendableStoredProperty(
          name: receivedArgument,
          exposedType: "\(wrappedType)?",
          storageType: "\(wrappedType)?",
          defaultExpression: "nil",
          isObservationIgnored: ignored),
        SendableStoredProperty(
          name: receivedInvocations,
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
      guard let receivedArguments = names.receivedArguments,
            let receivedInvocations = names.receivedInvocations
      else {
        return []
      }
      return [
        SendableStoredProperty(
          name: receivedArguments,
          exposedType: "\(wrappedType)?",
          storageType: "\(wrappedType)?",
          defaultExpression: "nil",
          isObservationIgnored: containsFunction),
        SendableStoredProperty(
          name: receivedInvocations,
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

  private func sendableCallCase(
    for method: ProtocolMethodInfo,
    caseName: String)
    -> String
  {
    let parameters = method.parameters.compactMap { parameter -> String? in
      guard let type = sendableSpyStorageType(for: parameter, method: method) else { return nil }
      return "\(parameter.internalName): \(type)"
    }
    guard !parameters.isEmpty else { return "case \(caseName)" }
    return "case \(caseName)(\(parameters.joined(separator: ", ")))"
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
