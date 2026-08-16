//
//  TestDoubleDiagnostic.swift
//  VISOR
//
//  Created by Anh Nguyen on 18/2/2026.
//

import SwiftDiagnostics

// MARK: - TestDoubleDiagnostic

enum TestDoubleDiagnostic: DiagnosticMessage {
  case notAProtocol(macroName: String)
  case associatedTypesNotSupported(macroName: String)
  case subscriptsNotSupported(macroName: String)
  case staticRequirementsNotSupported(macroName: String)
  case initialiserRequirementsNotSupported(macroName: String)
  case inheritedProtocolNotSupported(protocolName: String, macroName: String)
  case sendableTraitRequired(macroName: String)
  case unsupportedRequirement(kind: String, macroName: String)
  case unknownTypeDefaults(macroName: String)
  case observationStateBaselineRequired(propertyName: String, type: String, macroName: String)
  case implementationNameCollision(methodName: String, preferredName: String, generatedName: String, macroName: String)
  case generatedMemberNameCollision(role: String, preferredName: String, generatedName: String, macroName: String)
  case duplicateTrait(trait: String, macroName: String)
  case unsupportedTrait(trait: String, macroName: String)
  case sendableSpyUnconstrainedGenericValues(methodName: String, genericNames: [String])

  // MARK: Internal

  var message: String {
    switch self {
    case .notAProtocol(let macroName):
      "@\(macroName) can only be applied to protocols"
    case .associatedTypesNotSupported(let macroName):
      "@\(macroName) does not support protocols with associated types"
    case .subscriptsNotSupported(let macroName):
      "@\(macroName) does not support subscript requirements"
    case .staticRequirementsNotSupported(let macroName):
      "@\(macroName) does not support static or class requirements"
    case .initialiserRequirementsNotSupported(let macroName):
      "@\(macroName) does not support initialiser requirements"
    case .inheritedProtocolNotSupported(let protocolName, let macroName):
      "@\(macroName) cannot analyse requirements inherited from '\(protocolName)'"
    case .sendableTraitRequired(let macroName):
      "@\(macroName) requires the '.sendable' trait when the protocol inherits Sendable"
    case .unsupportedRequirement(let kind, let macroName):
      "@\(macroName) does not support \(kind) requirements"
    case .unknownTypeDefaults(let macroName):
      "@\(macroName): Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."
    case .observationStateBaselineRequired(let propertyName, let type, let macroName):
      "@\(macroName) cannot generate observation State '\(propertyName)' because '\(type)' has no inferred baseline; supply @ObservationState(initial:) or @DefaultValue"
    case .implementationNameCollision(let methodName, let preferredName, let generatedName, let macroName):
      "@\(macroName): '\(preferredName)' collides with an existing protocol member; using '\(generatedName)' for the generated implementation closure for '\(methodName)()'."
    case .generatedMemberNameCollision(let role, let preferredName, let generatedName, let macroName):
      "@\(macroName): generated \(role) '\(preferredName)' collides with another member; using '\(generatedName)'."
    case .duplicateTrait(let trait, let macroName):
      "@\(macroName) received duplicate '.\(trait)' traits"
    case .unsupportedTrait(let trait, let macroName):
      "@\(macroName) does not support the '\(trait)' trait"
    case .sendableSpyUnconstrainedGenericValues(let methodName, let genericNames):
      sendableSpyUnconstrainedGenericValuesMessage(
        methodName: methodName,
        genericNames: genericNames)
    }
  }

  var diagnosticID: MessageID {
    switch self {
    case .notAProtocol:
      MessageID(domain: "VISOR", id: "notAProtocol")
    case .associatedTypesNotSupported:
      MessageID(domain: "VISOR", id: "associatedTypesNotSupported")
    case .subscriptsNotSupported:
      MessageID(domain: "VISOR", id: "subscriptsNotSupported")
    case .staticRequirementsNotSupported:
      MessageID(domain: "VISOR", id: "staticRequirementsNotSupported")
    case .initialiserRequirementsNotSupported:
      MessageID(domain: "VISOR", id: "initialiserRequirementsNotSupported")
    case .inheritedProtocolNotSupported:
      MessageID(domain: "VISOR", id: "inheritedProtocolNotSupported")
    case .sendableTraitRequired:
      MessageID(domain: "VISOR", id: "sendableTraitRequired")
    case .unsupportedRequirement:
      MessageID(domain: "VISOR", id: "unsupportedTestDoubleRequirement")
    case .unknownTypeDefaults:
      MessageID(domain: "VISOR", id: "unknownTypeDefaults")
    case .observationStateBaselineRequired:
      MessageID(domain: "VISOR", id: "observationStateBaselineRequired")
    case .implementationNameCollision:
      MessageID(domain: "VISOR", id: "implementationNameCollision")
    case .generatedMemberNameCollision:
      MessageID(domain: "VISOR", id: "generatedMemberNameCollision")
    case .duplicateTrait:
      MessageID(domain: "VISOR", id: "duplicateTestDoubleTrait")
    case .unsupportedTrait:
      MessageID(domain: "VISOR", id: "unsupportedTestDoubleTrait")
    case .sendableSpyUnconstrainedGenericValues:
      MessageID(domain: "VISOR", id: "sendableSpyUnconstrainedGenericValues")
    }
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .notAProtocol, .associatedTypesNotSupported, .subscriptsNotSupported,
         .staticRequirementsNotSupported, .initialiserRequirementsNotSupported,
         .inheritedProtocolNotSupported, .sendableTraitRequired, .unsupportedRequirement,
         .duplicateTrait, .unsupportedTrait, .sendableSpyUnconstrainedGenericValues,
         .observationStateBaselineRequired:
      .error
    case .unknownTypeDefaults:
      .note
    case .implementationNameCollision, .generatedMemberNameCollision:
      .warning
    }
  }
}

private func sendableSpyUnconstrainedGenericValuesMessage(
  methodName: String,
  genericNames: [String])
  -> String
{
  let formattedNames = genericNames.map { "'\($0)'" }.joined(separator: ", ")
  if genericNames.count == 1 {
    return "@GenerateSpy(.sendable) cannot record unconstrained generic value \(formattedNames) in '\(methodName)()'; constrain it to Sendable"
  }
  return "@GenerateSpy(.sendable) cannot record unconstrained generic values \(formattedNames) in '\(methodName)()'; constrain them to Sendable"
}
