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
          @Bound(\\.permissionService) var isCameraDenied = false
        }
        var state = State()
        private let permissionService: PermissionService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var isCameraDenied = false
        }
        var state = State()
        private let permissionService: PermissionService

          init(permissionService: PermissionService) {
              self.permissionService = permissionService
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
          @Bound(\\.connectionService) var isAuthenticated = false
          @Bound(\\.connectionService) var isLoading = false
          @Bound(\\.connectionService) var connections: [Connection] = []
        }
        var state = State()
        private let connectionService: ConnectionService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var isAuthenticated = false
          var isLoading = false
          var connections: [Connection] = []
        }
        var state = State()
        private let connectionService: ConnectionService

          init(connectionService: ConnectionService) {
              self.connectionService = connectionService
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
          @Bound(\\.widgetService) var selectedId = ""
          @Bound(\\.connectionService) var connections: [Connection] = []
          @Bound(\\.sharingService) var isSending = false
        }
        var state = State()
        private let widgetService: WidgetService
        private let connectionService: ConnectionService
        private let sharingService: SharingService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var selectedId = ""
          var connections: [Connection] = []
          var isSending = false
        }
        var state = State()
        private let widgetService: WidgetService
        private let connectionService: ConnectionService
        private let sharingService: SharingService

          init(widgetService: WidgetService, connectionService: ConnectionService, sharingService: SharingService) {
              self.widgetService = widgetService
              self.connectionService = connectionService
              self.sharingService = sharingService
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
          @Bound(\\.typoService) var value = false
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
        DiagnosticSpec(message: #"@Bound on 'value': expected key path argument like \ClassName.dependencyName"#, line: 1, column: 1, severity: .warning),
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
          @Bound(\\.service) let value = false
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

  // MARK: - @Bound on class-level var (v1 migration)

  @Test
  func `@Bound on class-level var emits migration warning`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State: Equatable {}
        var state = State()
        @Bound(\\.service) var value = false
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
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Bound on 'value': move @Bound to the State struct property instead", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - Action/handle diagnostics

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
        DiagnosticSpec(message: "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action) async' method found", line: 1, column: 1, severity: .error),
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
  func `Action enum with non-async handle emits warning`() {
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
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel: 'handle(_:)' should be 'async' for structured concurrency", line: 1, column: 1, severity: .warning),
      ],
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
        DiagnosticSpec(message: "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action) async' method found", line: 1, column: 1, severity: .error),
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
          @Bound(\\.service) var isLoading = false
        }
        var state = State()
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        private let service: MyService
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State: Equatable {
          var isLoading = false
        }
        var state = State()
        func handleDeepLink(destination: Destination?) { }
        private let service: MyService
        private let router: DeepLinkRouter

          init(service: MyService, router: DeepLinkRouter) {
              self.service = service
              self.router = router
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

  // MARK: - Manual startObserving missing Bound observe method

  @Test
  func `Manual startObserving missing @Bound observe method emits warning`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class ItemsViewModel {
        struct State: Equatable {
          @Bound(\\.service) var items: [String] = []
        }
        var state = State()
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
          var items: [String] = []
        }
        var state = State()
        func startObserving() async {
          // forgot to call observeItems
        }
        private let service: MyService

          init(service: MyService) {
              self.service = service
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
          @Bound(\\.service) var items: [String] = []
        }
        var state = State()
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
          var items: [String] = []
        }
        var state = State()
        func startObserving() async {
          await observeItems()
        }
        private let service: MyService

          init(service: MyService) {
              self.service = service
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
}
#endif
