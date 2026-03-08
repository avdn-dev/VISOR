//
//  LazyViewModelsMacroTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let testMacros: [String: Macro.Type] = [
  "LazyViewModels": LazyViewModelsMacro.self,
]

// swiftlint:disable function_body_length

// MARK: - LazyViewModelsMacroTests

@Suite("LazyViewModels Macro")
struct LazyViewModelsMacroTests {

  @Test
  func `Inferred factories`() {
    let input = """
      @LazyViewModels(
        AViewModel.self,
        BViewModel.self)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """

    let expanded = """
      struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(AViewModel.Factory.self) private var aViewModelFactory

          @State private var _aViewModel: AViewModel?

          var aViewModel: AViewModel {
              _aViewModel!
          }

          @Environment(BViewModel.Factory.self) private var bViewModelFactory

          @State private var _bViewModel: BViewModel?

          var bViewModel: BViewModel {
              _bViewModel!
          }

          var body: some View {
              Group {
                  if _aViewModel != nil && _bViewModel != nil {
                      content
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _aViewModel == nil || _bViewModel == nil {
              _aViewModel = aViewModelFactory.makeViewModel(router: containerRouter)
              _bViewModel = bViewModelFactory.makeViewModel(router: containerRouter)
                  }
              }
                  .task(id: _aViewModel != nil) {
                      guard let vm = _aViewModel else {
                          return
                      }
                      await vm.startObserving()
                  }
                  .task(id: _bViewModel != nil) {
                      guard let vm = _bViewModel else {
                          return
                      }
                      await vm.startObserving()
                  }
          }
      }
      """

    assertMacroExpansion(input, expandedSource: expanded, macros: testMacros)
  }

  // MARK: - Error Diagnostics

  @Test
  func `Error when applied to class`() {
    assertMacroExpansion(
      """
      @LazyViewModels(AViewModel.self)
      class NotAStruct: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      class NotAStruct: View {
        var content: some View { Text("") }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModels can only be applied to structs", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when missing content property`() {
    assertMacroExpansion(
      """
      @LazyViewModels(AViewModel.self)
      struct MyView: View {
      }
      """,
      expandedSource: """
      struct MyView: View {

          @Environment(\\.router) private var containerRouter

          @Environment(AViewModel.Factory.self) private var aViewModelFactory

          @State private var _aViewModel: AViewModel?

          var aViewModel: AViewModel {
              _aViewModel!
          }

          var body: some View {
              Group {
                  if _aViewModel != nil {
                      content
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _aViewModel == nil {
                      _aViewModel = aViewModelFactory.makeViewModel(router: containerRouter)
                  }
              }
                  .task(id: _aViewModel != nil) {
                      guard let vm = _aViewModel else {
                          return
                      }
                      await vm.startObserving()
                  }
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModels with a single ViewModel; use @LazyViewModel instead", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@LazyViewModels requires: var content: some View", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning for unrecognized argument format`() {
    assertMacroExpansion(
      """
      @LazyViewModels(42)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModels: unrecognized argument (expected ViewModel.self)", line: 1, column: 17, severity: .warning),
        DiagnosticSpec(message: "@LazyViewModels requires (ViewModel.self) argument", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Single ViewModel with content emits warning but expands correctly`() {
    assertMacroExpansion(
      """
      @LazyViewModels(AViewModel.self)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(AViewModel.Factory.self) private var aViewModelFactory

          @State private var _aViewModel: AViewModel?

          var aViewModel: AViewModel {
              _aViewModel!
          }

          var body: some View {
              Group {
                  if _aViewModel != nil {
                      content
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _aViewModel == nil {
                      _aViewModel = aViewModelFactory.makeViewModel(router: containerRouter)
                  }
              }
                  .task(id: _aViewModel != nil) {
                      guard let vm = _aViewModel else {
                          return
                      }
                      await vm.startObserving()
                  }
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModels with a single ViewModel; use @LazyViewModel instead", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when no arguments provided`() {
    assertMacroExpansion(
      """
      @LazyViewModels()
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModels requires (ViewModel.self) argument", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when applied to enum`() {
    assertMacroExpansion(
      """
      @LazyViewModels(AViewModel.self)
      enum NotAStruct {
      }
      """,
      expandedSource: """
      enum NotAStruct {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModels can only be applied to structs", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - Expansion Variants

  @Test
  func `Three ViewModels expansion`() {
    let input = """
      @LazyViewModels(
        AViewModel.self,
        BViewModel.self,
        CViewModel.self)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """

    let expanded = """
      struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(AViewModel.Factory.self) private var aViewModelFactory

          @State private var _aViewModel: AViewModel?

          var aViewModel: AViewModel {
              _aViewModel!
          }

          @Environment(BViewModel.Factory.self) private var bViewModelFactory

          @State private var _bViewModel: BViewModel?

          var bViewModel: BViewModel {
              _bViewModel!
          }

          @Environment(CViewModel.Factory.self) private var cViewModelFactory

          @State private var _cViewModel: CViewModel?

          var cViewModel: CViewModel {
              _cViewModel!
          }

          var body: some View {
              Group {
                  if _aViewModel != nil && _bViewModel != nil && _cViewModel != nil {
                      content
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _aViewModel == nil || _bViewModel == nil || _cViewModel == nil {
              _aViewModel = aViewModelFactory.makeViewModel(router: containerRouter)
              _bViewModel = bViewModelFactory.makeViewModel(router: containerRouter)
              _cViewModel = cViewModelFactory.makeViewModel(router: containerRouter)
                  }
              }
                  .task(id: _aViewModel != nil) {
                      guard let vm = _aViewModel else {
                          return
                      }
                      await vm.startObserving()
                  }
                  .task(id: _bViewModel != nil) {
                      guard let vm = _bViewModel else {
                          return
                      }
                      await vm.startObserving()
                  }
                  .task(id: _cViewModel != nil) {
                      guard let vm = _cViewModel else {
                          return
                      }
                      await vm.startObserving()
                  }
          }
      }
      """

    assertMacroExpansion(input, expandedSource: expanded, macros: testMacros)
  }

}

// swiftlint:enable function_body_length
#endif
