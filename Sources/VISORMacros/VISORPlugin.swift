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
    LazyViewModelMacro.self,
    PolledMacro.self,
    ReactionMacro.self,
    ViewModelMacro.self,
    StubbableDefaultMacro.self,
    StubbableMacro.self,
    SpyableMacro.self,
  ]
}
