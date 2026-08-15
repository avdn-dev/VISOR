//
//  SendableTestDoubleGenerator.swift
//  VISOR
//

// MARK: - SendableTestDoubleRenderer

/// Renders the shared test-double plan through lock-backed storage.
///
/// Semantic decisions belong to `TestDoubleGenerationPlan`. This renderer owns
/// only the synchronisation mechanics that distinguish a Sendable peer.
struct SendableTestDoubleRenderer {
  func render(_ plan: TestDoubleGenerationPlan) -> [String] {
    var members = storageMembers(plan)
    members.append(contentsOf: plan.protocolProperties.flatMap {
      observationStateChannelMembers($0, access: plan.access)
    })
    members.append(contentsOf: plan.allStoredProperties.flatMap {
      computedPropertyMembers($0, access: plan.access, storageName: plan.storageName)
    })

    switch plan.kind {
    case .stub:
      members.append(contentsOf: stubMembers(plan))
    case .spy:
      members.append(contentsOf: spyMembers(plan))
    }
    return members
  }

  private func storageMembers(_ plan: TestDoubleGenerationPlan) -> [String] {
    var members = ["  private struct \(plan.storageTypeName): Sendable {"]
    members.append(contentsOf: plan.allStoredProperties.map {
      "    var \($0.name): \($0.storageType) = \($0.storageDefaultExpression)"
    })
    members.append("  }")
    members.append("  @ObservationIgnored")
    members.append(
      "  private let \(plan.storageName) = VISORTestDoubles._TestDoubleStorage(\(plan.storageTypeName)())")
    return members
  }

  private func computedPropertyMembers(
    _ property: TestDoubleStoredPropertyPlan,
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
      lines.append(contentsOf: storageMutationMembers(property, storageName: storageName, indent: "      "))
    } else {
      lines.append("      withMutation(keyPath: \\.\(property.name)) {")
      lines.append(contentsOf: storageMutationMembers(property, storageName: storageName, indent: "        "))
      lines.append("      }")
    }
    if property.isObservationState {
      lines.append("      _\(property.name)ObservationChannel.publish(newValue)")
    }
    lines.append("    }")
    lines.append("  }")
    return lines
  }

  private func observationStateChannelMembers(
    _ property: TestDoubleStoredPropertyPlan,
    access: String)
    -> [String]
  {
    guard property.isObservationState else { return [] }
    let prefix = access.isEmpty ? "" : "\(access) "
    return [
      "  @ObservationIgnored",
      "  private let _\(property.name)ObservationChannel = "
        + "VISORObservation.ObservationChannel<\(property.exposedType)>(\(property.storageDefaultExpression))",
      "  \(prefix)var \(property.name)Source: "
        + "VISORObservation.ObservationSource<\(property.exposedType)> {",
      "    _\(property.name)ObservationChannel.source",
      "  }",
    ]
  }

  private func storageMutationMembers(
    _ property: TestDoubleStoredPropertyPlan,
    storageName: String,
    indent: String)
    -> [String]
  {
    [
      "\(indent)\(storageName).withMutation(retiring: { $0.\(property.name) }) { state in",
      "\(indent)  state.\(property.name) = newValue",
      "\(indent)}",
    ]
  }

  private func stubMembers(_ plan: TestDoubleGenerationPlan) -> [String] {
    var members: [String] = []
    for methodPlan in plan.methods {
      if methodPlan.method.isConcurrent {
        members.append("  @concurrent")
      }
      members.append("  \(buildMethodSignature(methodPlan.method, access: plan.access)) {")
      if let returnProperty = methodPlan.returnProperty {
        members.append(
          "    let \(returnProperty.name) = \(plan.storageName).withValue { $0.\(returnProperty.name) }")
      }
      members.append(contentsOf: generateFallbackBodyLines(
        method: methodPlan.method,
        returnStorageName: methodPlan.returnProperty?.name,
        style: .explicitReturn))
      members.append("  }")
    }
    return members
  }

  private func spyMembers(_ plan: TestDoubleGenerationPlan) -> [String] {
    let prefix = plan.access.isEmpty ? "" : "\(plan.access) "
    var members: [String] = []
    for methodPlan in plan.methods {
      if methodPlan.method.isConcurrent {
        members.append("  @concurrent")
      }
      members.append("  \(buildMethodSignature(methodPlan.method, access: plan.access)) {")
      members.append(contentsOf: methodPlan.storageSnapshotDeclarations.map { "    \($0)" })
      members.append(contentsOf: atomicRecordingMembers(
        methodPlan,
        callLogName: plan.callLogProperty?.name ?? "calls",
        storageName: plan.storageName))
      members.append(contentsOf: generateImplementationBodyLines(for: methodPlan))
      members.append("  }")
    }

    if !plan.methods.isEmpty, let callTypeName = plan.names.callType {
      members.append("  \(prefix)enum \(callTypeName): Sendable {")
      members.append(contentsOf: plan.methods.compactMap { method in
        method.callCase.map { "    \($0.declaration)" }
      })
      members.append("  }")
    }
    return members
  }

  private func atomicRecordingMembers(
    _ plan: TestDoubleMethodGenerationPlan,
    callLogName: String,
    storageName: String)
    -> [String]
  {
    var mutationNames = plan.recordingMutationPropertyNames
    mutationNames.append(callLogName)

    let snapshotNames = [
      plan.implementationProperty?.name,
      plan.returnProperty?.name,
    ].compactMap { $0 }

    var storageBody = ["state.\(plan.callCountName) += 1"]
    if plan.receivedParameters.count == 1,
       let parameter = plan.receivedParameters.first,
       let receivedArgument = plan.names.receivedArgument,
       let receivedInvocations = plan.names.receivedInvocations
    {
      storageBody.append("state.\(receivedArgument) = \(parameter.valueExpression)")
      storageBody.append("state.\(receivedInvocations).append(\(parameter.valueExpression))")
    } else if plan.receivedParameters.count > 1,
              let receivedArguments = plan.names.receivedArguments,
              let receivedInvocations = plan.names.receivedInvocations
    {
      let tuple = "(" + plan.receivedParameters.map(\.valueExpression).joined(separator: ", ") + ")"
      storageBody.append("state.\(receivedArguments) = \(tuple)")
      storageBody.append("state.\(receivedInvocations).append(\(tuple))")
    }
    if let callCase = plan.callCase {
      storageBody.append("state.\(callLogName).append(\(callCase.invocation))")
    }

    return wrapAtomicRecording(
      mutationNames: mutationNames,
      retirementName: plan.recordingRetirementPropertyName,
      snapshotNames: snapshotNames,
      storageBody: storageBody,
      storageName: storageName)
  }

  private func wrapAtomicRecording(
    mutationNames: [String],
    retirementName: String?,
    snapshotNames: [String],
    storageBody: [String],
    storageName: String)
    -> [String]
  {
    let binding = switch snapshotNames.count {
    case 0:
      ""
    case 1:
      "let \(snapshotNames[0]) = "
    default:
      "let (\(snapshotNames.joined(separator: ", "))) = "
    }

    var lines: [String] = []
    var indent = "    "
    for (index, name) in mutationNames.enumerated() {
      let assignment = index == 0 ? binding : ""
      lines.append("\(indent)\(assignment)withMutation(keyPath: \\.\(name)) {")
      indent += "  "
    }
    let retirementExpression = if let retirementName {
      "{ $0.\(retirementName) }"
    } else {
      "{ _ in () }"
    }
    lines.append(
      "\(indent)\(storageName).withMutation(retiring: \(retirementExpression)) { state in")
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
}
