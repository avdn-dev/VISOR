import SwiftDiagnostics

enum VISORDiagnostic: DiagnosticMessage {
  case missingContent(macroName: String)
  case notAClass
  case notAStruct(macroName: String)
  case missingArguments(macroName: String)
  case missingSelfSuffix(macroName: String)
  case missingObservable
  case missingState
  case actionWithoutHandle
  case handleWrongLabel
  case stateClassNotFinal
  case lazyViewModelStateAliasCollision
  case viewModelRequiresMainActor
  case viewModelRequiresStableState
  case viewModelRequiresVisibleState
  case invalidSourceBoundDeclaration
  case invalidSourceBoundPlacement
  case invalidSourceReactionDeclaration
  case invalidSourceReactionPlacement
  case sourceObservationRequiresPlainState
  case conditionalDeinitialiserUnsupported

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
    case .missingState:
      "@ViewModel requires a nested plain 'final class State { }'"
    case .actionWithoutHandle:
      "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action)' method found"
    case .handleWrongLabel:
      "@ViewModel: 'handle(action:)' should use an underscore label: 'handle(_ action: Action)'"
    case .stateClassNotFinal:
      "State class must be 'final'"
    case .lazyViewModelStateAliasCollision:
      "@LazyViewModel could not generate 'state' because this view already declares a member named 'state'; use viewModel.state or rename the existing member"
    case .viewModelRequiresMainActor:
      "@ViewModel requires the class to be explicitly @MainActor"
    case .viewModelRequiresStableState:
      "@ViewModel requires State to be held by a stored 'let state' property"
    case .viewModelRequiresVisibleState:
      "a public @ViewModel requires public nested State and public let state"
    case .invalidSourceBoundDeclaration:
      "@Bound requires one ordinary stored State property using " +
        "@Bound(source:) or @Bound(source:selecting:)"
    case .invalidSourceBoundPlacement:
      "@Bound(source:) is only supported on a direct member of @ViewModel.State"
    case .invalidSourceReactionDeclaration:
      "@Reaction requires one nonthrowing Void method parameter using " +
        "@Reaction(source:) or @Reaction(source:selecting:)"
    case .invalidSourceReactionPlacement:
      "@Reaction(source:) is only supported on a direct @ViewModel member"
    case .sourceObservationRequiresPlainState:
      "@ViewModel requires a plain State without @Observable"
    case .conditionalDeinitialiserUnsupported:
      "@ViewModel types require an unconditional deinit; put conditional logic inside its body"
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
    case .missingState: "missingState"
    case .actionWithoutHandle: "actionWithoutHandle"
    case .handleWrongLabel: "handleWrongLabel"
    case .stateClassNotFinal: "stateClassNotFinal"
    case .lazyViewModelStateAliasCollision: "lazyViewModelStateAliasCollision"
    case .viewModelRequiresMainActor: "viewModelRequiresMainActor"
    case .viewModelRequiresStableState: "viewModelRequiresStableState"
    case .viewModelRequiresVisibleState: "viewModelRequiresVisibleState"
    case .invalidSourceBoundDeclaration: "invalidSourceBoundDeclaration"
    case .invalidSourceBoundPlacement: "invalidSourceBoundPlacement"
    case .invalidSourceReactionDeclaration: "invalidSourceReactionDeclaration"
    case .invalidSourceReactionPlacement: "invalidSourceReactionPlacement"
    case .sourceObservationRequiresPlainState: "sourceObservationRequiresPlainState"
    case .conditionalDeinitialiserUnsupported: "conditionalDeinitialiserUnsupported"
    }
    return MessageID(domain: "VISOR", id: id)
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .lazyViewModelStateAliasCollision:
      .warning
    default:
      .error
    }
  }
}
