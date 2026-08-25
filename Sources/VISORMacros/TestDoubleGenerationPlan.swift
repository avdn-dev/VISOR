//
//  TestDoubleGenerationPlan.swift
//  VISOR
//

// MARK: - TestDoubleStoredPropertyPlan

struct TestDoubleStoredPropertyPlan {

  // MARK: Lifecycle

  init(
    name: String,
    exposedType: String,
    storageType: String,
    storageDefaultExpression: String,
    ordinaryInitialiser: String?,
    isObservationIgnored: Bool,
    observationState: ProtocolObservationStateInfo? = nil,
    observationChannelName: String? = nil,
  ) {
    self.name = name
    self.exposedType = exposedType
    self.storageType = storageType
    self.storageDefaultExpression = storageDefaultExpression
    self.ordinaryInitialiser = ordinaryInitialiser
    self.isObservationIgnored = isObservationIgnored
    self.observationState = observationState
    self.observationChannelName = observationChannelName
  }

  // MARK: Internal

  let name: String
  let exposedType: String
  let storageType: String
  let storageDefaultExpression: String
  let ordinaryInitialiser: String?
  let isObservationIgnored: Bool
  let observationState: ProtocolObservationStateInfo?
  let observationChannelName: String?

  var isObservationState: Bool {
    observationState != nil
  }

}

// MARK: - TestDoubleRecordedParameterPlan

struct TestDoubleRecordedParameterPlan {
  let parameter: ParameterInfo
  let storageType: String
  let valueExpression: String
  let snapshotDeclaration: String?
}

// MARK: - TestDoubleCallCasePlan

struct TestDoubleCallCasePlan {
  let name: String
  let parameters: [TestDoubleRecordedParameterPlan]

  var declaration: String {
    guard !parameters.isEmpty else { return "case \(name)" }
    let associatedValues = parameters.map {
      "\($0.parameter.internalNameComponent): \($0.storageType)"
    }.joined(separator: ", ")
    return "case \(name)(\(associatedValues))"
  }

  var invocation: String {
    guard !parameters.isEmpty else { return ".\(name)" }
    let arguments = parameters.map {
      "\($0.parameter.internalNameComponent): \($0.valueExpression)"
    }.joined(separator: ", ")
    return ".\(name)(\(arguments))"
  }
}

// MARK: - TestDoubleMethodGenerationPlan

struct TestDoubleMethodGenerationPlan {

  // MARK: Internal

  let method: ProtocolMethodInfo
  let names: TestDoubleMethodNamePlan
  let storedProperties: [TestDoubleStoredPropertyPlan]
  let receivedParameters: [TestDoubleRecordedParameterPlan]
  let returnProperty: TestDoubleStoredPropertyPlan?
  let implementationProperty: TestDoubleStoredPropertyPlan?
  let callCase: TestDoubleCallCasePlan?
  let implementationInvocationArguments: String

  var callCountName: String {
    names.callCount ?? "\(names.prefix)CallCount"
  }

  var storageSnapshotDeclarations: [String] {
    callCase?.parameters.compactMap(\.snapshotDeclaration) ?? []
  }

  var recordingMutationPropertyNames: [String] {
    var propertyNames = [callCountName]
    propertyNames.append(contentsOf: receivedProperties.map(\.name))
    return propertyNames
  }

  var recordingRetirementPropertyName: String? {
    receivedProperties.first { property in
      property.name == names.receivedArgument || property.name == names.receivedArguments
    }?.name
  }

  // MARK: Private

  private var receivedProperties: [TestDoubleStoredPropertyPlan] {
    storedProperties.filter { property in
      property.name == names.receivedArgument
        || property.name == names.receivedArguments
        || property.name == names.receivedInvocations
    }
  }
}

// MARK: - TestDoubleGenerationPlan

struct TestDoubleGenerationPlan {

  // MARK: Lifecycle

  init(
    kind: TestDoubleKind,
    protocolName: String,
    access: String,
    analysis: ProtocolAnalysis,
    names: TestDoubleNamePlan,
    isSendable: Bool,
  ) {
    self.kind = kind
    self.protocolName = protocolName
    typeName = "\(kind.generatedTypePrefix)\(protocolName)"
    self.access = access
    self.isSendable = isSendable
    self.names = names
    protocolProperties = analysis.properties.map { property in
      Self.protocolProperty(
        property,
        observationChannelName: names.observationStateChannels[property.name],
        isSendable: isSendable,
      )
    }
    methods = zip(analysis.methods, names.methods).map { method, methodNames in
      Self.methodPlan(
        method,
        names: methodNames,
        kind: kind,
        isSendable: isSendable,
      )
    }

    if
      kind == .spy, !analysis.methods.isEmpty,
      let callLogName = names.callLog,
      let callTypeName = names.callType
    {
      callLogProperty = TestDoubleStoredPropertyPlan(
        name: callLogName,
        exposedType: "[\(callTypeName)]",
        storageType: "[\(callTypeName)]",
        storageDefaultExpression: "[]",
        ordinaryInitialiser: "[]",
        isObservationIgnored: false,
      )
    } else {
      callLogProperty = nil
    }
  }

