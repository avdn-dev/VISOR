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

// MARK: - ViewModelMacroTests

@Suite("ViewModel Macro")
struct ViewModelMacroTests {

  // MARK: - Init Generation

  @Test
  func `Generates memberwise init, Factory typealias, preview, and PreviewProviding`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let service: MyService
        private let store: DataStore
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let service: MyService
        private let store: DataStore

          init(service: MyService, store: DataStore) {
              self.service = service
              self.store = store
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService(),
              store: StubDataStore()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Skips init when already exists`() {
    assertMacroExpansion(
      """
      @ViewModel
      class MyViewModel: NSObject {
        var state: ViewModelState<Bool> { .loaded(state: true) }
        init(service: MyService) {
          self.service = service
          super.init()
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      class MyViewModel: NSObject {
        var state: ViewModelState<Bool> { .loaded(state: true) }
        init(service: MyService) {
          self.service = service
          super.init()
        }
        private let service: MyService

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - Property Filtering

  @Test
  func `Skips var properties`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var mutableProp: String = ""
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var mutableProp: String = ""
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Skips let with default value`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let defaulted: String = "hello"
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let defaulted: String = "hello"
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - No Dependencies

  @Test
  func `No dependencies produces Factory typealias and empty preview`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class SimpleViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
      }
      """,
      expandedSource: """
      final class SimpleViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }

          typealias Factory = ViewModelFactory<SimpleViewModel>

          #if DEBUG
          static var preview: SimpleViewModel {
            SimpleViewModel()
          }
          #endif
      }

      extension SimpleViewModel: @MainActor ViewModel {
      }

      extension SimpleViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: SimpleViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - Isolation Skipping

  @Test
  func `Skips nonisolated members`() {
    assertMacroExpansion(
      """
      @ViewModel
      class MyViewModel: NSObject {
        var state: ViewModelState<Bool> { .loaded(state: true) }
        nonisolated func delegateCallback() { }
        private let service: MyService
      }
      """,
      expandedSource: """
      class MyViewModel: NSObject {
        var state: ViewModelState<Bool> { .loaded(state: true) }
        nonisolated func delegateCallback() { }
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Skips nested types`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        struct State {
          let count: Int
        }
        var state: ViewModelState<State> { .loaded(state: State(count: 0)) }
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        struct State {
          let count: Int
        }
        var state: ViewModelState<State> { .loaded(state: State(count: 0)) }
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
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
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
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
        var state: ViewModelState<Int> { .loaded(state: 0) }
      }
      """,
      expandedSource: """
      struct NotAClass {
        var state: ViewModelState<Int> { .loaded(state: 0) }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel can only be applied to classes", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

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

  @Test
  func `Multiple let properties of same type`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let serviceA: MyService
        private let serviceB: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let serviceA: MyService
        private let serviceB: MyService

          init(serviceA: MyService, serviceB: MyService) {
              self.serviceA = serviceA
              self.serviceB = serviceB
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              serviceA: StubMyService(),
              serviceB: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }
  // MARK: - @Bound Generation

  @Test
  func `Multiple Bound properties generates withDiscardingTaskGroup`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Bound(\\.connectionService) var isAuthenticated = false
        @Bound(\\.connectionService) var isLoading = false
        @Bound(\\.connectionService) var connections: [Connection] = []
        private let connectionService: ConnectionService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var isAuthenticated = false
        var isLoading = false
        var connections: [Connection] = []
        private let connectionService: ConnectionService

          init(connectionService: ConnectionService) {
              self.connectionService = connectionService
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeIsAuthenticated() async {
              for await value in VISOR.valuesOf({ self.connectionService.isAuthenticated }) {
                  self.isAuthenticated = value
              }
          }

          func observeIsLoading() async {
              for await value in VISOR.valuesOf({ self.connectionService.isLoading }) {
                  self.isLoading = value
              }
          }

          func observeConnections() async {
              for await value in VISOR.valuesOf({ self.connectionService.connections }) {
                  self.connections = value
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeIsAuthenticated() }
                  group.addTask { await self.observeIsLoading() }
                  group.addTask { await self.observeConnections() }
              }
          }

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              connectionService: StubConnectionService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Single Bound property generates direct observation`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Bound(\\.permissionService) var isCameraDenied = false
        private let permissionService: PermissionService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var isCameraDenied = false
        private let permissionService: PermissionService

          init(permissionService: PermissionService) {
              self.permissionService = permissionService
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeIsCameraDenied() async {
              for await value in VISOR.valuesOf({ self.permissionService.isCameraDenied }) {
                  self.isCameraDenied = value
              }
          }

          func startObserving() async {
              await observeIsCameraDenied()
          }

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              permissionService: StubPermissionService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Bound observation methods generated alongside manual startObserving`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Bound(\\.service) var value = false
        func startObserving() async {
          // custom implementation
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var value = false
        func startObserving() async {
          // custom implementation
        }
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          func observeValue() async {
              for await value in VISOR.valuesOf({ self.service.value }) {
                  self.value = value
              }
          }

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Multiple different dependency sources`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Bound(\\.widgetService) var selectedId = ""
        @Bound(\\.connectionService) var connections: [Connection] = []
        @Bound(\\.sharingService) var isSending = false
        private let widgetService: WidgetService
        private let connectionService: ConnectionService
        private let sharingService: SharingService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var selectedId = ""
        var connections: [Connection] = []
        var isSending = false
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
                  self.selectedId = value
              }
          }

          func observeConnections() async {
              for await value in VISOR.valuesOf({ self.connectionService.connections }) {
                  self.connections = value
              }
          }

          func observeIsSending() async {
              for await value in VISOR.valuesOf({ self.sharingService.isSending }) {
                  self.isSending = value
              }
          }

          func startObserving() async {
              await withDiscardingTaskGroup { group in
                  group.addTask { await self.observeSelectedId() }
                  group.addTask { await self.observeConnections() }
                  group.addTask { await self.observeIsSending() }
              }
          }

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              widgetService: StubWidgetService(),
              connectionService: StubConnectionService(),
              sharingService: StubSharingService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - @Reaction Generation

  @Test
  func `Sync Reaction generates for-await loop`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
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

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              router: StubDeepLinkRouter()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Async Reaction generates latestValuesOf call`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Reaction(\\.uploadService.uploadState)
        func handleUploadState(state: UploadState) async { }
        private let uploadService: UploadService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
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

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              uploadService: StubUploadService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Mixed Bound and Reaction generates combined startObserving`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Bound(\\.service) var isLoading = false
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        private let service: MyService
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var isLoading = false
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
                  self.isLoading = value
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

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService(),
              router: StubDeepLinkRouter()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Reaction observation methods generated alongside manual startObserving`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        func startObserving() async {
          // custom implementation
        }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        func handleDeepLink(destination: Destination?) { }
        func startObserving() async {
          // custom implementation
        }
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

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              router: StubDeepLinkRouter()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Reaction with zero params emits diagnostic`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink() { }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        func handleDeepLink() { }
        private let router: DeepLinkRouter

          init(router: DeepLinkRouter) {
              self.router = router
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              router: StubDeepLinkRouter()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Reaction on 'handleDeepLink': method must have exactly one parameter", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Reaction with two params emits diagnostic`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Reaction(\\.router.pendingDestination)
        func handleDeepLink(destination: Destination?, source: String) { }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        func handleDeepLink(destination: Destination?, source: String) { }
        private let router: DeepLinkRouter

          init(router: DeepLinkRouter) {
              self.router = router
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              router: StubDeepLinkRouter()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: "@Reaction on 'handleDeepLink': method must have exactly one parameter", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Multi-binding let declaration captures all properties`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let serviceA: ServiceA, serviceB: ServiceB
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let serviceA: ServiceA, serviceB: ServiceB

          init(serviceA: ServiceA, serviceB: ServiceB) {
              self.serviceA = serviceA
              self.serviceB = serviceB
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              serviceA: StubServiceA(),
              serviceB: StubServiceB()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Warning for malformed Bound key path`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Bound("invalid") var value = false
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var value = false
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: #"@Bound on 'value': expected key path argument like \Self.dependencyName"#, line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - Router Type Detection

  @Test
  func `Router property uses direct init instead of Stub prefix`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let router: Router<AppScene>
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        private let router: Router<AppScene>
        private let service: MyService

          init(router: Router<AppScene>, service: MyService) {
              self.router = router
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              router: Router<AppScene>(),
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  @Test
  func `Error for invalid dependency name in Bound key path`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        @Bound(\\.typoService) var value = false
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        var state: ViewModelState<Int> { .loaded(state: 0) }
        var value = false
        private let service: MyService

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>

          #if DEBUG
          static var preview: MyViewModel {
            MyViewModel(
              service: StubMyService()
            )
          }
          #endif
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel: PreviewProviding {
          #if !DEBUG
          static var preview: MyViewModel {
              fatalError()
          }
          #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .warning),
        DiagnosticSpec(message: #"@Bound(\.typoService) on 'value': no stored 'let typoService' found on this class"#, line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }
}
#endif
