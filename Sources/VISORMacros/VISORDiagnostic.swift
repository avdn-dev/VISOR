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
  case notAClass
  case notAStruct(macroName: String)
  case missingArguments(macroName: String)
  case missingSelfSuffix(macroName: String)
  case missingObservable
  case invalidBoundDependency(name: String, propertyName: String)
  case malformedBoundKeyPath(propertyName: String)
  case invalidReactionParameter(methodName: String)
  case malformedReactionKeyPath(methodName: String)
  case manualStartObservingMissingMethod(methodName: String)
  case missingState
  case statePropertyMissingInitializer
  case actionWithoutHandle
  case handleWrongLabel
  case boundOnClassVar(propertyName: String)
  case boundOnLetProperty(propertyName: String)
  case invalidObservationPolicy

  // MARK: Internal

  var message: String {
    switch self {
    case .missingContent(let macroName):
      "@\(macroName) requires: var content: some View"
    case .notAClass:
      "@ViewModel can only be applied to classes"
    case .notAStruct(let macroName):
      "@\(macroName) can only be applied to structs"
    case .missingArguments(let macroName):
      "@\(macroName) requires (ViewModel.self) argument"
    case .missingSelfSuffix(let macroName):
      "@\(macroName) argument must use .self suffix (e.g., MyViewModel.self)"
    case .missingObservable:
      "@ViewModel requires @Observable on the class to enable observation tracking"
    case .invalidBoundDependency(let name, let propertyName):
      "@Bound(\\.\(name)) on '\(propertyName)': no stored 'let \(name)' found on this class"
    case .malformedBoundKeyPath(let propertyName):
      "@Bound on '\(propertyName)': expected single-level key path like \\ClassName.dependencyName (nested paths are not supported)"
    case .invalidReactionParameter(let methodName):
      "@Reaction on '\(methodName)': method must have exactly one parameter"
    case .malformedReactionKeyPath(let methodName):
      "@Reaction on '\(methodName)': expected key path argument like \\.dependency.property"
    case .manualStartObservingMissingMethod(let methodName):
      "startObserving() does not call \(methodName)(); state derivation will not run"
    case .missingState:
      "@ViewModel requires a nested 'struct State: Equatable { }'"
    case .statePropertyMissingInitializer:
      "@ViewModel: 'var state' must have a default value (e.g., 'var state = State()')"
    case .actionWithoutHandle:
      "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action)' method found"
    case .handleWrongLabel:
      "@ViewModel: 'handle(action:)' should use an underscore label: 'handle(_ action: Action)'"
    case .boundOnClassVar(let name):
      "@Bound on '\(name)': move @Bound to the State struct property instead"
    case .boundOnLetProperty(let name):
      "@Bound on '\(name)': use 'var' instead of 'let' — bound properties must be mutable"
    case .invalidObservationPolicy:
      "@LazyViewModel observationPolicy must be .alwaysObserving, .pauseInBackground, or .pauseWhenInactive"
    }
  }

  var diagnosticID: MessageID {
    let id: String
    switch self {
    case .missingContent: id = "missingContent"
    case .notAClass: id = "notAClass"
    case .notAStruct: id = "notAStruct"
    case .missingArguments: id = "missingArguments"
    case .missingSelfSuffix: id = "missingSelfSuffix"
    case .missingObservable: id = "missingObservable"
    case .invalidBoundDependency: id = "invalidBoundDependency"
    case .malformedBoundKeyPath: id = "malformedBoundKeyPath"
    case .invalidReactionParameter: id = "invalidReactionParameter"
    case .malformedReactionKeyPath: id = "malformedReactionKeyPath"
    case .manualStartObservingMissingMethod: id = "manualStartObservingMissingMethod"
    case .missingState: id = "missingState"
    case .statePropertyMissingInitializer: id = "statePropertyMissingInitializer"
    case .actionWithoutHandle: id = "actionWithoutHandle"
    case .handleWrongLabel: id = "handleWrongLabel"
    case .boundOnClassVar: id = "boundOnClassVar"
    case .boundOnLetProperty: id = "boundOnLetProperty"
    case .invalidObservationPolicy: id = "invalidObservationPolicy"
    }
    return MessageID(domain: "VISOR", id: id)
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .malformedBoundKeyPath, .manualStartObservingMissingMethod,
         .boundOnClassVar, .boundOnLetProperty,
         .malformedReactionKeyPath:
      .warning
    case .missingState, .statePropertyMissingInitializer, .actionWithoutHandle, .handleWrongLabel, .invalidBoundDependency:
      .error
    default:
      .error
    }
  }
}