  // MARK: Internal

  let kind: TestDoubleKind
  let protocolName: String
  let typeName: String
  let access: String
  let isSendable: Bool
  let names: TestDoubleNamePlan
  let protocolProperties: [TestDoubleStoredPropertyPlan]
  let methods: [TestDoubleMethodGenerationPlan]
  let callLogProperty: TestDoubleStoredPropertyPlan?

  var allStoredProperties: [TestDoubleStoredPropertyPlan] {
    protocolProperties
      + methods.flatMap(\.storedProperties)
      + [callLogProperty].compactMap { $0 }
  }

  var storageTypeName: String {
    names.storageType ?? "_Storage"
  }

  var storageName: String {
    names.storage ?? "_testDoubleStorage"
  }

  // MARK: Private

  private static func methodPlan(
    _ method: ProtocolMethodInfo,
    names: TestDoubleMethodNamePlan,
    kind: TestDoubleKind,
    isSendable: Bool,
  ) -> TestDoubleMethodGenerationPlan {
    let returnProperty = returnProperty(
      method,
      name: names.returnStorage,
      isSendable: isSendable,
    )

    guard kind == .spy else {
      return TestDoubleMethodGenerationPlan(
        method: method,
        names: names,
        storedProperties: [returnProperty].compactMap { $0 },
        receivedParameters: [],
        returnProperty: returnProperty,
        implementationProperty: nil,
        callCase: nil,
        implementationInvocationArguments: "",
      )
    }

    let receivedParameters = method.parameters
      .filter { !$0.isInout }
      .compactMap { recordedParameter($0, method: method, isSendable: isSendable) }
    let callParameters = method.parameters.compactMap {
      recordedParameter($0, method: method, isSendable: isSendable)
    }
    let receivedProperties = receivedProperties(
      for: receivedParameters,
      names: names,
      isSendable: isSendable,
    )
    let implementationProperty = implementationProperty(
      method,
      name: names.implementation,
      isSendable: isSendable,
    )
    let callCase = TestDoubleCallCasePlan(
      name: names.callCase ?? method.name,
      parameters: callParameters,
    )

    let callCountProperty = TestDoubleStoredPropertyPlan(
      name: names.callCount ?? "\(names.prefix)CallCount",
      exposedType: "Int",
      storageType: "Int",
      storageDefaultExpression: "0",
      ordinaryInitialiser: "0",
      isObservationIgnored: false,
    )
    let storedProperties = [callCountProperty]
      + receivedProperties
      + [returnProperty, implementationProperty].compactMap { $0 }

    return TestDoubleMethodGenerationPlan(
      method: method,
      names: names,
      storedProperties: storedProperties,
      receivedParameters: receivedParameters,
      returnProperty: returnProperty,
      implementationProperty: implementationProperty,
      callCase: callCase,
      implementationInvocationArguments: implementationInvocationArguments(
        for: method,
        isSendable: isSendable,
      ),
    )
  }

  private static func protocolProperty(
    _ property: ProtocolPropertyInfo,
    observationChannelName: String?,
    isSendable: Bool,
  ) -> TestDoubleStoredPropertyPlan {
    if let customDefault = property.defaultValueExpression {
      return TestDoubleStoredPropertyPlan(
        name: property.name,
        exposedType: property.type,
        storageType: property.type,
        storageDefaultExpression: customDefault,
        ordinaryInitialiser: customDefault,
        isObservationIgnored: isSendable && isFunctionType(property.type),
        observationState: property.observationState,
        observationChannelName: observationChannelName,
      )
    }

    if let knownDefault = defaultValue(for: property.type) {
      return TestDoubleStoredPropertyPlan(
        name: property.name,
        exposedType: property.type,
        storageType: property.type,
        storageDefaultExpression: knownDefault,
        ordinaryInitialiser: knownDefault,
        isObservationIgnored: isSendable && isFunctionType(property.type),
        observationState: property.observationState,
        observationChannelName: observationChannelName,
      )
    }

    return TestDoubleStoredPropertyPlan(
      name: property.name,
      exposedType: "\(property.type)!",
      storageType: "\(property.type)?",
      storageDefaultExpression: "nil",
      ordinaryInitialiser: "nil",
      isObservationIgnored: isSendable && isFunctionType(property.type),
      observationState: property.observationState,
      observationChannelName: observationChannelName,
    )
  }

