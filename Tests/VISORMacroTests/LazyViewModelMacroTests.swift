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
  func `Unified mode delegates observation lifetime to runtime bridge`() {
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          public var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .pauseInBackground
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
              }
          }
      }
      """,
      macros: testMacros)
  }

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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          public var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
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

            @Environment(\\.router) private var hostRouter

            @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

            @State private var _viewModel: MyVM?

            var viewModel: MyVM {
                guard let vm = _viewModel else {
                    preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
                }
                return vm
            }

            var state: MyVM.State {
                viewModel.state
            }

            var bindableState: Bindable<MyVM.State> {
                Bindable(viewModel.state)
            }

            var body: some View {
                Group {
                    if let viewModel = _viewModel {
                        VISOR._visorOwnedViewModelContent(
                            for: viewModel,
                            observationPolicy: .alwaysObserving
                        ) { _ in
                            content
                        }
                    } else {
                        Color.clear
                    }
                }
                .task {
                    if _viewModel == nil {
                        _viewModel = factory.makeViewModel(router: hostRouter)
                    }
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
              }
          }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `pauseInBackground delegates policy to runtime bridge`() {
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .pauseInBackground
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
              }
          }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `pauseWhenInactive delegates policy to runtime bridge`() {
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .pauseWhenInactive
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
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

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: MyVM.State {
              viewModel.state
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          public var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .pauseInBackground
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
              }
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - State Alias Collision

  @Test
  func `State alias collision skips alias and emits warning`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self)
      struct MyView: View {
        var state: Int = 0
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        var state: Int = 0
        var content: some View { Text("") }

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
              }
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModel could not generate 'state' because this view already declares a member named 'state'; use viewModel.state or rename the existing member", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `State alias collision with multi-binding let declaration`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(MyVM.self)
      struct MyView: View {
        let title = "", state = 0
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct MyView: View {
        let title = "", state = 0
        var content: some View { Text("") }

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<MyVM>.self) private var factory

          @State private var _viewModel: MyVM?

          var viewModel: MyVM {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: MyVM viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var bindableState: Bindable<MyVM.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: .alwaysObserving
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
              }
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@LazyViewModel could not generate 'state' because this view already declares a member named 'state'; use viewModel.state or rename the existing member", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Qualified generic type and policy expression are preserved`() {
    assertMacroExpansionSwiftTesting(
      """
      @LazyViewModel(
        Feature.GenericViewModel<LiveService>.self,
        observationPolicy: featurePolicy)
      struct FeatureView: View {
        var content: some View { Text("") }
      }
      """,
      expandedSource: """
      struct FeatureView: View {
        var content: some View { Text("") }

          @Environment(\\.router) private var hostRouter

          @Environment(VISOR.ViewModelFactory<Feature.GenericViewModel<LiveService>>.self) private var factory

          @State private var _viewModel: Feature.GenericViewModel<LiveService>?

          var viewModel: Feature.GenericViewModel<LiveService> {
              guard let vm = _viewModel else {
                  preconditionFailure("@LazyViewModel internal error: Feature.GenericViewModel<LiveService> viewModel accessed while _viewModel is nil — content should only render after initialisation.")
              }
              return vm
          }

          var state: Feature.GenericViewModel<LiveService>.State {
              viewModel.state
          }

          var bindableState: Bindable<Feature.GenericViewModel<LiveService>.State> {
              Bindable(viewModel.state)
          }

          var body: some View {
              Group {
                  if let viewModel = _viewModel {
                      VISOR._visorOwnedViewModelContent(
                          for: viewModel,
                          observationPolicy: featurePolicy
                      ) { _ in
                          content
                      }
                  } else {
                      Color.clear
                  }
              }
              .task {
                  if _viewModel == nil {
                      _viewModel = factory.makeViewModel(router: hostRouter)
                  }
              }
          }
      }
      """,
      macros: testMacros)
  }

}
#endif
