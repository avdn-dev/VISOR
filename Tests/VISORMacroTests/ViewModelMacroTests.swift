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

// MARK: - ViewModelMacroTests

@Suite("ViewModel Macro")
struct ViewModelMacroTests {

  // MARK: - Init Generation

  @Test
  func `Generates memberwise init and Factory typealias`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let service: MyService
        private let store: DataStore
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let service: MyService
        private let store: DataStore

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(service: MyService, store: DataStore) {
              self.service = service
              self.store = store
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Skips init when already exists`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      class MyViewModel: NSObject {
        @Observable
        final class State {
          var value = 0
        }
        init(service: MyService) {
          self.service = service
          super.init()
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      class MyViewModel: NSObject {
        @Observable
        final class State {
          var value = 0
        }
        init(service: MyService) {
          self.service = service
          super.init()
        }
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.value == rhs.value
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - Property Filtering

  @Test
  func `Skips var properties`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        var mutableProp: String = ""
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        var mutableProp: String = ""
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Skips let with default value`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let defaulted: String = "hello"
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let defaulted: String = "hello"
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - No Dependencies

  @Test
  func `No dependencies produces Factory typealias only`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class SimpleViewModel {
        @Observable
        final class State {
          var count = 0
        }
      }
      """,
      expandedSource: """
      @Observable
      final class SimpleViewModel {
        @Observable
        final class State {
          var count = 0
        }

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          typealias Factory = ViewModelFactory<SimpleViewModel>
      }

      extension SimpleViewModel: @MainActor ViewModel {
      }

      extension SimpleViewModel.State: Equatable {
          static func == (lhs: SimpleViewModel.State, rhs: SimpleViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
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
        @Observable
        final class State {
          var count = 0
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      public final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          public var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          public init(service: MyService) {
              self.service = service
          }

          public typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
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
        @Observable
        final class State {
          @Bound(\\MyViewModel.service.isLoading) var isLoading: Bool
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      public final class MyViewModel {
        @Observable
        final class State {
          var isLoading: Bool
        }
        private let service: MyService

          @ObservationIgnored private var _state: State

          public var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.isLoading == rhs.isLoading
          }
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
        @Observable
        final class State {
          var count = 0
        }
      }
      """,
      expandedSource: """
      struct NotAClass {
        @Observable
        final class State {
          var count = 0
        }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel can only be applied to classes", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `Missing Observable on outer class emits error`() {
    assertMacroExpansion(
      """
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let service: MyService
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel requires @Observable on the class to enable observation tracking", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - @Bound inside State

  @Test
  func `@Bound inside State generates updateState observe method`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          @Bound(\\MyViewModel.permissionService.isCameraDenied) var isCameraDenied: Bool
        }
        private let permissionService: PermissionService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var isCameraDenied: Bool
        }
        private let permissionService: PermissionService

          @ObservationIgnored private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.isCameraDenied == rhs.isCameraDenied
          }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Multiple @Bound inside State generates withDiscardingTaskGroup`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          @Bound(\\MyViewModel.connectionService.isAuthenticated) var isAuthenticated: Bool
          @Bound(\\MyViewModel.connectionService.isLoading) var isLoading: Bool
          @Bound(\\MyViewModel.connectionService.connections) var connections: [Connection]
        }
        private let connectionService: ConnectionService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var isAuthenticated: Bool
          var isLoading: Bool
          var connections: [Connection]
        }
        private let connectionService: ConnectionService

          @ObservationIgnored private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.isAuthenticated == rhs.isAuthenticated
              && lhs.isLoading == rhs.isLoading
              && lhs.connections == rhs.connections
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - State/Action diagnostics

  @Test
  func `Missing State class emits error`() {
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
        DiagnosticSpec(message: "@ViewModel requires a nested '@Observable final class State { }'", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `State class not final emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        class State {
          var count = 0
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        class State {
          var count = 0
        }
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "State class must be 'final'", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  @Test
  func `State class missing Observable emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        final class State {
          var count = 0
        }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        final class State {
          var count = 0
        }
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "State class requires @Observable", line: 1, column: 1, severity: .error),
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
        @Observable
        final class State {
          var count = 0
        }
        enum Action { case refresh }
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        enum Action { case refresh }
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action)' method found", line: 1, column: 1, severity: .error),
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
        @Observable
        final class State {
          var count = 0
        }
      }
      """,
      expandedSource: """
      @Observable
      final class SimpleViewModel {
        @Observable
        final class State {
          var count = 0
        }

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          typealias Factory = ViewModelFactory<SimpleViewModel>
      }

      extension SimpleViewModel: @MainActor ViewModel {
      }

      extension SimpleViewModel.State: Equatable {
          static func == (lhs: SimpleViewModel.State, rhs: SimpleViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - @Reaction Generation

  @Test
  func `Sync @Reaction generates for-await loop`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          var lastDestination: String? = nil
        }
        @Reaction(\\Self.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var lastDestination: String? = nil
        }
        func handleDeepLink(destination: Destination?) { }
        private let router: DeepLinkRouter

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

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

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.lastDestination == rhs.lastDestination
          }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Mixed @Bound in State and @Reaction generates combined startObserving`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          @Bound(\\MyViewModel.service.isLoading) var isLoading: Bool
        }
        @Reaction(\\Self.router.pendingDestination)
        func handleDeepLink(destination: Destination?) { }
        private let service: MyService
        private let router: DeepLinkRouter
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var isLoading: Bool
        }
        func handleDeepLink(destination: Destination?) { }
        private let service: MyService
        private let router: DeepLinkRouter

          @ObservationIgnored private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.isLoading == rhs.isLoading
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - @Polled inside State

  @Test
  func `Single @Polled generates inlined poll loop`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class DashboardVM {
        @Observable
        final class State {
          @Polled(\\DashboardVM.monitor.level, every: .seconds(30)) var level: Float
        }
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      @Observable
      final class DashboardVM {
        @Observable
        final class State {
          var level: Float
        }
        private let monitor: BatteryMonitor

          @ObservationIgnored private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension DashboardVM.State: Equatable {
          static func == (lhs: DashboardVM.State, rhs: DashboardVM.State) -> Bool {
              lhs.level == rhs.level
          }
      }
      """,
      macros: testMacros)
  }

  @Test
  func `Mixed @Bound and @Polled preserves declaration order in init`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MixedVM {
        @Observable
        final class State {
          @Bound(\\MixedVM.service.name) var name: String
          @Polled(\\MixedVM.monitor.level, every: .seconds(5)) var level: Float
          @Bound(\\MixedVM.service.count) var count: Int
        }
        private let service: MyService
        private let monitor: BatteryMonitor
      }
      """,
      expandedSource: """
      @Observable
      final class MixedVM {
        @Observable
        final class State {
          var name: String
          var level: Float
          var count: Int
        }
        private let service: MyService
        private let monitor: BatteryMonitor

          @ObservationIgnored private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension MixedVM.State: Equatable {
          static func == (lhs: MixedVM.State, rhs: MixedVM.State) -> Bool {
              lhs.name == rhs.name
              && lhs.level == rhs.level
              && lhs.count == rhs.count
          }
      }
      """,
      macros: testMacros)
  }

  // MARK: - @Bound with throttledBy

  @Test
  func `@Bound with throttledBy generates sleep after updateState`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class HeadVM {
        @Observable
        final class State {
          @Bound(\\HeadVM.tracker.posture, throttledBy: .seconds(0.125)) var posture: Posture
        }
        private let tracker: HeadTracker
      }
      """,
      expandedSource: """
      @Observable
      final class HeadVM {
        @Observable
        final class State {
          var posture: Posture
        }
        private let tracker: HeadTracker

          @ObservationIgnored private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension HeadVM.State: Equatable {
          static func == (lhs: HeadVM.State, rhs: HeadVM.State) -> Bool {
              lhs.posture == rhs.posture
          }
      }
      """,
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
        @Observable
        final class State {
          var count = 0
        }
        private let router: Router<AppScene>
        private let sessionInteractor: any SessionInteractor
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        private let router: Router<AppScene>
        private let sessionInteractor: any SessionInteractor

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(router: Router<AppScene>, sessionInteractor: any SessionInteractor) {
              self.router = router
              self.sessionInteractor = sessionInteractor
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
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

  // MARK: - @Bound outside State

  @Test
  func `@Bound on class-level var emits error`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        @Bound(\\MyViewModel.service.value) var value = false
        private let service: MyService
      }
      """,
      expandedSource: """
      @Observable
      final class MyViewModel {
        @Observable
        final class State {
          var count = 0
        }
        var value = false
        private let service: MyService

          @ObservationIgnored private var _state: State = State()

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
          }

          init(service: MyService) {
              self.service = service
          }

          typealias Factory = ViewModelFactory<MyViewModel>
      }

      extension MyViewModel: @MainActor ViewModel {
      }

      extension MyViewModel.State: Equatable {
          static func == (lhs: MyViewModel.State, rhs: MyViewModel.State) -> Bool {
              lhs.count == rhs.count
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "@Bound must be inside 'class State' — move to the corresponding State property", line: 1, column: 1, severity: .error),
      ],
      macros: testMacros)
  }

  // MARK: - Manual startObserving

  @Test
  func `Manual startObserving missing @Bound observe method emits warning`() {
    assertMacroExpansion(
      """
      @Observable
      @ViewModel
      final class ItemsViewModel {
        @Observable
        final class State {
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
        @Observable
        final class State {
          var items: [String]
        }
        func startObserving() async {
          // forgot to call observeItems
        }
        private let service: MyService

          @ObservationIgnored private var _state: State

          var state: State {
              get { access(keyPath: \\.state); return _state }
              set { withMutation(keyPath: \\.state) { _state = newValue } }
          }

          func updateState<V: Equatable>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              guard _state[keyPath: keyPath] != value else { return }
              _state[keyPath: keyPath] = value
          }

          func updateState<V>(_ keyPath: WritableKeyPath<State, V>, to value: V) {
              _state[keyPath: keyPath] = value
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

      extension ItemsViewModel.State: Equatable {
          static func == (lhs: ItemsViewModel.State, rhs: ItemsViewModel.State) -> Bool {
              lhs.items == rhs.items
          }
      }
      """,
      diagnostics: [
        DiagnosticSpec(message: "startObserving() does not call observeItems(); state derivation will not run", line: 1, column: 1, severity: .warning),
      ],
      macros: testMacros)
  }

  // MARK: - @ViewModelState direct expansion

  @Test
  func `ViewModelState generates public init and Equatable for public class with mixed defaults`() {
    let stateMacros: [String: Macro.Type] = [
      "ViewModelState": ViewModelStateMacro.self,
    ]
    assertMacroExpansion(
      """
      @ViewModelState
      public final class State {
        public var appSettings = AppSettings.default
        public var isLoading = false
        public var errorMessage: String?
      }
      """,
      expandedSource: """
      public final class State {
        public var appSettings = AppSettings.default
        public var isLoading = false
        public var errorMessage: String?

          public init(isLoading: Bool = false, errorMessage: String? = nil) {
              self._isLoading = isLoading
              self._errorMessage = errorMessage
          }
      }

      extension State: @preconcurrency Equatable {
          public static func == (lhs: State, rhs: State) -> Bool {
              lhs.appSettings == rhs.appSettings
                  && lhs.isLoading == rhs.isLoading
                  && lhs.errorMessage == rhs.errorMessage
          }
      }
      """,
      macros: stateMacros)
  }
}
#endif
