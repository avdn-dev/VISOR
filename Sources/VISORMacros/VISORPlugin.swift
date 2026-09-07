//
//  VISORPlugin.swift
//  VISOR
//
//  Created by Anh Nguyen on 5/2/2026.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

// MARK: - VISORPlugin

@main
struct VISORPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    BoundMacro.self,
    StateBindingMacro.self,
    ViewModelStateBindingsMacro.self,
    LazyViewModelMacro.self,
    ReactionMacro.self,
    ObservationStateMacro.self,
    ObservationStateRequirementMacro.self,
    ObservationStateRequirementsMacro.self,
    ViewModelMacro.self,
    ViewModelStateMacro.self,
    ViewModelStateFieldMacro.self,
    DefaultValueMacro.self,
    GenerateTestDoublesStubMacro.self,
    GenerateTestDoublesSpyMacro.self,
  ]
}
