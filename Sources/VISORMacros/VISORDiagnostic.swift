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
  case malformedBoundKeyPath(propertyName: String, className: String)
  case boundOutsideState
  case invalidReactionParameter(methodName: String)
  case malformedReactionKeyPath(methodName: String)
  case reactionNotOnMethod
  case reactionInsideNestedType(methodName: String)
  case manualStartObservingMissingMethod(methodName: String)
  case missingState
  case actionWithoutHandle
  case handleWrongLabel
  case boundOnLetProperty(propertyName: String)
  case boundPropertyHasDefault(propertyName: String)
  case invalidPolledDependency(name: String, propertyName: String)
  case malformedPolledKeyPath(propertyName: String, className: String)
  case polledOnLetProperty(propertyName: String)
  case polledPropertyHasDefault(propertyName: String)
  case polledMissingInterval(propertyName: String)
  case polledOutsideState
  case invalidObservationPolicy
  case stateClassNotFinal
  case stateClassMissingObservable
  case stateClassMissingInit(expectedSignature: String)

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
    case .malformedBoundKeyPath(let propertyName, let className):
      "@Bound on '\(propertyName)': expected key path like \\\(className).dependency.property"
    case .boundOutsideState:
      "@Bound must be inside 'class State' — move to the corresponding State property"
    case .invalidReactionParameter(let methodName):
      "@Reaction on '\(methodName)': method must have exactly one parameter"
    case .malformedReactionKeyPath(let methodName):
      "@Reaction on '\(methodName)': expected key path argument like \\.dependency.property"
    case .reactionNotOnMethod:
      "@Reaction can only annotate methods"
    case .reactionInsideNestedType(let methodName):
      "@Reaction on '\(methodName)' must be at the class level, not inside a nested type"
    case .manualStartObservingMissingMethod(let methodName):
      "startObserving() does not call \(methodName)(); state derivation will not run"
    case .missingState:
      "@ViewModel requires a nested '@Observable final class State { }'"
    case .actionWithoutHandle:
      "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action)' method found"
    case .handleWrongLabel:
      "@ViewModel: 'handle(action:)' should use an underscore label: 'handle(_ action: Action)'"
    case .boundOnLetProperty(let name):
      "@Bound on '\(name)': use 'var' instead of 'let' — bound properties must be mutable"
    case .boundPropertyHasDefault(let propertyName):
      "@Bound on '\(propertyName)': remove the default value — state is initialised from the service"
    case .invalidPolledDependency(let name, let propertyName):
      "@Polled(\\.\(name)) on '\(propertyName)': no stored 'let \(name)' found on this class"
    case .malformedPolledKeyPath(let propertyName, let className):
      "@Polled on '\(propertyName)': expected key path like \\\(className).dependency.property"
    case .polledOnLetProperty(let name):
      "@Polled on '\(name)': use 'var' instead of 'let' — polled properties must be mutable"
    case .polledPropertyHasDefault(let propertyName):
      "@Polled on '\(propertyName)': remove the default value — state is initialised from the service"
    case .polledMissingInterval(let propertyName):
      "@Polled on '\(propertyName)': missing 'every:' interval parameter"
    case .polledOutsideState:
      "@Polled must be inside 'class State' — move to the corresponding State property"
    case .invalidObservationPolicy:
      "@LazyViewModel observationPolicy must be .alwaysObserving, .pauseInBackground, or .pauseWhenInactive"
    case .stateClassNotFinal:
      "State class must be 'final'"
    case .stateClassMissingObservable:
      "State class requires @Observable"
    case .stateClassMissingInit(let sig):
      "State class needs a user-declared init — #Preview cannot see macro-generated initialisers. Add: \(sig)"
    }
  }

  var diagnosticID: MessageID {
    let id = switch self {
    case .missingContent: "missingContent"
    case .notAClass: "notAClass"
    case .notAStruct: "notAStruct"
    case .missingArguments: "missingArguments"
    case .missingSelfSuffix: "missingSelfSuffix"
    case .missingObservable: "missingObservable"
    case .invalidBoundDependency: "invalidBoundDependency"
    case .malformedBoundKeyPath: "malformedBoundKeyPath"
    case .boundOutsideState: "boundOutsideState"
    case .invalidReactionParameter: "invalidReactionParameter"
    case .malformedReactionKeyPath: "malformedReactionKeyPath"
    case .reactionNotOnMethod: "reactionNotOnMethod"
    case .reactionInsideNestedType: "reactionInsideNestedType"
    case .manualStartObservingMissingMethod: "manualStartObservingMissingMethod"
    case .missingState: "missingState"
    case .actionWithoutHandle: "actionWithoutHandle"
    case .handleWrongLabel: "handleWrongLabel"
    case .boundOnLetProperty: "boundOnLetProperty"
    case .boundPropertyHasDefault: "boundPropertyHasDefault"
    case .invalidPolledDependency: "invalidPolledDependency"
    case .malformedPolledKeyPath: "malformedPolledKeyPath"
    case .polledOnLetProperty: "polledOnLetProperty"
    case .polledPropertyHasDefault: "polledPropertyHasDefault"
    case .polledMissingInterval: "polledMissingInterval"
    case .polledOutsideState: "polledOutsideState"
    case .invalidObservationPolicy: "invalidObservationPolicy"
    case .stateClassNotFinal: "stateClassNotFinal"
    case .stateClassMissingObservable: "stateClassMissingObservable"
    case .stateClassMissingInit: "stateClassMissingInit"
    }
    return MessageID(domain: "VISOR", id: id)
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .malformedBoundKeyPath, .manualStartObservingMissingMethod,
         .boundOnLetProperty, .malformedReactionKeyPath,
         .malformedPolledKeyPath, .polledOnLetProperty:
      .warning
    case .missingObservable, .boundOutsideState, .reactionNotOnMethod, .reactionInsideNestedType,
         .missingContent, .notAClass, .notAStruct, .missingArguments, .missingSelfSuffix,
         .missingState, .actionWithoutHandle, .handleWrongLabel, .invalidBoundDependency,
         .invalidReactionParameter,
         .invalidPolledDependency, .polledPropertyHasDefault, .polledMissingInterval,
         .boundPropertyHasDefault,
         .polledOutsideState, .invalidObservationPolicy,
         .stateClassNotFinal, .stateClassMissingObservable:
      .error
    case .stateClassMissingInit:
      .warning
    }
  }
}
