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

  // MARK: Internal

  var macroName: String {
    switch self {
    case .stub:
      "GenerateStub"
    case .spy:
      "GenerateSpy"
    }
  }

  var generatedTypePrefix: String {
    switch self {
    case .stub:
      "Stub"
    case .spy:
      "Spy"
    }
  }
}

// MARK: - TestDoubleGenerator

struct TestDoubleGenerator {

  // MARK: Internal

  let kind: TestDoubleKind

  func expand(
    _ node: AttributeSyntax,
    declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext,
  ) throws -> [DeclSyntax] {
    guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
      context.diagnose(Diagnostic(
        node: Syntax(declaration),
        message: TestDoubleDiagnostic.notAProtocol(macroName: kind.macroName),
      ))
      return []
    }

    guard let traits = TestDoubleTraits.parse(from: node, macroName: kind.macroName, in: context) else {
      return []
    }

    let analysis = ProtocolAnalysis(protocolDecl)
    guard
      validateProtocolForTestDouble(
        analysis,
        protocolDecl: protocolDecl,
        traits: traits,
        macroName: kind.macroName,
        context: context,
      )
    else {
      return []
    }

    if
      let property = analysis.properties.first(where: {
        $0.observationState != nil
          && $0.defaultValueExpression == nil
          && defaultValue(for: $0.type) == nil
      })
    {
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.observationStateBaselineRequired(
          propertyName: property.name,
          type: property.type,
          macroName: kind.macroName,
        ),
      ))
      return []
    }

    if
      kind == .spy, traits.isSendable,
      let unsupportedMethod = analysis.methods.lazy.compactMap({ method -> (ProtocolMethodInfo, [String])? in
        let genericNames = unconstrainedGenericParameterNamesRequiringSendableStorage(in: method)
        return genericNames.isEmpty ? nil : (method, genericNames)
      }).first
    {
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.sendableSpyUnconstrainedGenericValues(
          methodName: unsupportedMethod.0.name,
          genericNames: unsupportedMethod.1,
        ),
      ))
      return []
    }

    let namePlan = TestDoubleNamePlan(
      kind: kind,
      analysis: analysis,
      isSendable: traits.isSendable,
    )
    if hasUnknownTypeDefaults(properties: analysis.properties, methods: analysis.methods) {
      context.diagnose(Diagnostic(
        node: Syntax(protocolDecl),
        message: TestDoubleDiagnostic.unknownTypeDefaults(macroName: kind.macroName),
      ))
    }
    namePlan.diagnose(
      protocolDecl: protocolDecl,
      macroName: kind.macroName,
      context: context,
    )

    let plan = TestDoubleGenerationPlan(
      kind: kind,
      protocolName: protocolDecl.name.trimmedDescription,
      access: accessLevel(of: protocolDecl),
      analysis: analysis,
      names: namePlan,
      isSendable: traits.isSendable,
    )
    var members = traits.isSendable
      ? SendableTestDoubleRenderer().render(plan)
      : OrdinaryTestDoubleRenderer().render(plan)
    members.append(contentsOf: initialiserMembers(access: plan.access))

    let prefix = plan.access.isEmpty ? "" : "\(plan.access) "
    let isolation = plan.isSendable ? "nonisolated " : ""
    let sendableConformance = plan.isSendable ? ", Sendable" : ""
    let body = members.joined(separator: "\n")
    let result: DeclSyntax = """
      @Observable
      \(raw: isolation)\(raw: prefix)final class \(raw: plan.typeName): \(raw: plan.protocolName)\(raw: sendableConformance) {
      \(raw: body)
      }
      """
    return [result]
  }

  // MARK: Private

  private func initialiserMembers(access: String) -> [String] {
    guard access == "public" || access == "package" else { return [] }
    return ["  \(access) init() {}"]
  }
}

// MARK: - OrdinaryTestDoubleRenderer

private struct OrdinaryTestDoubleRenderer {

  // MARK: Internal

  func render(_ plan: TestDoubleGenerationPlan) -> [String] {
    var members = plan.protocolProperties.flatMap {
      directPropertyMembers($0, access: plan.access)
    }

    switch plan.kind {
    case .stub:
      members.append(contentsOf: stubMembers(plan))
    case .spy:
      members.append(contentsOf: spyMembers(plan))
    }
    return members
  }

  // MARK: Private

  private func stubMembers(_ plan: TestDoubleGenerationPlan) -> [String] {
    var members = [String]()
    for methodPlan in plan.methods {
      members.append(contentsOf: methodPlan.storedProperties.flatMap {
        directPropertyMembers($0, access: plan.access)
      })

      let signature = buildMethodSignature(methodPlan.method, access: plan.access)
      let bodyLines = generateFallbackBodyLines(
        method: methodPlan.method,
        returnStorageName: methodPlan.returnProperty?.name,
        style: .expression,
      )
      if bodyLines.isEmpty {
        members.append("  \(signature) { }")
      } else if bodyLines.count == 1 {
        members.append("  \(signature) { \(bodyLines[0].trimmingWhitespace) }")
      } else {
        members.append("  \(signature) {")
        members.append(contentsOf: bodyLines)
        members.append("  }")
      }
    }
    return members
  }

