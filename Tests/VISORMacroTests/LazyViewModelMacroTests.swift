//
//  LazyViewModelMacroTests.swift
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
  "LazyViewModel": LazyViewModelMacro.self,
]

// MARK: - LazyViewModelMacroTests

@Suite("LazyViewModel Macro")
struct LazyViewModelMacroTests {

  @Test
  func `Content mode generates correct expansion`() {
    assertMacroExpansion(
      """
      @LazyViewModel(MyVM.self)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              _viewModel!
          }

          var body: some View {
              Group {
                  if _viewModel != nil {
                      content
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: containerRouter)
                  }
              }
              .task(id: _viewModel != nil) {
                  guard let vm = _viewModel else {
                      return
                  }
                  await vm.startObserving()
              }
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Error Diagnostics

  @Test
  func `Error when applied to class`() {
    assertMacroExpansion(
      """
      @LazyViewModel(MyViewModel.self)
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
        DiagnosticSpec(message: "@LazyViewModel can only be applied to structs", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when missing content`() {
    assertMacroExpansion(
      """
      @LazyViewModel(MyViewModel.self)
      struct MyView: View {
      }
      """,
      expandedSource: """
      struct MyView: View {

          @Environment(\\.router) private var containerRouter

          @Environment(MyViewModel.Factory.self) private var factory

          @State private var _viewModel: MyViewModel?

          var viewModel: MyViewModel {
              _viewModel!
          }

          var body: some View {
              Group {
                  if _viewModel != nil {
                      content
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: containerRouter)
                  }
              }
              .task(id: _viewModel != nil) {
                  guard let vm = _viewModel else {
                      return
                  }
                  await vm.startObserving()
              }
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModels requires: var content: some View", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Short VM name derives correct factory`() {
    assertMacroExpansion(
      """
      @LazyViewModel(MyVM.self)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              _viewModel!
          }

          var body: some View {
              Group {
                  if _viewModel != nil {
                      content
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: containerRouter)
                  }
              }
              .task(id: _viewModel != nil) {
                  guard let vm = _viewModel else {
                      return
                  }
                  await vm.startObserving()
              }
          }
      }
      """,
      macros: testMacros)
  }
}
#endif
