import SwiftDiagnostics
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let stateMacros: [String: Macro.Type] = [
  "_ViewModelState": ViewModelStateMacro.self,
  "_ViewModelStateField": ViewModelStateFieldMacro.self,
]

@Suite("V11 State gateway macros")
struct ViewModelStateMacroTests {
  @Test
  func `State macro generates the release-workaround deinitialiser`() {
    assertMacroExpansionSwiftTesting(
      """
      @_ViewModelState
      final class State {}
      """,
      expandedSource: """
      final class State {

          private let _$observationRegistrar = Observation.ObservationRegistrar()

          nonisolated func access<Member>(keyPath: KeyPath<State, Member>) {
            _$observationRegistrar.access(self, keyPath: keyPath)
          }

          nonisolated func withMutation<Member, MutationResult>(
            keyPath: KeyPath<State, Member>,
            _ mutation: () throws -> MutationResult
          ) rethrows -> MutationResult {
            try _$observationRegistrar.withMutation(
              of: self,
              keyPath: keyPath,
              mutation)
          }

          var _visorMutationRecorder: (any VISOR._StateMutationRecorder)?

          @MainActor
          struct _VISORSelectors {


            init() {
            }
          }

          @MainActor
          static let _visorSelectors = _VISORSelectors()

          @MainActor
          static let _visorAllFields: [VISOR._AnyStateField<State>] = [

          ]

          private nonisolated func _visorShouldNotifyObservers<Value>(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              true
          }

          private nonisolated func _visorShouldNotifyObservers<Value: Equatable>(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              lhs != rhs
          }

          private nonisolated func _visorShouldNotifyObservers<Value: AnyObject>(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              lhs !== rhs
          }

          private nonisolated func _visorShouldNotifyObservers<
            Value: Equatable & AnyObject
          >(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              lhs != rhs
          }

          deinit {
          }
      }

      extension State: nonisolated Observation.Observable {
      }

      extension State: VISOR._ViewModelState {
      }
      """,
      macros: stateMacros)
  }

  @Test
  func `State macro preserves an explicit deinitialiser`() {
    assertMacroExpansionSwiftTesting(
      """
      @_ViewModelState
      final class State {
        deinit { recordDeinitialisation() }
      }
      """,
      expandedSource: """
      final class State {
        deinit { recordDeinitialisation() }

          private let _$observationRegistrar = Observation.ObservationRegistrar()

          nonisolated func access<Member>(keyPath: KeyPath<State, Member>) {
            _$observationRegistrar.access(self, keyPath: keyPath)
          }

          nonisolated func withMutation<Member, MutationResult>(
            keyPath: KeyPath<State, Member>,
            _ mutation: () throws -> MutationResult
          ) rethrows -> MutationResult {
            try _$observationRegistrar.withMutation(
              of: self,
              keyPath: keyPath,
              mutation)
          }

          var _visorMutationRecorder: (any VISOR._StateMutationRecorder)?

          @MainActor
          struct _VISORSelectors {


            init() {
            }
          }

          @MainActor
          static let _visorSelectors = _VISORSelectors()

          @MainActor
          static let _visorAllFields: [VISOR._AnyStateField<State>] = [

          ]

          private nonisolated func _visorShouldNotifyObservers<Value>(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              true
          }

          private nonisolated func _visorShouldNotifyObservers<Value: Equatable>(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              lhs != rhs
          }

          private nonisolated func _visorShouldNotifyObservers<Value: AnyObject>(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              lhs !== rhs
          }

          private nonisolated func _visorShouldNotifyObservers<
            Value: Equatable & AnyObject
          >(
            _ lhs: Value,
            _ rhs: Value
          ) -> Bool {
              lhs != rhs
          }
      }

      extension State: nonisolated Observation.Observable {
      }

      extension State: VISOR._ViewModelState {
      }
      """,
      macros: stateMacros)
  }