  private static func returnProperty(
    _ method: ProtocolMethodInfo,
    name: String?,
    isSendable: Bool,
  ) -> TestDoubleStoredPropertyPlan? {
    guard let name else { return nil }
    guard !method.isRethrowing else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.returnType) else { return nil }
    guard !methodReferencesGenericParameters(method, in: method.throwsEffect.explicitErrorType) else {
      return nil
    }

    if method.isThrowing {
      guard let failureType = method.throwsEffect.resultFailureType else { return nil }
      guard let rawReturnType = method.returnType else {
        return TestDoubleStoredPropertyPlan(
          name: name,
          exposedType: "Result<Void, \(failureType)>",
          storageType: "Result<Void, \(failureType)>",
          storageDefaultExpression: ".success(())",
          ordinaryInitialiser: ".success(())",
          isObservationIgnored: false,
        )
      }

      let returnType = isSendable ? storageValueType(from: rawReturnType) : rawReturnType
      let resultType = "Result<\(returnType), \(failureType)>"
      if let initialValue = returnDefaultValue(for: method) {
        return TestDoubleStoredPropertyPlan(
          name: name,
          exposedType: resultType,
          storageType: resultType,
          storageDefaultExpression: ".success(\(initialValue))",
          ordinaryInitialiser: ".success(\(initialValue))",
          isObservationIgnored: false,
        )
      }
      return TestDoubleStoredPropertyPlan(
        name: name,
        exposedType: "\(resultType)?",
        storageType: "\(resultType)?",
        storageDefaultExpression: "nil",
        ordinaryInitialiser: nil,
        isObservationIgnored: false,
      )
    }

    guard let rawReturnType = method.returnType else { return nil }
    let returnType = isSendable ? storageValueType(from: rawReturnType) : rawReturnType
    if let initialValue = returnDefaultValue(for: method) {
      return TestDoubleStoredPropertyPlan(
        name: name,
        exposedType: returnType,
        storageType: returnType,
        storageDefaultExpression: initialValue,
        ordinaryInitialiser: initialValue,
        isObservationIgnored: isSendable && isFunctionType(returnType),
      )
    }
    return TestDoubleStoredPropertyPlan(
      name: name,
      exposedType: "\(returnType)?",
      storageType: "\(returnType)?",
      storageDefaultExpression: "nil",
      ordinaryInitialiser: nil,
      isObservationIgnored: isSendable && isFunctionType(returnType),
    )
  }

  private static func receivedProperties(
    for parameters: [TestDoubleRecordedParameterPlan],
    names: TestDoubleMethodNamePlan,
    isSendable: Bool,
  ) -> [TestDoubleStoredPropertyPlan] {
    guard !parameters.isEmpty else { return [] }
    let containsFunction = parameters.contains { isFunctionType($0.storageType) }
    let ignored = containsFunction

    if parameters.count == 1, let parameter = parameters.first {
      let type = parameter.storageType
      let wrappedType = isFunctionType(type) || (isSendable && type.hasPrefix("any "))
        ? "(\(type))"
        : type
      guard
        let receivedArgument = names.receivedArgument,
        let receivedInvocations = names.receivedInvocations
      else {
        return []
      }
      return [
        TestDoubleStoredPropertyPlan(
          name: receivedArgument,
          exposedType: "\(wrappedType)?",
          storageType: "\(wrappedType)?",
          storageDefaultExpression: "nil",
          ordinaryInitialiser: nil,
          isObservationIgnored: ignored,
        ),
        TestDoubleStoredPropertyPlan(
          name: receivedInvocations,
          exposedType: "[\(wrappedType)]",
          storageType: "[\(wrappedType)]",
          storageDefaultExpression: "[]",
          ordinaryInitialiser: "[]",
          isObservationIgnored: ignored,
        ),
      ]
    }

    let tupleType = "(" + parameters.map {
      "\($0.parameter.internalNameComponent): \($0.storageType)"
    }.joined(separator: ", ") + ")"
    let wrappedType = containsFunction ? "(\(tupleType))" : tupleType
    guard
      let receivedArguments = names.receivedArguments,
      let receivedInvocations = names.receivedInvocations
    else {
      return []
    }
    return [
      TestDoubleStoredPropertyPlan(
        name: receivedArguments,
        exposedType: "\(wrappedType)?",
        storageType: "\(wrappedType)?",
        storageDefaultExpression: "nil",
        ordinaryInitialiser: nil,
        isObservationIgnored: ignored,
      ),
      TestDoubleStoredPropertyPlan(
        name: receivedInvocations,
        exposedType: "[\(wrappedType)]",
        storageType: "[\(wrappedType)]",
        storageDefaultExpression: "[]",
        ordinaryInitialiser: "[]",
        isObservationIgnored: ignored,
      ),
    ]
  }

  private static func implementationProperty(
    _ method: ProtocolMethodInfo,
    name: String?,
    isSendable: Bool,
  ) -> TestDoubleStoredPropertyPlan? {
    guard let name else { return nil }
    let closureType = implementationClosureType(for: method, isSendable: isSendable)
    return TestDoubleStoredPropertyPlan(
      name: name,
      exposedType: closureType,
      storageType: closureType,
      storageDefaultExpression: "nil",
      ordinaryInitialiser: nil,
      isObservationIgnored: true,
    )
  }

  private static func recordedParameter(
    _ parameter: ParameterInfo,
    method: ProtocolMethodInfo,
    isSendable: Bool,
  ) -> TestDoubleRecordedParameterPlan? {
    guard
      let storageType = testDoubleStorageType(
        for: parameter,
        method: method,
        isSendable: isSendable,
      )
    else {
      return nil
    }

    guard isSendable else {
      return TestDoubleRecordedParameterPlan(
        parameter: parameter,
        storageType: storageType,
        valueExpression: parameter.internalName,
        snapshotDeclaration: nil,
      )
    }

    let snapshotName = "_visor\(parameter.internalNameComponent.capitalisedFirst)Snapshot"
    let snapshotDeclaration: String? =
      if parameter.isInout {
        "let \(snapshotName) = \(parameter.internalName)"
      } else {
        switch storageSnapshotStrategy(for: parameter.type) {
        case .copy:
          "let \(snapshotName) = copy \(parameter.internalName)"
        case .consume:
          "let \(snapshotName) = consume \(parameter.internalName)"
        case .none:
          nil
        }
      }

    return TestDoubleRecordedParameterPlan(
      parameter: parameter,
      storageType: storageType,
      valueExpression: snapshotDeclaration == nil ? parameter.internalName : snapshotName,
      snapshotDeclaration: snapshotDeclaration,
    )
  }

  private static func implementationInvocationArguments(
    for method: ProtocolMethodInfo,
    isSendable: Bool,
  ) -> String {
    method.parameters.map { parameter in
      if parameter.isInout {
        return "&\(parameter.internalName)"
      }
      if isSendable, storageSnapshotStrategy(for: parameter.type) == .consume {
        return "_visor\(parameter.internalNameComponent.capitalisedFirst)Snapshot"
      }
      return parameter.internalName
    }.joined(separator: ", ")
  }
}

