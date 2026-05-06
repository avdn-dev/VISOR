//
//  LazyViewModelMacroTests.swift
//  VISOR
//
//  Created by Anh Nguyen on 17/2/2026.
//

import SwiftSyntaxMacros
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
    assertMacroExpansionSwiftTesting(
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
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
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

  // MARK: - Access Modifier Propagation

  @Test
  func `Public struct propagates access to body only`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self)
      public struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      public struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          public var body: some View {
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

  // MARK: - Access Modifier Propagation (continued)

  @Test
  func `Private struct inherits access — no explicit modifier on generated body`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self)
      private struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      private struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
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
  func `Fileprivate struct inherits access — no explicit modifier on generated body`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self)
      fileprivate struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      fileprivate struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
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
  func `Package struct inherits access — no explicit modifier on generated body`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self)
      package struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      package struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
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
  func `Nested struct inside fileprivate type inherits enclosing access`() {
    assertMacroExpansionSwiftTesting(
      """
      fileprivate class Container {
        @LazyViewModel(MyVM.self)
        struct InnerView: View {
          var content: some View { Text("") }
        }
      }
      """,
      expandedSource: """
      fileprivate class Container {
        struct InnerView: View {
          var content: some View { Text("") }

            @Environment(\\.router) private var containerRouter

            @Environment(MyVM.Factory.self) private var factory

            @State private var _viewModel: MyVM?

            var viewModel: MyVM {
                guard let vm = _viewModel else {
                    preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
                }
                return vm
            }

            var bindableState: Bindable<MyVM.State> {
                Bindable(viewModel.state)
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
      }
      """,
      macros: testMacros)
  }

  // MARK: - Error Diagnostics

  @Test
  func `Error when applied to class`() {
    assertMacroExpansionSwiftTesting(
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
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyViewModel.self)
      struct MyView: View {
      }
      """,
      expandedSource: """
      struct MyView: View {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModel requires: var content: some View", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when no argument provided`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel
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
        DiagnosticSpec(message: "@LazyViewModel requires (ViewModel.self) argument", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when argument missing .self suffix`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyViewModel)
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
        DiagnosticSpec(message: "@LazyViewModel argument must use .self suffix (e.g., MyViewModel.self)", line: 1, column: 16, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Error when applied to enum`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyViewModel.self)
      enum NotAStruct {
      }
      """,
      expandedSource: """
      enum NotAStruct {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModel can only be applied to structs", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - ObservationPolicy

  @Test
  func `Explicit alwaysObserving produces same expansion as default`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self, observationPolicy: .alwaysObserving)
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
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
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
  func `pauseInBackground generates scenePhase environment and modified task`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self, observationPolicy: .pauseInBackground)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @Environment(\\.scenePhase) private var scenePhase

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
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
              .task(id: scenePhase != .background && _viewModel != nil) {
                  guard let vm = _viewModel, scenePhase != .background else {
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
  func `pauseWhenInactive generates scenePhase environment and modified task`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self, observationPolicy: .pauseWhenInactive)
      struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @Environment(\\.scenePhase) private var scenePhase

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
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
              .task(id: scenePhase == .active && _viewModel != nil) {
                  guard let vm = _viewModel, scenePhase == .active else {
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
  func `Public struct with pauseInBackground propagates access`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self, observationPolicy: .pauseInBackground)
      public struct MyView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      public struct MyView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var containerRouter

          @Environment(MyVM.Factory.self) private var factory

          @Environment(\\.scenePhase) private var scenePhase

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: viewModel accessed while _viewModel is nil — this should never happen because content is only rendered after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          public var body: some View {
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
              .task(id: scenePhase != .background && _viewModel != nil) {
                  guard let vm = _viewModel, scenePhase != .background else {
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
  func `Invalid observation policy emits diagnostic`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self, observationPolicy: .never)
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
        DiagnosticSpec(message: "@LazyViewModel observationPolicy must be .alwaysObserving, .pauseInBackground, or .pauseWhenInactive", line: 1, column: 27, severity: .error),
      ],
      macros: testMacros)
  }

}
#endif