  private func spyMembers(_ plan: TestDoubleGenerationPlan) -> [String] {
    let prefix = plan.access.isEmpty ? "" : "\(plan.access) "
    var members = [String]()
    members.reserveCapacity(plan.methods.count * 8 + (plan.methods.isEmpty ? 0 : 3))

    for methodPlan in plan.methods {
      members.append("  // -- \(methodPlan.names.prefix) --")
      members.append(contentsOf: methodPlan.storedProperties.flatMap {
        directPropertyMembers(
          $0,
          access: plan.access,
          omitType: $0.name == methodPlan.callCountName,
        )
      })

      let signature = buildMethodSignature(methodPlan.method, access: plan.access)
      var bodyLines = directRecordingBodyLines(
        methodPlan,
        callLogName: plan.callLogProperty?.name ?? "calls",
      )
      bodyLines.append(contentsOf: generateImplementationBodyLines(for: methodPlan))
      members.append("  \(signature) {")
      members.append(contentsOf: bodyLines)
      members.append("  }")
    }

    if
      !plan.methods.isEmpty,
      let callTypeName = plan.names.callType,
      let callLogProperty = plan.callLogProperty
    {
      members.append("  \(prefix)enum \(callTypeName) {")
      members.append(contentsOf: plan.methods.compactMap { method in
        method.callCase.map { "    \($0.declaration)" }
      })
      members.append("  }")
      members.append(contentsOf: directPropertyMembers(callLogProperty, access: plan.access))
    }
    return members
  }

  private func directRecordingBodyLines(
    _ plan: TestDoubleMethodGenerationPlan,
    callLogName: String,
  ) -> [String] {
    var lines = ["    \(plan.callCountName) += 1"]
    if
      plan.receivedParameters.count == 1,
      let parameter = plan.receivedParameters.first,
      let receivedArgument = plan.names.receivedArgument,
      let receivedInvocations = plan.names.receivedInvocations
    {
      lines.append("    \(receivedArgument) = \(parameter.valueExpression)")
      lines.append("    \(receivedInvocations).append(\(parameter.valueExpression))")
    } else if
      plan.receivedParameters.count > 1,
      let receivedArguments = plan.names.receivedArguments,
      let receivedInvocations = plan.names.receivedInvocations
    {
      let tuple = "(" + plan.receivedParameters.map(\.valueExpression).joined(separator: ", ") + ")"
      lines.append("    \(receivedArguments) = \(tuple)")
      lines.append("    \(receivedInvocations).append(\(tuple))")
    }
    if let callCase = plan.callCase {
      lines.append("    \(callLogName).append(\(callCase.invocation))")
    }
    return lines
  }

  private func directPropertyMembers(
    _ property: TestDoubleStoredPropertyPlan,
    access: String,
    omitType: Bool = false,
  ) -> [String] {
    if property.isObservationState {
      return observationStateMembers(property, access: access)
    }

    let prefix = access.isEmpty ? "" : "\(access) "
    var members = [String]()
    if property.isObservationIgnored {
      members.append("  @ObservationIgnored")
    }
    var declaration = "  \(prefix)var \(property.name)"
    if !omitType {
      declaration += ": \(property.exposedType)"
    }
    if let ordinaryInitialiser = property.ordinaryInitialiser {
      declaration += " = \(ordinaryInitialiser)"
    }
    members.append(declaration)
    return members
  }

  private func observationStateMembers(
    _ property: TestDoubleStoredPropertyPlan,
    access: String,
  ) -> [String] {
    guard let observationState = property.observationState else { return [] }
    let prefix = access.isEmpty ? "" : "\(access) "
    let channelName = property.observationChannelName
      ?? "_\(property.name)ObservationChannel"
    let sequenceName = observationState.sequenceName(for: property.name)
    var members = [
      "  @ObservationIgnored",
      "  nonisolated private let \(channelName) = "
        + "VISORObservation.ObservationChannel<\(property.exposedType)>(\(property.storageDefaultExpression))",
      "  nonisolated \(prefix)var \(sequenceName): "
        + "VISORObservation.ObservationSource<\(property.exposedType)> {",
      "    \(channelName).source",
      "  }",
      "  \(prefix)var \(property.name): \(property.exposedType) {",
      "    get {",
    ]
    if !property.isObservationIgnored {
      members.append("      access(keyPath: \\.\(property.name))")
    }
    members.append("      return \(channelName).source.currentSnapshot()")
    members.append("    }")
    members.append("    set {")
    if property.isObservationIgnored {
      members.append("      \(channelName).publish(newValue)")
    } else {
      members.append("      withMutation(keyPath: \\.\(property.name)) {")
      members.append("        \(channelName).publish(newValue)")
      members.append("      }")
    }
    members.append("    }")
    members.append("  }")
    return members
  }
}
