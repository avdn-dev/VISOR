import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

#if canImport(VISORMacros)
import VISORMacros

private let viewModelV11Macros: [String: Macro.Type] = [
  "Bound": BoundMacro.self,
  "Reaction": ReactionMacro.self,
  "ViewModel": ViewModelMacro.self,
]

private let sourceEntryV11Macros: [String: Macro.Type] = [
  "Bound": BoundMacro.self,
  "Reaction": ReactionMacro.self,
]

private let viewModelOnlyV11Macros: [String: Macro.Type] = [
  "ViewModel": ViewModelMacro.self
]

@Suite("V11 ViewModel macro")
struct ViewModelV11MacroTests {
  @Test
  func `State ownership and an empty initialiser are synthesised when omitted`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class EmptyViewModel {
        final class State {
          var count = 0
        }
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class EmptyViewModel {
          @MainActor @VISOR._ViewModelState
          final class State {
            var count = 0
          }

            typealias Factory = ViewModelFactory<EmptyViewModel>

            let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()

            let state: State

            init() {
              self.state = State()
            }

            deinit {
            }
        }

        extension EmptyViewModel: @MainActor ViewModel {
        }
        """,
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Memberwise initialiser establishes State from coherent source baselines`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      public final class SourceInitialisedViewModel {
        public final class State {
          @Bound(
            source: \\SourceInitialisedViewModel.consumer.snapshotSource,
            selecting: \\Snapshot.count)
          public private(set) var count: Int

          @Bound(
            source: \\AlternateRoot.SourceInitialisedViewModel.consumer.snapshotSource,
            selecting: \\Snapshot.label)
          public private(set) var label: String

          @Bound(source: \\SourceInitialisedViewModel.status.valueSource)
          public private(set) var status: Status

          public init(count: Int, label: String, status: Status) {
            self.count = count
            self.label = label
            self.status = status
          }
        }

        public let consumer: Consumer
        private let status: StatusService
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        public final class SourceInitialisedViewModel {
          @MainActor @VISOR._ViewModelState
          public final class State {
            public private(set) var count: Int
            public private(set) var label: String
            public private(set) var status: Status

            public init(count: Int, label: String, status: Status) {
              self.count = count
              self.label = label
              self.status = status
            }
          }

          public let consumer: Consumer
          private let status: StatusService

            public typealias Factory = ViewModelFactory<SourceInitialisedViewModel>

            public let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()

            public let state: State

            public init(consumer: Consumer, status: StatusService) {
              self.consumer = consumer
              self.status = status
              let _visorInitialSource0 = consumer.snapshotSource.currentSnapshot()
              let _visorInitialSource1 = status.valueSource.currentSnapshot()
              self.state = State(
                count: _visorInitialSource0[keyPath: \\Snapshot.count],
                label: _visorInitialSource0[keyPath: \\Snapshot.label],
                status: _visorInitialSource1)
            }

            deinit {
            }

            public func _visorBuildObservationRecipe(
              into visitor: VISOR._ObservationRecipeVisitor
            ) {
              visitor.add(
              source: self[keyPath: \\SourceInitialisedViewModel.consumer.snapshotSource],
              projections: [
                { [weak self] snapshot in
              guard let self else {
                  return
              }
              self.updateState(\\.count, to: snapshot[keyPath: \\Snapshot.count])
                },
                { [weak self] snapshot in
                  guard let self else {
                  return
              }
                  self.updateState(\\.label, to: snapshot[keyPath: \\Snapshot.label])
                }
              ],
              initialReactions: [

              ])
              visitor.add(
                source: self[keyPath: \\SourceInitialisedViewModel.status.valueSource],
                projections: [
                  { [weak self] snapshot in
                guard let self else {
                  return
              }
                self.updateState(\\.status, to: snapshot)
                }
                ],
                initialReactions: [

                ])
            }
        }

        extension SourceInitialisedViewModel: @MainActor ViewModel {
        }
        """,
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Custom initialisation remains authored`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class CustomViewModel {
        final class State {
          var count: Int

          init(count: Int) {
            self.count = count
          }
        }

        let state: State
        let service: Service

        init(service: Service) {
          self.service = service
          self.state = State(count: service.initialCount)
          recordConstruction()
        }
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class CustomViewModel {
          @MainActor @VISOR._ViewModelState
          final class State {
            var count: Int

            init(count: Int) {
              self.count = count
            }
          }

          let state: State
          let service: Service

          init(service: Service) {
            self.service = service
            self.state = State(count: service.initialCount)
            recordConstruction()
          }

            typealias Factory = ViewModelFactory<CustomViewModel>

            let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()

            deinit {
            }
        }

        extension CustomViewModel: @MainActor ViewModel {
        }
        """,
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Memberwise initialisers preserve dependency types and exclude owned storage`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      package final class DependencyViewModel {
        final class State {}
        private var cachedValue = ""
        private var task: Task<Void, Never>?
        private let defaultedValue = "default"
        private let router: Router<AppScene>
        private let service: any Service
        private let onAppear: () -> Void
        private let openURL: @MainActor @Sendable (URL) -> Bool
        private let onDismiss: (() -> Void)
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        package final class DependencyViewModel {
          @MainActor @VISOR._ViewModelState
          final class State {}
          private var cachedValue = ""
          private var task: Task<Void, Never>?
          private let defaultedValue = "default"
          private let router: Router<AppScene>
          private let service: any Service
          private let onAppear: () -> Void
          private let openURL: @MainActor @Sendable (URL) -> Bool
          private let onDismiss: (() -> Void)

            typealias Factory = ViewModelFactory<DependencyViewModel>

            let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()

            let state: State

            init(router: Router<AppScene>, service: any Service, onAppear: @escaping () -> Void, openURL: @escaping @MainActor @Sendable (URL) -> Bool, onDismiss: @escaping (() -> Void)) {
              self.router = router
              self.service = service
              self.onAppear = onAppear
              self.openURL = openURL
              self.onDismiss = onDismiss
              self.state = State()
            }

            deinit {
            }
        }

        extension DependencyViewModel: @MainActor ViewModel {
        }
        """,
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Unsafe synthesis shapes fail closed`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class MutableDependencyViewModel {
        final class State {}
        var service: Service
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class MutableDependencyViewModel {
          final class State {}
          var service: Service
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "viewModelRequiresInitialisation",
          ),
          message:
          "@ViewModel cannot synthesise initialisation for this State; declare a stored 'let state' and a custom initialiser",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class AmbiguousStateViewModel {
        final class State {
          init() {}
          init(count: Int) {}
        }
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class AmbiguousStateViewModel {
          final class State {
            init() {}
            init(count: Int) {}
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "viewModelRequiresInitialisation",
          ),
          message:
          "@ViewModel cannot synthesise initialisation for this State; declare a stored 'let state' and a custom initialiser",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class DerivedStateViewModel {
        final class State {
          var summary: String

          init(summary: String) {
            self.summary = summary
          }
        }

        let service: Service
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class DerivedStateViewModel {
          final class State {
            var summary: String

            init(summary: String) {
              self.summary = summary
            }
          }

          let service: Service
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "viewModelRequiresInitialisation",
          ),
          message:
          "@ViewModel cannot synthesise initialisation for this State; declare a stored 'let state' and a custom initialiser",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `A plain State cascades the hidden gateway and uses the default recipe hook`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class EmptyViewModel {
        final class State {
          var count = 0
        }

        let state = State()
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class EmptyViewModel {
          @MainActor @VISOR._ViewModelState
          final class State {
            var count = 0
          }

          let state = State()

            typealias Factory = ViewModelFactory<EmptyViewModel>

            let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()

            deinit {
            }
        }

        extension EmptyViewModel: @MainActor ViewModel {
        }
        """,
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Equivalent source roots group projections before reactions`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class SourceViewModel {
        final class State {
          @Bound(
            source: \\SourceViewModel.service.source,
            selecting: \\Snapshot.count)
          var count = 0

          @Bound(
            source: \\AlternateRoot.SourceViewModel.service.source,
            selecting: \\Snapshot.label)
          var label = ""

          @Bound(source: \\SourceViewModel.status.source)
          var status = 0
        }

        let state = State()
        let service: Service
        let status: StatusService

        @Reaction(
          source: \\AlternateRoot.SourceViewModel.service.source,
          selecting: \\Snapshot.count)
        func countChanged(_ count: Int) {}

        @Reaction(source: \\SourceViewModel.status.source)
        func statusChanged(value: Int) async {}
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class SourceViewModel {
          @MainActor @VISOR._ViewModelState
          final class State {
            var count = 0
            var label = ""
            var status = 0
          }

          let state = State()
          let service: Service
          let status: StatusService
          func countChanged(_ count: Int) {}
          func statusChanged(value: Int) async {}

            typealias Factory = ViewModelFactory<SourceViewModel>

            let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()

            init(service: Service, status: StatusService) {
              self.service = service
              self.status = status
            }

            deinit {
            }

            func _visorBuildObservationRecipe(
              into visitor: VISOR._ObservationRecipeVisitor
            ) {
              visitor.add(
              source: self[keyPath: \\SourceViewModel.service.source],
              projections: [
                { [weak self] snapshot in
              guard let self else {
                  return
              }
              self.updateState(\\.count, to: snapshot[keyPath: \\Snapshot.count])
                },
                { [weak self] snapshot in
                  guard let self else {
                  return
              }
                  self.updateState(\\.label, to: snapshot[keyPath: \\Snapshot.label])
                }
              ],
              initialReactions: [
                { [weak self] snapshot in
              guard let self else {
                  return
              }
              self.countChanged(snapshot[keyPath: \\Snapshot.count])
                }
              ])
              visitor.add(
                source: self[keyPath: \\SourceViewModel.status.source],
                projections: [
                  { [weak self] snapshot in
                guard let self else {
                  return
              }
                self.updateState(\\.status, to: snapshot)
                }
                ],
                initialReactions: [
                  { [weak self] snapshot in
                guard let self else {
                  return
              }
                await self.statusChanged(value: snapshot)
                }
                ])
            }
        }

        extension SourceViewModel: @MainActor ViewModel {
        }
        """,
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `An explicit source-backed deinitialiser is preserved`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class ExplicitDeinitViewModel {
        final class State {}
        let state = State()

        deinit { recordDeinitialisation() }
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class ExplicitDeinitViewModel {
          @MainActor @VISOR._ViewModelState
          final class State {}
          let state = State()

          deinit { recordDeinitialisation() }

            typealias Factory = ViewModelFactory<ExplicitDeinitViewModel>

            let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()
        }

        extension ExplicitDeinitViewModel: @MainActor ViewModel {
        }
        """,
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `A conditional source-backed deinitialiser fails closed`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class ConditionalDeinitViewModel {
        final class State {}
        let state = State()

        #if DEBUG
        deinit { recordDebugDeinitialisation() }
        #endif
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class ConditionalDeinitViewModel {
          final class State {}
          let state = State()

          #if DEBUG
          deinit { recordDebugDeinitialisation() }
          #endif
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "conditionalDeinitialiserUnsupported",
          ),
          message:
          "@ViewModel types require an unconditional deinit; put conditional logic inside its body",
          line: 9,
          column: 3,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `V11 State ownership must be stable`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class MutableStateViewModel {
        final class State {
          var count = 0
        }

        var state = State()
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class MutableStateViewModel {
          final class State {
            var count = 0
          }

          var state = State()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "viewModelRequiresStableState"),
          message: "@ViewModel requires State to be held by a stored 'let state' property",
          line: 9,
          column: 3,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Source-form Bound validates placement and declaration shape`() {
    assertMacroExpansionSwiftTesting(
      """
      final class NotAViewModel {
        @Bound(source: \\NotAViewModel.source)
        var value = 0
      }
      """,
      expandedSource: """
        final class NotAViewModel {
          var value = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "invalidSourceBoundPlacement",
          ),
          message: "@Bound(source:) is only supported on a direct member of @ViewModel.State",
          line: 2,
          column: 3,
          severity: .error,
        )
      ],
      macros: sourceEntryV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @ViewModel
      final class ExampleViewModel {
        final class State {
          @Bound(source: \\ExampleViewModel.source)
          let value = 0
        }
      }
      """,
      expandedSource: """
        @ViewModel
        final class ExampleViewModel {
          final class State {
            let value = 0
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "invalidSourceBoundDeclaration",
          ),
          message:
          "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
          line: 4,
          column: 5,
          severity: .error,
        )
      ],
      macros: sourceEntryV11Macros,
    )
  }

  @Test
  func `Source-form Reaction validates placement and declaration shape`() {
    assertMacroExpansionSwiftTesting(
      """
      extension ExampleViewModel {
        @Reaction(source: \\ExampleViewModel.source)
        func changed(_ value: Int) {}
      }
      """,
      expandedSource: """
        extension ExampleViewModel {
          func changed(_ value: Int) {}
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "invalidSourceReactionPlacement",
          ),
          message: "@Reaction(source:) is only supported on a direct @ViewModel member",
          line: 2,
          column: 3,
          severity: .error,
        )
      ],
      macros: sourceEntryV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @ViewModel
      final class ExampleViewModel {
        @Reaction(source: \\ExampleViewModel.source)
        func changed(_ first: Int, _ second: Int) {}
      }
      """,
      expandedSource: """
        @ViewModel
        final class ExampleViewModel {
          func changed(_ first: Int, _ second: Int) {}
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "invalidSourceReactionDeclaration",
          ),
          message:
          "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
          line: 3,
          column: 3,
          severity: .error,
        )
      ],
      macros: sourceEntryV11Macros,
    )
  }

  @Test
  func `Malformed source arguments fail closed without partial expansion`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class MalformedSourceViewModel {
        final class State {
          @Bound(source: \\MalformedSourceViewModel.service.source, source: \\MalformedSourceViewModel.service.source)
          var duplicate = 0

          @Bound(selecting: \\Snapshot.count, source: \\MalformedSourceViewModel.service.source)
          var reversed = 0

          @Bound(source: \\MalformedSourceViewModel.service.source, selecting: \\Snapshot.count, selecting: \\Snapshot.count)
          var extra = 0
        }

        let state = State()
        let service: Service
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class MalformedSourceViewModel {
          final class State {
            var duplicate = 0
            var reversed = 0
            var extra = 0
          }

          let state = State()
          let service: Service
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceBoundDeclaration"),
          message:
          "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
          line: 6,
          column: 5,
          severity: .error,
        ),
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceBoundDeclaration"),
          message:
          "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
          line: 9,
          column: 5,
          severity: .error,
        ),
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceBoundDeclaration"),
          message:
          "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
          line: 12,
          column: 5,
          severity: .error,
        ),
      ],
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Malformed source Reaction arguments fail closed`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class MalformedSourceReactionViewModel {
        final class State {}

        let state = State()
        let service: Service

        @Reaction(source: \\MalformedSourceReactionViewModel.service.source, source: \\MalformedSourceReactionViewModel.service.source)
        func duplicate(_ value: Int) {}

        @Reaction(selecting: \\Snapshot.count, source: \\MalformedSourceReactionViewModel.service.source)
        func reversed(_ value: Int) {}

        @Reaction(source: \\MalformedSourceReactionViewModel.service.source, selecting: \\Snapshot.count, selecting: \\Snapshot.count)
        func extra(_ value: Int) {}
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class MalformedSourceReactionViewModel {
          final class State {}

          let state = State()
          let service: Service
          func duplicate(_ value: Int) {}
          func reversed(_ value: Int) {}
          func extra(_ value: Int) {}
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceReactionDeclaration"),
          message:
          "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
          line: 10,
          column: 3,
          severity: .error,
        ),
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceReactionDeclaration"),
          message:
          "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
          line: 13,
          column: 3,
          severity: .error,
        ),
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceReactionDeclaration"),
          message:
          "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
          line: 16,
          column: 3,
          severity: .error,
        ),
      ],
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Private source-bound State fields fail closed`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class PrivateBoundViewModel {
        final class State {
          @Bound(source: \\PrivateBoundViewModel.service.source)
          private var count = 0
        }

        let state = State()
        let service: Service
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class PrivateBoundViewModel {
          final class State {
            private var count = 0
          }

          let state = State()
          let service: Service
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceBoundDeclaration"),
          message:
          "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
          line: 6,
          column: 5,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Duplicate source routing markers fail closed`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class DuplicateSourceMarkerViewModel {
        final class State {
          @Bound(source: \\DuplicateSourceMarkerViewModel.service.source)
          @Bound(source: \\DuplicateSourceMarkerViewModel.service.source)
          var count = 0
        }

        let state = State()
        let service: Service

        @Reaction(source: \\DuplicateSourceMarkerViewModel.service.source)
        @Reaction(source: \\DuplicateSourceMarkerViewModel.service.source)
        func countChanged(_ count: Int) {}
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class DuplicateSourceMarkerViewModel {
          final class State {
            var count = 0
          }

          let state = State()
          let service: Service
          func countChanged(_ count: Int) {}
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceBoundDeclaration"),
          message:
          "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
          line: 6,
          column: 5,
          severity: .error,
        ),
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "invalidSourceReactionDeclaration"),
          message:
          "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
          line: 14,
          column: 3,
          severity: .error,
        ),
      ],
      macros: viewModelV11Macros,
    )
  }

  @Test
  func `Invalid ViewModel and State shapes fail closed`() {
    assertMacroExpansionSwiftTesting(
      """
      @ViewModel
      struct StructViewModel {}
      """,
      expandedSource: """
        struct StructViewModel {}
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "notAClass"),
          message: "@ViewModel can only be applied to classes",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelOnlyV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @ViewModel
      final class MissingObservableViewModel {
        final class State {}
        let state = State()
      }
      """,
      expandedSource: """
        @MainActor
        final class MissingObservableViewModel {
          final class State {}
          let state = State()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "missingObservable"),
          message: "@ViewModel requires @Observable on the class to enable observation tracking",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelOnlyV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class MissingStateViewModel {}
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class MissingStateViewModel {}
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "missingState"),
          message: "@ViewModel requires a nested plain 'final class State { }'",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelOnlyV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class NonFinalStateViewModel {
        class State {}
        let state = State()
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class NonFinalStateViewModel {
          class State {}
          let state = State()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "stateClassNotFinal"),
          message: "State class must be 'final'",
          line: 5,
          column: 3,
          severity: .error,
        )
      ],
      macros: viewModelOnlyV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class ObservableStateViewModel {
        @Observable
        final class State {}
        let state = State()
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class ObservableStateViewModel {
          @Observable
          final class State {}
          let state = State()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(
            domain: "VISOR",
            id: "sourceObservationRequiresPlainState",
          ),
          message: "@ViewModel requires a plain State without @Observable",
          line: 5,
          column: 3,
          severity: .error,
        )
      ],
      macros: viewModelOnlyV11Macros,
    )
  }

  @Test
  func `ViewModels require explicit MainActor isolation`() {
    assertMacroExpansionSwiftTesting(
      """
      @Observable
      @ViewModel
      final class MissingMainActorViewModel {
        final class State {}
        let state = State()
      }
      """,
      expandedSource: """
        @Observable
        final class MissingMainActorViewModel {
          final class State {}
          let state = State()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "viewModelRequiresMainActor"),
          message: "@ViewModel requires the class to be explicitly @MainActor",
          line: 3,
          column: 13,
          severity: .error,
          fixIts: [FixItSpec(message: "add '@MainActor'")],
        )
      ],
      macros: viewModelOnlyV11Macros,
    )
  }

  @Test
  func `Action handling diagnostics remain enforced`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      final class ActionViewModel {
        final class State {}
        enum Action {
          case refresh
        }
        let state = State.init()

        func handle(action: Action) {}
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        final class ActionViewModel {
          @MainActor @VISOR._ViewModelState
          final class State {}
          enum Action {
            case refresh
          }
          let state = State.init()

          func handle(action: Action) {}

            typealias Factory = ViewModelFactory<ActionViewModel>

            let _visorObservationOwnership = VISOR._ViewModelObservationOwnership()

            deinit {
            }
        }

        extension ActionViewModel: @MainActor ViewModel {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "actionWithoutHandle"),
          message:
          "@ViewModel: 'Action' enum declared but no 'handle(_ action: Action)' method found",
          line: 1,
          column: 1,
          severity: .error,
        ),
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "handleWrongLabel"),
          message:
          "@ViewModel: 'handle(action:)' should use an underscore label: 'handle(_ action: Action)'",
          line: 1,
          column: 1,
          severity: .error,
        ),
      ],
      macros: viewModelOnlyV11Macros,
    )
  }

  @Test
  func `Public V11 ViewModels require public State exposure`() {
    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      public final class InternalStateViewModel {
        final class State {
          var count = 0
        }

        public let state = State()
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        public final class InternalStateViewModel {
          final class State {
            var count = 0
          }

          public let state = State()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "viewModelRequiresVisibleState"),
          message: "a public @ViewModel requires public nested State and public let state",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )

    assertMacroExpansionSwiftTesting(
      """
      @MainActor
      @Observable
      @ViewModel
      public final class InternalStatePropertyViewModel {
        public final class State {
          var count = 0
        }

        let state = State()
      }
      """,
      expandedSource: """
        @MainActor
        @Observable
        public final class InternalStatePropertyViewModel {
          public final class State {
            var count = 0
          }

          let state = State()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          id: MessageID(domain: "VISOR", id: "viewModelRequiresVisibleState"),
          message: "a public @ViewModel requires public nested State and public let state",
          line: 1,
          column: 1,
          severity: .error,
        )
      ],
      macros: viewModelV11Macros,
    )
  }

}
#endif
