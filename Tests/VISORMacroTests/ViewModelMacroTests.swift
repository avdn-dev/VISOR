//
//  ViewModelMacroTests.swift
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
  "Bound": BoundMacro.self,
  "Polled": PolledMacro.self,
  "Reaction": ReactionMacro.self,
  "ViewModel": ViewModelMacro.self,
]

private nonisolated(unsafe) let observableWarning = DiagnosticSpec(
  message: "@ViewModel requires @Observable on the class to enable observation tracking",
  line: 1, column: 1, severity: .warning
)

// MARK: - ViewModelMacroTests

@Suite("ViewModel Macro")
struct ViewModelMacroTests {

  // MARK: - Init Generation

  @Test
  func `Generates memberwise init and Factory typealias`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        var state = State()
        private let service: MyService
        private let store: DataStore
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        var state = State()
        private let service: MyService
        private let store: DataStore

          init(service: MyService, store: DataStore) {
              self.service = service
              self.store = store
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Skips init when already exists`() {
    assertMacroExpansion(
      """
      @ViewModel
      class MyViewModel: NSObject {
        struct State: Equatable {}
        var state = State()
        init(service: MyService) {
          self.service = service
          super.init()
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      class MyViewModel: NSObject {
        struct State: Equatable {}
        var state = State()
        init(service: MyService) {
          self.service = service
          super.init()
        }
        private let service: MyService

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  // MARK: - Property Filtering

  @Test
  func `Skips var properties`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        var mutableProp: String = ""
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        var mutableProp: String = ""
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Skips let with default value`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let defaulted: String = "hello"
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let defaulted: String = "hello"
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  // MARK: - No Dependencies

  @Test
  func `No dependencies produces Factory typealias only`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class SimpleViewModel {
        struct State: Equatable {}
        var state = State()
      }
      """,
      expandedSource: """
      final class SimpleViewModel {
        struct State: Equatable {}
        var state = State()

          typealias Factory = ViewModelFactory<SimpleViewModel>
      }

      extension SimpleViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  // MARK: - @Observable Present (no warning)

  @Test
  func `No warning with @Observable`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  // MARK: - Access Modifier Propagation

  @Test
  func `Public class propagates access to init and Factory`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      public final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      public final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let service: MyService

          public init(service: MyService) {
              self.service = service
          }

          public typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Package class propagates access to init and Factory`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      package final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      package final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let service: MyService

          package init(service: MyService) {
              self.service = service
          }

          package typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Public class with @Bound propagates access to protocol requirements`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      public final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.service.isLoading) var isLoading: Bool
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      public final class MyViewModel {
        struct State: Equatable {
          var isLoading: Bool
        }
        private let service: MyService

          private var _state: State

          public var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          public init(service: MyService) {
              self.service = service
              self._state = State(isLoading: service.isLoading)
          }

          public typealias Factory = ViewModelFactory<MyViewModel>

          func observeIsLoading() async {
              for await value in VISOR.valuesOf({ self.service.isLoading }) {
                  self.updateState(\\.isLoading, to: value)
              }
          }

          public func startObserving() async {
              await observeIsLoading()
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  // MARK: - Error Diagnostics

  @Test
  func `Error when applied to struct`() {
    assertMacroExpansion(
      """
      @ViewModel
      struct NotAClass {
        struct State: Equatable {}
        var state = State()
      }
      """,
      expandedSource: """
      struct NotAClass {
        struct State: Equatable {}
        var state = State()
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel can only be applied to classes", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - @Bound inside State

  @Test
  func `@Bound inside State generates updateState observe method`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.permissionService.isCameraDenied) var isCameraDenied: Bool
        }
        private let permissionService: PermissionService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var isCameraDenied: Bool
        }
        private let permissionService: PermissionService

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(permissionService: PermissionService) {
              self.permissionService = permissionService
              self._state = State(isCameraDenied: permissionService.isCameraDenied)
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeIsCameraDenied() async {
              for await value in VISOR.valuesOf({ self.permissionService.isCameraDenied }) {
                  self.updateState(\\.isCameraDenied, to: value)
              }
          }

          func startObserving() async {
              await observeIsCameraDenied()
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Multiple @Bound inside State generates withDiscardingTaskGroup`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.connectionService.isAuthenticated) var isAuthenticated: Bool
          @Bound(\\MyViewModel.connectionService.isLoading) var isLoading: Bool
          @Bound(\\MyViewModel.connectionService.connections) var connections: [Connection]
        }
        private let connectionService: ConnectionService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var isAuthenticated: Bool
          var isLoading: Bool
          var connections: [Connection]
        }
        private let connectionService: ConnectionService

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(connectionService: ConnectionService) {
              self.connectionService = connectionService
              self._state = State(isAuthenticated: connectionService.isAuthenticated, isLoading: connectionService.isLoading, connections: connectionService.connections)
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeIsAuthenticated() async {
              for await value in VISOR.valuesOf({ self.connectionService.isAuthenticated }) {
                  self.updateState(\\.isAuthenticated, to: value)
              }
          }

          func observeIsLoading() async {
              for await value in VISOR.valuesOf({ self.connectionService.isLoading }) {
                  self.updateState(\\.isLoading, to: value)
              }
          }

          func observeConnections() async {
              for await value in VISOR.valuesOf({ self.connectionService.connections }) {
                  self.updateState(\\.connections, to: value)
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeIsAuthenticated() }
                  group.addTask { await self.observeIsLoading() }
                  group.addTask { await self.observeConnections() }
              }
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Multiple different dependency sources in State`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.widgetService.selectedId) var selectedId: String
          @Bound(\\MyViewModel.connectionService.connections) var connections: [Connection]
          @Bound(\\MyViewModel.sharingService.isSending) var isSending: Bool
        }
        private let widgetService: WidgetService
        private let connectionService: ConnectionService
        private let sharingService: SharingService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var selectedId: String
          var connections: [Connection]
          var isSending: Bool
        }
        private let widgetService: WidgetService
        private let connectionService: ConnectionService
        private let sharingService: SharingService

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(widgetService: WidgetService, connectionService: ConnectionService, sharingService: SharingService) {
              self.widgetService = widgetService
              self.connectionService = connectionService
              self.sharingService = sharingService
              self._state = State(selectedId: widgetService.selectedId, connections: connectionService.connections, isSending: sharingService.isSending)
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeSelectedId() async {
              for await value in VISOR.valuesOf({ self.widgetService.selectedId }) {
                  self.updateState(\\.selectedId, to: value)
              }
          }

          func observeConnections() async {
              for await value in VISOR.valuesOf({ self.connectionService.connections }) {
                  self.updateState(\\.connections, to: value)
              }
          }

          func observeIsSending() async {
              for await value in VISOR.valuesOf({ self.sharingService.isSending }) {
                  self.updateState(\\.isSending, to: value)
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeSelectedId() }
                  group.addTask { await self.observeConnections() }
                  group.addTask { await self.observeIsSending() }
              }
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `@Bound inside State with invalid dependency emits error`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.typoService.value) var value = false
        }
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var value = false
        }
        var state = State()
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: #"@Bound(\.typoService) on 'value': no stored 'let typoService' found on this class"#, line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `@Bound inside State with malformed key path emits warning`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound("invalid") var value = false
        }
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var value = false
        }
        var state = State()
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: #"@Bound on 'value': expected key path like \MyViewModel.dependency.property"#, line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `@Bound with single-component key path emits warning`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.service) var value = false
        }
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var value = false
        }
        var state = State()
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: #"@Bound on 'value': expected key path like \MyViewModel.dependency.property"#, line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `@Bound on let inside State emits warning`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.service.value) let value = false
        }
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          let value = false
        }
        var state = State()
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Bound on 'value': use 'var' instead of 'let' — bound properties must be mutable", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - @Bound on class-level var (BoundMacro is a no-op; @ViewModel ignores it)

  @Test
  func `@Bound on class-level var is ignored`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        @Bound(\\MyViewModel.service.value) var value = false
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        var value = false
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - State/Action diagnostics

  @Test
  func `Missing State struct emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        private let service: MyService
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires a nested 'struct State: Equatable { }'", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `State struct without state property generates it`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        enum Action { case refresh }
        func handle(_ action: Action) async {}
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        enum Action { case refresh }
        func handle(_ action: Action) async {}
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          var state = State()
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `var state with non-State type still generates state property`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        var state: Int = 0
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        var state: Int = 0
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          var state = State()
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `var state without initializer emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        var state: State
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {
          var count = 0
        }
        var state: State
        private let service: MyService
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel: 'var state' must have a default value (e.g., 'var state = State()')", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `State without defaults and no var state emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          var name: String
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {
          var name: String
        }
        private let service: MyService
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel: all State properties must have default values when 'var state' is not declared (auto-generates 'var state = State()')", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Action enum without handle emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action)' method found", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Action enum with async handle emits no diagnostic`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(_ action: Action) async {}
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(_ action: Action) async {}
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Action enum with non-async handle emits no warning`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(_ action: Action) {}
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(_ action: Action) {}
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `No Action no handle emits no diagnostic`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class SimpleViewModel {
        struct State: Equatable {}
        var state = State()
      }
      """,
      expandedSource: """
      @Observable
      final class SimpleViewModel {
        struct State: Equatable {}
        var state = State()

          typealias Factory = ViewModelFactory<SimpleViewModel>
      }

      extension SimpleViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Action enum with wrong handle parameter type emits diagnostic`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(_ action: String) async {}
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(_ action: String) async {}
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action)' method found", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Action enum with wrong handle label emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(action: Action) async {}
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {}
        enum Action { case refresh }
        var state = State()
        func handle(action: Action) async {}
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel: 'handle(action:)' should use an underscore label: 'handle(_ action: Action)'", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - @Reaction Generation

  @Test
  func `Sync @Reaction generates for-await loop`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        func handleDeepLink(destination: Destination?) { }
        private let router: DeepLinkRouter

          init(router: DeepLinkRouter) {
              self.router = router
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeHandleDeepLink() async {
              for await destination in VISOR.valuesOf({ self.router.pendingDestination }) {
                  self.handleDeepLink(destination: destination)
              }
          }

          func startObserving() async {
              await observeHandleDeepLink()
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Async @Reaction generates latestValuesOf call`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        @Reaction(\\.uploadService.uploadState)
        func handleUploadState(state: UploadState) async { }
        private let uploadService: UploadService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        func handleUploadState(state: UploadState) async { }
        private let uploadService: UploadService

          init(uploadService: UploadService) {
              self.uploadService = uploadService
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeHandleUploadState() async {
              await VISOR.latestValuesOf({ self.uploadService.uploadState }) { state in
                  await self.handleUploadState(state: state)
              }
          }

          func startObserving() async {
              await observeHandleUploadState()
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Mixed @Bound in State and @Reaction generates combined startObserving`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Bound(\\MyViewModel.service.isLoading) var isLoading: Bool
        }
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        private let service: MyService
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var isLoading: Bool
        }
        func handleDeepLink(destination: Destination?) { }
        private let service: MyService
        private let router: DeepLinkRouter

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(service: MyService, router: DeepLinkRouter) {
              self.service = service
              self.router = router
              self._state = State(isLoading: service.isLoading)
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeIsLoading() async {
              for await value in VISOR.valuesOf({ self.service.isLoading }) {
                  self.updateState(\\.isLoading, to: value)
              }
          }

          func observeHandleDeepLink() async {
              for await destination in VISOR.valuesOf({ self.router.pendingDestination }) {
                  self.handleDeepLink(destination: destination)
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeIsLoading() }
                  group.addTask { await self.observeHandleDeepLink() }
              }
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `@Reaction with zero params emits diagnostic`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink() { }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        func handleDeepLink() { }
        private let router: DeepLinkRouter

          init(router: DeepLinkRouter) {
              self.router = router
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Reaction on 'handleDeepLink': method must have exactly one parameter", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - @Reaction with malformed key path

  @Test
  func `@Reaction with non-key-path argument emits diagnostic`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        @Reaction("bogus")
        func handleChange(value: String) { }
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        func handleChange(value: String) { }
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        observableWarning,
        DiagnosticSpec(message: #"@Reaction on 'handleChange': expected key path argument like \.dependency.property"#, line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - Router Type Detection

  @Test
  func `Router property included in init`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let router: Router<AppScene>
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let router: Router<AppScene>
        private let service: MyService

          init(router: Router<AppScene>, service: MyService) {
              self.router = router
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  // MARK: - Existential `any` Protocol Types

  @Test
  func `Existential any types preserved in init`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let router: Router<AppScene>
        private let sessionInteractor: any SessionInteractor
        private let distractionInteractor: any DistractionInteractor
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let router: Router<AppScene>
        private let sessionInteractor: any SessionInteractor
        private let distractionInteractor: any DistractionInteractor

          init(router: Router<AppScene>, sessionInteractor: any SessionInteractor, distractionInteractor: any DistractionInteractor) {
              self.router = router
              self.sessionInteractor = sessionInteractor
              self.distractionInteractor = distractionInteractor
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  // MARK: - Manual startObserving missing Bound observe method

  @Test
  func `Manual startObserving missing @Bound observe method emits warning`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class ItemsViewModel {
        struct State: Equatable {
          @Bound(\\ItemsViewModel.service.items) var items: [String]
        }
        func startObserving() async {
          // forgot to call observeItems
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class ItemsViewModel {
        struct State: Equatable {
          var items: [String]
        }
        func startObserving() async {
          // forgot to call observeItems
        }
        private let service: MyService

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(service: MyService) {
              self.service = service
              self._state = State(items: service.items)
          }

          typealias Factory = ViewModelFactory<ItemsViewModel>

          func observeItems() async {
              for await value in VISOR.valuesOf({ self.service.items }) {
                  self.updateState(\\.items, to: value)
              }
          }
      }

      extension ItemsViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "startObserving() does not call observeItems(); state derivation will not run", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Multi-binding let declaration captures all properties`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let serviceA: ServiceA, serviceB: ServiceB
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        private let serviceA: ServiceA, serviceB: ServiceB

          init(serviceA: ServiceA, serviceB: ServiceB) {
              self.serviceA = serviceA
              self.serviceB = serviceB
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  // MARK: - Error when applied to enum

  @Test
  func `Error when applied to enum`() {
    assertMacroExpansion(
      """
      @ViewModel
      enum NotAClass {
        case a
      }
      """,
      expandedSource: """
      enum NotAClass {
        case a
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel can only be applied to classes", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - @Reaction with two parameters

  @Test
  func `@Reaction with two parameters emits diagnostic`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?, source: String) { }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        func handleDeepLink(destination: Destination?, source: String) { }
        private let router: DeepLinkRouter

          init(router: DeepLinkRouter) {
              self.router = router
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        observableWarning,
        DiagnosticSpec(message: "@Reaction on 'handleDeepLink': method must have exactly one parameter", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - Manual startObserving calling correct observe methods emits no diagnostic

  @Test
  func `Manual startObserving calling observe methods emits no diagnostic`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class ItemsViewModel {
        struct State: Equatable {
          @Bound(\\ItemsViewModel.service.items) var items: [String]
        }
        func startObserving() async {
          await observeItems()
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class ItemsViewModel {
        struct State: Equatable {
          var items: [String]
        }
        func startObserving() async {
          await observeItems()
        }
        private let service: MyService

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(service: MyService) {
              self.service = service
              self._state = State(items: service.items)
          }

          typealias Factory = ViewModelFactory<ItemsViewModel>

          func observeItems() async {
              for await value in VISOR.valuesOf({ self.service.items }) {
                  self.updateState(\\.items, to: value)
              }
          }
      }

      extension ItemsViewModel: @MainActor ViewModel {
      }
      """,
      macros: testMacros)
  }

  // MARK: - @Polled inside State

  @Test
  func `Single @Polled generates inlined poll loop`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class DashboardVM {
        struct State: Equatable {
          @Polled(\\DashboardVM.monitor.level, every: .seconds(30)) var level: Float
        }
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      final class DashboardVM {
        struct State: Equatable {
          var level: Float
        }
        private let monitor: BatteryMonitor

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(monitor: BatteryMonitor) {
              self.monitor = monitor
              self._state = State(level: monitor.level)
          }

          typealias Factory = ViewModelFactory<DashboardVM>

          func observeLevel() async {
              self.updateState(\\.level, to: self.monitor.level)
              do {
                  while !Task.isCancelled {
                      try await Task.sleep(for: .seconds(30))
                      self.updateState(\\.level, to: self.monitor.level)
                  }
              } catch {
              }
          }

          func startObserving() async {
              await observeLevel()
          }
      }

      extension DashboardVM: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Multiple @Polled generates task group startObserving`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class SensorVM {
        struct State: Equatable {
          @Polled(\\SensorVM.monitor.level, every: .seconds(30)) var level: Float
          @Polled(\\SensorVM.monitor.temperature, every: .seconds(10)) var temperature: Double
        }
        private let monitor: SensorMonitor
      }
      """,
      expandedSource: """
      final class SensorVM {
        struct State: Equatable {
          var level: Float
          var temperature: Double
        }
        private let monitor: SensorMonitor

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(monitor: SensorMonitor) {
              self.monitor = monitor
              self._state = State(level: monitor.level, temperature: monitor.temperature)
          }

          typealias Factory = ViewModelFactory<SensorVM>

          func observeLevel() async {
              self.updateState(\\.level, to: self.monitor.level)
              do {
                  while !Task.isCancelled {
                      try await Task.sleep(for: .seconds(30))
                      self.updateState(\\.level, to: self.monitor.level)
                  }
              } catch {
              }
          }

          func observeTemperature() async {
              self.updateState(\\.temperature, to: self.monitor.temperature)
              do {
                  while !Task.isCancelled {
                      try await Task.sleep(for: .seconds(10))
                      self.updateState(\\.temperature, to: self.monitor.temperature)
                  }
              } catch {
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeLevel() }
                  group.addTask { await self.observeTemperature() }
              }
          }
      }

      extension SensorVM: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Mixed @Bound and @Polled preserves declaration order in init`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MixedVM {
        struct State: Equatable {
          @Bound(\\MixedVM.service.name) var name: String
          @Polled(\\MixedVM.monitor.level, every: .seconds(5)) var level: Float
          @Bound(\\MixedVM.service.count) var count: Int
        }
        private let service: MyService
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      final class MixedVM {
        struct State: Equatable {
          var name: String
          var level: Float
          var count: Int
        }
        private let service: MyService
        private let monitor: BatteryMonitor

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(service: MyService, monitor: BatteryMonitor) {
              self.service = service
              self.monitor = monitor
              self._state = State(name: service.name, level: monitor.level, count: service.count)
          }

          typealias Factory = ViewModelFactory<MixedVM>

          func observeName() async {
              for await value in VISOR.valuesOf({ self.service.name }) {
                  self.updateState(\\.name, to: value)
              }
          }

          func observeCount() async {
              for await value in VISOR.valuesOf({ self.service.count }) {
                  self.updateState(\\.count, to: value)
              }
          }

          func observeLevel() async {
              self.updateState(\\.level, to: self.monitor.level)
              do {
                  while !Task.isCancelled {
                      try await Task.sleep(for: .seconds(5))
                      self.updateState(\\.level, to: self.monitor.level)
                  }
              } catch {
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeName() }
                  group.addTask { await self.observeCount() }
                  group.addTask { await self.observeLevel() }
              }
          }
      }

      extension MixedVM: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `@Polled with invalid dependency emits error`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Polled(\\MyViewModel.typoMonitor.level, every: .seconds(5)) var level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor

          init(monitor: BatteryMonitor) {
              self.monitor = monitor
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: #"@Polled(\.typoMonitor) on 'level': no stored 'let typoMonitor' found on this class"#, line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `@Polled with malformed key path emits warning`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Polled("invalid", every: .seconds(5)) var level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor

          init(monitor: BatteryMonitor) {
              self.monitor = monitor
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: #"@Polled on 'level': expected key path like \MyViewModel.dependency.property"#, line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `@Polled on let emits warning`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Polled(\\MyViewModel.monitor.level, every: .seconds(5)) let level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          let level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor

          init(monitor: BatteryMonitor) {
              self.monitor = monitor
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Polled on 'level': use 'var' instead of 'let' — polled properties must be mutable", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `@Polled with default value emits error`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Polled(\\MyViewModel.monitor.level, every: .seconds(5)) var level: Float = 0.5
        }
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var level: Float = 0.5
        }
        private let monitor: BatteryMonitor

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(monitor: BatteryMonitor) {
              self.monitor = monitor
              self._state = State(level: monitor.level)
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeLevel() async {
              self.updateState(\\.level, to: self.monitor.level)
              do {
                  while !Task.isCancelled {
                      try await Task.sleep(for: .seconds(5))
                      self.updateState(\\.level, to: self.monitor.level)
                  }
              } catch {
              }
          }

          func startObserving() async {
              await observeLevel()
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Polled on 'level': remove the default value — state is initialized from the service", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `@Polled missing interval emits error`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Polled(\\MyViewModel.monitor.level) var level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var level = 0.0
        }
        var state = State()
        private let monitor: BatteryMonitor

          init(monitor: BatteryMonitor) {
              self.monitor = monitor
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Polled on 'level': missing 'every:' interval parameter", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Manual startObserving warns for missing @Polled observe call`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {
          @Polled(\\MyViewModel.monitor.level, every: .seconds(5)) var level: Float
        }
        private let monitor: BatteryMonitor

        func startObserving() async {
          // Forgot to call observeLevel()
        }
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var level: Float
        }
        private let monitor: BatteryMonitor

        func startObserving() async {
          // Forgot to call observeLevel()
        }

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(monitor: BatteryMonitor) {
              self.monitor = monitor
              self._state = State(level: monitor.level)
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeLevel() async {
              self.updateState(\\.level, to: self.monitor.level)
              do {
                  while !Task.isCancelled {
                      try await Task.sleep(for: .seconds(5))
                      self.updateState(\\.level, to: self.monitor.level)
                  }
              } catch {
              }
          }
      }

      extension MyViewModel: @MainActor ViewModel {
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "startObserving() does not call observeLevel(); state derivation will not run", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - @Bound with throttled:

  @Test
  func `@Bound with throttled generates sleep after updateState`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class HeadVM {
        struct State: Equatable {
          @Bound(\\HeadVM.tracker.posture, throttled: .seconds(0.125)) var posture: Posture
        }
        private let tracker: HeadTracker
      }
      """,
      expandedSource: """
      final class HeadVM {
        struct State: Equatable {
          var posture: Posture
        }
        private let tracker: HeadTracker

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(tracker: HeadTracker) {
              self.tracker = tracker
              self._state = State(posture: tracker.posture)
          }

          typealias Factory = ViewModelFactory<HeadVM>

          func observePosture() async {
              for await value in VISOR.valuesOf({ self.tracker.posture }) {
                  self.updateState(\\.posture, to: value)
                  do {
                      try await Task.sleep(for: .seconds(0.125))
                  } catch {
                  }
              }
          }

          func startObserving() async {
              await observePosture()
          }
      }

      extension HeadVM: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Sync @Reaction with throttled generates sleep after method call`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class AudioVM {
        struct State: Equatable {}
        var state = State()
        @Reaction(\\.recorder.audioLevel, throttled: .seconds(0.1))
        func handleLevel(level: Float) { }
        private let recorder: AudioRecorder
      }
      """,
      expandedSource: """
      final class AudioVM {
        struct State: Equatable {}
        var state = State()
        func handleLevel(level: Float) { }
        private let recorder: AudioRecorder

          init(recorder: AudioRecorder) {
              self.recorder = recorder
          }

          typealias Factory = ViewModelFactory<AudioVM>

          func observeHandleLevel() async {
              for await level in VISOR.valuesOf({ self.recorder.audioLevel }) {
                  self.handleLevel(level: level)
                  do {
                      try await Task.sleep(for: .seconds(0.1))
                  } catch {
                  }
              }
          }

          func startObserving() async {
              await observeHandleLevel()
          }
      }

      extension AudioVM: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Async @Reaction with throttled generates for-await with sleep instead of latestValuesOf`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class UploadVM {
        struct State: Equatable {}
        var state = State()
        @Reaction(\\.uploadService.uploadState, throttled: .seconds(1))
        func handleUploadState(state: UploadState) async { }
        private let uploadService: UploadService
      }
      """,
      expandedSource: """
      final class UploadVM {
        struct State: Equatable {}
        var state = State()
        func handleUploadState(state: UploadState) async { }
        private let uploadService: UploadService

          init(uploadService: UploadService) {
              self.uploadService = uploadService
          }

          typealias Factory = ViewModelFactory<UploadVM>

          func observeHandleUploadState() async {
              for await state in VISOR.valuesOf({ self.uploadService.uploadState }) {
                  await self.handleUploadState(state: state)
                  do {
                      try await Task.sleep(for: .seconds(1))
                  } catch {
                  }
              }
          }

          func startObserving() async {
              await observeHandleUploadState()
          }
      }

      extension UploadVM: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

  @Test
  func `Mixed throttled and unthrottled @Bound in same State`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MixedThrottleVM {
        struct State: Equatable {
          @Bound(\\MixedThrottleVM.service.name) var name: String
          @Bound(\\MixedThrottleVM.tracker.posture, throttled: .seconds(0.125)) var posture: Posture
        }
        private let service: MyService
        private let tracker: HeadTracker
      }
      """,
      expandedSource: """
      final class MixedThrottleVM {
        struct State: Equatable {
          var name: String
          var posture: Posture
        }
        private let service: MyService
        private let tracker: HeadTracker

          private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          init(service: MyService, tracker: HeadTracker) {
              self.service = service
              self.tracker = tracker
              self._state = State(name: service.name, posture: tracker.posture)
          }

          typealias Factory = ViewModelFactory<MixedThrottleVM>

          func observeName() async {
              for await value in VISOR.valuesOf({ self.service.name }) {
                  self.updateState(\\.name, to: value)
              }
          }

          func observePosture() async {
              for await value in VISOR.valuesOf({ self.tracker.posture }) {
                  self.updateState(\\.posture, to: value)
                  do {
                      try await Task.sleep(for: .seconds(0.125))
                  } catch {
                  }
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeName() }
                  group.addTask { await self.observePosture() }
              }
          }
      }

      extension MixedThrottleVM: @MainActor ViewModel {
      }
      """,
      diagnostics: [observableWarning],
      macros: testMacros)
  }

}
#endif