  @Test
  func `State macro rejects a conditional deinitialiser`() {
    assertMacroExpansionSwiftTesting(
      """
      @_ViewModelState
      final class State {
        #if DEBUG
        deinit { recordDebugDeinitialisation() }
        #endif
      }
      """,
      expandedSource: """
      final class State {
        #if DEBUG
        deinit { recordDebugDeinitialisation() }
        #endif
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "conditionalDeinitialiserUnsupported"),
        message: "@ViewModel types require an unconditional deinit; put conditional logic inside its body",
          line: 4,
          column: 3,
          severity: .error),
      ],
      macros: stateMacros)
  }

  @Test
  func `Field macro owns storage and Observation accessors`() {
    assertMacroExpansionSwiftTesting(
      """
      @_ViewModelStateField
      var count = 0
      """,
      expandedSource: """
      var count {
          @storageRestrictions(initializes: _count)
          init(initialValue) {
            _count = initialValue
          }
          get {
            access(keyPath: \\.count)
            return _count
          }
          set {
            guard _visorMutationRecorder != nil else {
              if _visorShouldNotifyObservers(_count, newValue) {
                withMutation(keyPath: \\.count) {
                  _count = newValue
                }
              } else {
                _count = newValue
              }
              return
            }

            let oldValue = _count
            if _visorShouldNotifyObservers(_count, newValue) {
              withMutation(keyPath: \\.count) {
                _count = newValue
              }
            } else {
              _count = newValue
            }
            let resultingValue = _count
            _visorRecordMutation(
              Self._visorField_count,
              oldValue: oldValue,
              newValue: resultingValue)
          }
          _modify {
            access(keyPath: \\.count)

            guard _visorMutationRecorder != nil else {
              _$observationRegistrar.willSet(self, keyPath: \\.count)
              defer {
                _$observationRegistrar.didSet(self, keyPath: \\.count)
              }
              yield &_count
              return
            }

            let oldValue = _count
            _$observationRegistrar.willSet(self, keyPath: \\.count)
            defer {
              _$observationRegistrar.didSet(self, keyPath: \\.count)
              _visorRecordMutation(
                Self._visorField_count,
                oldValue: oldValue,
                newValue: _count)
            }
            yield &_count
          }
      }

      private var _count = 0
      """,
      macros: stateMacros)
  }

  @Test
  func `A public setter fails closed with a fix-it`() {
    assertMacroExpansionSwiftTesting(
      """
      @_ViewModelState
      final class State {
        public var count = 0
        var valid = 1
      }
      """,
      expandedSource: """
      final class State {
        public var count = 0
        var valid = 1
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "unrestrictedPublicSetter"),
          message: "public VISOR State fields require private(set)",
          line: 3,
          column: 3,
          severity: .error,
          fixIts: [
            FixItSpec(message: "restrict the State field setter"),
          ]),
      ],
      macros: stateMacros,
      applyFixIts: ["restrict the State field setter"],
      fixedSource: """
      @_ViewModelState
      final class State {
        public private(set) var count = 0
        var valid = 1
      }
      """)
  }

  @Test
  func `An existing setter modifier is replaced by the fix-it`() {
    assertMacroExpansionSwiftTesting(
      """
      @_ViewModelState
      final class State {
        public internal(set) var count = 0
      }
      """,
      expandedSource: """
      final class State {
        public internal(set) var count = 0
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "unrestrictedPublicSetter"),
          message: "public VISOR State fields require private(set)",
          line: 3,
          column: 3,
          severity: .error,
          fixIts: [
            FixItSpec(message: "restrict the State field setter"),
          ]),
      ],
      macros: stateMacros,
      applyFixIts: ["restrict the State field setter"],
      fixedSource: """
      @_ViewModelState
      final class State {
        public private(set) var count = 0
      }
      """)
  }

  @Test
  func `The generated namespace is reserved and fails closed`() {
    assertMacroExpansionSwiftTesting(
      """
      @_ViewModelState
      final class State {
        var valid = 0
        var _visorStatus = false
      }
      """,
      expandedSource: """
      final class State {
        var valid = 0
        var _visorStatus = false
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "reservedName"),
          message: "'_visorStatus' uses VISOR's reserved _visor prefix",
          line: 4,
          column: 3,
          severity: .error),
      ],
      macros: stateMacros)
  }
}
#endif
