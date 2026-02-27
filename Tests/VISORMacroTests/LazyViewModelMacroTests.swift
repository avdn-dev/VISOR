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
  func `Inferred factory`() {
    assertMacroExpansion(
      """
      @LazyViewModel(MyViewModel.self)
      struct MyView: View {
        func loadedView(state: MyViewModel.State) -> some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        func loadedView(state: MyViewModel.State) -> some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyViewModel.Factory.self) private var factory

          @State private var _viewModel: MyViewModel?

          var viewModel: MyViewModel {
              _viewModel!
          }

          func makeViewModel() -> MyViewModel {
              factory.makeViewModel(router: containerRouter)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      switch viewModel.state {
                      case .loading:
                          loadingView
                      case .empty:
                          emptyView
                      case .loaded(let state):
                          loadedView(state: state)
                      case .error(let message):
                          errorView(message: message)
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = makeViewModel()
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

      extension MyView: @MainActor LazyViewModelView {
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
        func loadedView(state: Int) -> some View { Text("") }
      }
      """,
      expandedSource: """
      class NotAStruct: View {
        func loadedView(state: Int) -> some View { Text("") }
      }

      extension NotAStruct: @MainActor LazyViewModelView {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModel can only be applied to structs", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when missing loadedView`() {
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

          func makeViewModel() -> MyViewModel {
              factory.makeViewModel(router: containerRouter)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      switch viewModel.state {
                      case .loading:
                          loadingView
                      case .empty:
                          emptyView
                      case .loaded(let state):
                          loadedView(state: state)
                      case .error(let message):
                          errorView(message: message)
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = makeViewModel()
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

      extension MyView: @MainActor LazyViewModelView {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModel requires either: func loadedView(state:) -> some View or var content: some View", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

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

  @Test
  func `Error when both loadedView and content provided`() {
    assertMacroExpansion(
      """
      @LazyViewModel(MyVM.self)
      struct MyView: View {
        func loadedView(state: MyVM.State) -> some View { Text("") }
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        func loadedView(state: MyVM.State) -> some View { Text("") }
        var content: some View { Text("") }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModel: provide either loadedView(state:) or content, not both", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Short VM name derives correct factory`() {
    assertMacroExpansion(
      """
      @LazyViewModel(MyVM.self)
      struct MyView: View {
        func loadedView(state: MyVM.State) -> some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        func loadedView(state: MyVM.State) -> some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              _viewModel!
          }

          func makeViewModel() -> MyVM {
              factory.makeViewModel(router: containerRouter)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      switch viewModel.state {
                      case .loading:
                          loadingView
                      case .empty:
                          emptyView
                      case .loaded(let state):
                          loadedView(state: state)
                      case .error(let message):
                          errorView(message: message)
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = makeViewModel()
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

      extension MyView: @MainActor LazyViewModelView {
      }
      """,
      macros: testMacros)
  }
}
#endif
