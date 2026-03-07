//
//  VISORDiagnostic.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

import SwiftDiagnostics

// MARK: - VISORDiagnostic

enum VISORDiagnostic: DiagnosticMessage {
  case missingContent(macroName: String)
  case singleViewModelInLazyViewModels
  case notAClass
  case notAStruct(macroName: String)
  case missingArguments(macroName: String)
  case missingObservable
  case invalidBoundDependency(name: String, propertyName: String)
  case malformedBoundKeyPath(propertyName: String)
  case invalidReactionParameter(methodName: String)
  case malformedLazyViewModelsArgument
  case manualStartObservingMissingMethod(methodName: String)
  case actionWithoutPerform
  case performNotAsync
  case boundOnClassVar(propertyName: String)
  case boundOnLetProperty(propertyName: String)

  // MARK: Internal

  var message: String {
    switch self {
    case .missingContent(let macroName):
      "@\(macroName) requires: var content: some View"
    case .singleViewModelInLazyViewModels:
      "@LazyViewModels with a single ViewModel; use @LazyViewModel instead"
    case .notAClass:
      "@ViewModel can only be applied to classes"
    case .notAStruct(let macroName):
      "@\(macroName) can only be applied to structs"
    case .missingArguments(let macroName):
      "@\(macroName) requires (ViewModel.self) argument"
    case .missingObservable:
      "@ViewModel requires @Observable on the class to enable observation tracking"
    case .invalidBoundDependency(let name, let propertyName):
      "@Bound(\\.\(name)) on '\(propertyName)': no stored 'let \(name)' found on this class"
    case .malformedBoundKeyPath(let propertyName):
      "@Bound on '\(propertyName)': expected key path argument like \\Self.dependencyName"
    case .invalidReactionParameter(let methodName):
      "@Reaction on '\(methodName)': method must have exactly one parameter"
    case .malformedLazyViewModelsArgument:
      "@LazyViewModels: unrecognized argument (expected ViewModel.self)"
    case .manualStartObservingMissingMethod(let methodName):
      "startObserving() does not call \(methodName)(); state derivation will not run"
    case .actionWithoutPerform:
      "@ViewModel: 'Action' enum declared but no 'perform(_ action: Action) async' method found"
    case .performNotAsync:
      "@ViewModel: 'perform(_:)' should be 'async' for structured concurrency"
    case .boundOnClassVar(let name):
      "@Bound on '\(name)': move @Bound to the State struct property instead"
    case .boundOnLetProperty(let name):
      "@Bound on '\(name)': use 'var' instead of 'let' — bound properties must be mutable"
    }
  }

  var diagnosticID: MessageID {
    // Strips associated values from e.g. "notAStruct(macroName: \"Foo\")" -> "notAStruct"
    let caseName = String(describing: self).prefix(while: { $0 != "(" })
    return MessageID(domain: "VISOR", id: String(caseName))
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .missingObservable, .malformedBoundKeyPath, .malformedLazyViewModelsArgument,
         .singleViewModelInLazyViewModels, .manualStartObservingMissingMethod,
         .performNotAsync, .boundOnClassVar, .boundOnLetProperty:
      .warning
    case .actionWithoutPerform, .invalidBoundDependency:
      .error
    default:
      .error
    }
  }
}
