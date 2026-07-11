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
  case subscriptsSkipped(macroName: String)
  case staticMembersSkipped(macroName: String)
  case unknownTypeDefaults(macroName: String)
  case implementationNameCollision(methodName: String, preferredName: String, generatedName: String, macroName: String)
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
    case .subscriptsSkipped(let macroName):
      "@\(macroName) skips subscript members (not yet supported)"
    case .staticMembersSkipped(let macroName):
      "@\(macroName) skips static members (not yet supported)"
    case .unknownTypeDefaults(let macroName):
      "@\(macroName): Custom types without known defaults use implicitly unwrapped optionals for properties and fatalError for methods. Use @DefaultValue for properties or @DefaultReturn for method returns."
    case .implementationNameCollision(let methodName, let preferredName, let generatedName, let macroName):
      "@\(macroName): '\(preferredName)' collides with an existing protocol member; using '\(generatedName)' for the generated implementation closure for '\(methodName)()'."
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
    case .subscriptsSkipped:
      MessageID(domain: "VISOR", id: "subscriptsSkipped")
    case .staticMembersSkipped:
      MessageID(domain: "VISOR", id: "staticMembersSkipped")
    case .unknownTypeDefaults:
      MessageID(domain: "VISOR", id: "unknownTypeDefaults")
    case .implementationNameCollision:
      MessageID(domain: "VISOR", id: "implementationNameCollision")
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
    case .notAProtocol, .associatedTypesNotSupported, .duplicateTrait, .unsupportedTrait,
         .sendableSpyUnconstrainedGenericValues:
      .error
    case .subscriptsSkipped, .staticMembersSkipped:
      .warning
    case .unknownTypeDefaults:
      .note
    case .implementationNameCollision:
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
