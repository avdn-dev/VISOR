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
    }
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .notAProtocol, .associatedTypesNotSupported:
      .error
    case .subscriptsSkipped, .staticMembersSkipped:
      .warning
    }
  }
}