// MARK: - Shared Planning Helpers

func unconstrainedGenericParameterNamesRequiringSendableStorage(
  in method: ProtocolMethodInfo
) -> [String] {
  let referencedNames = method.parameters
    .filter { !isNonEscapingFunctionType($0.type) }
    .flatMap { genericParameterNamesReferenced(by: method, in: $0.type) }
  let uniqueNames = Set(referencedNames)
  return method.genericParameterNames.filter {
    uniqueNames.contains($0)
      && !method.explicitlySendableGenericParameterNames.contains($0)
  }
}

func testDoubleStorageType(
  for parameter: ParameterInfo,
  method: ProtocolMethodInfo,
  isSendable: Bool,
) -> String? {
  guard isSendable else {
    return spyStorageType(for: parameter, method: method)
  }

  let strippedType = storageValueType(from: parameter.type)
  guard !isNonEscapingFunctionType(parameter.type) else { return nil }

  let genericNames = genericParameterNamesReferenced(by: method, in: strippedType)
  guard !genericNames.isEmpty else { return strippedType }
  guard genericNames.allSatisfy(method.explicitlySendableGenericParameterNames.contains) else {
    return nil
  }
  return "any Sendable"
}

func implementationClosureType(
  for method: ProtocolMethodInfo,
  isSendable: Bool,
) -> String {
  let parameters = method.parameters.map { stripEscaping(from: $0.type) }.joined(separator: ", ")
  var effects = ""
  if method.isAsync { effects += " async" }
  if let throwsKeyword = method.throwsEffect.keyword {
    effects += " \(throwsKeyword)"
  }
  let sendable = isSendable ? "@Sendable " : ""
  return "(\(sendable)(\(parameters))\(effects) -> \(method.returnType ?? "Void"))?"
}

func generateImplementationBodyLines(
  for plan: TestDoubleMethodGenerationPlan
) -> [String] {
  guard let implementationName = plan.implementationProperty?.name else {
    return generateFallbackBodyLines(
      method: plan.method,
      returnStorageName: plan.returnProperty?.name,
      style: .explicitReturn,
    )
  }

  let method = plan.method
  let invocationArguments = plan.implementationInvocationArguments
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
    returnStorageName: plan.returnProperty?.name,
    style: .explicitReturn,
  ))
  return lines
}
