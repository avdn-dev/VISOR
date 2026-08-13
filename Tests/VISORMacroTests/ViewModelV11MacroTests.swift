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
        macros: viewModelV11Macros)
    }

    @Test
    func `Source entries are grouped with projections before reactions`() {
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
              source: \\SourceViewModel.service.source,
              selecting: \\Snapshot.label)
            var label = ""

            @Bound(source: \\SourceViewModel.status.source)
            var status = 0
          }

          let state = State()
          let service: Service
          let status: StatusService

          @Reaction(
            source: \\SourceViewModel.service.source,
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
        macros: viewModelV11Macros)
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
        macros: viewModelV11Macros)
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
              id: "conditionalDeinitialiserUnsupported"),
            message:
              "@ViewModel types require an unconditional deinit; put conditional logic inside its body",
            line: 9,
            column: 3,
            severity: .error)
        ],
        macros: viewModelV11Macros)
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
            severity: .error)
        ],
        macros: viewModelV11Macros)
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
              id: "invalidSourceBoundPlacement"),
            message: "@Bound(source:) is only supported on a direct member of @ViewModel.State",
            line: 2,
            column: 3,
            severity: .error)
        ],
        macros: sourceEntryV11Macros)

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
              id: "invalidSourceBoundDeclaration"),
            message:
              "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
            line: 4,
            column: 5,
            severity: .error)
        ],
        macros: sourceEntryV11Macros)
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
              id: "invalidSourceReactionPlacement"),
            message: "@Reaction(source:) is only supported on a direct @ViewModel member",
            line: 2,
            column: 3,
            severity: .error)
        ],
        macros: sourceEntryV11Macros)

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
              id: "invalidSourceReactionDeclaration"),
            message:
              "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
            line: 3,
            column: 3,
            severity: .error)
        ],
        macros: sourceEntryV11Macros)
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
            severity: .error),
          DiagnosticSpec(
            id: MessageID(domain: "VISOR", id: "invalidSourceBoundDeclaration"),
            message:
              "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
            line: 9,
            column: 5,
            severity: .error),
          DiagnosticSpec(
            id: MessageID(domain: "VISOR", id: "invalidSourceBoundDeclaration"),
            message:
              "@Bound requires one ordinary stored State property using @Bound(source:) or @Bound(source:selecting:)",
            line: 12,
            column: 5,
            severity: .error),
        ],
        macros: viewModelV11Macros)
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
            severity: .error),
          DiagnosticSpec(
            id: MessageID(domain: "VISOR", id: "invalidSourceReactionDeclaration"),
            message:
              "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
            line: 13,
            column: 3,
            severity: .error),
          DiagnosticSpec(
            id: MessageID(domain: "VISOR", id: "invalidSourceReactionDeclaration"),
            message:
              "@Reaction requires one nonthrowing Void method parameter using @Reaction(source:) or @Reaction(source:selecting:)",
            line: 16,
            column: 3,
            severity: .error),
        ],
        macros: viewModelV11Macros)
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
            severity: .error)
        ],
        macros: viewModelV11Macros)
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
            severity: .error)
        ],
        macros: viewModelOnlyV11Macros)

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
            severity: .error)
        ],
        macros: viewModelOnlyV11Macros)

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
            severity: .error)
        ],
        macros: viewModelOnlyV11Macros)

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
            severity: .error)
        ],
        macros: viewModelOnlyV11Macros)

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
              id: "sourceObservationRequiresPlainState"),
            message: "@ViewModel requires a plain State without @Observable",
            line: 5,
            column: 3,
            severity: .error)
        ],
        macros: viewModelOnlyV11Macros)
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
            fixIts: [FixItSpec(message: "add '@MainActor'")])
        ],
        macros: viewModelOnlyV11Macros)
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
          let state = State()

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
            let state = State()

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
            severity: .error),
          DiagnosticSpec(
            id: MessageID(domain: "VISOR", id: "handleWrongLabel"),
            message:
              "@ViewModel: 'handle(action:)' should use an underscore label: 'handle(_ action: Action)'",
            line: 1,
            column: 1,
            severity: .error),
        ],
        macros: viewModelOnlyV11Macros)
    }

    @Test
    func `Removed observation marker forms fail closed`() {
      assertMacroExpansionSwiftTesting(
        """
        @MainActor
        @Observable
        @ViewModel
        final class LegacyMarkerViewModel {
          final class State {
            @Bound(\\LegacyMarkerViewModel.service.value)
            var value = 0
            @Polled(\\LegacyMarkerViewModel.monitor.level)
            var level = 0
          }

          let state = State()

          @Reaction(\\LegacyMarkerViewModel.service.value)
          func valueChanged(_ value: Int) {}
        }
        """,
        expandedSource: """
          @MainActor
          @Observable
          final class LegacyMarkerViewModel {
            final class State {
              @Bound(\\LegacyMarkerViewModel.service.value)
              var value = 0
              @Polled(\\LegacyMarkerViewModel.monitor.level)
              var level = 0
            }

            let state = State()

            @Reaction(\\LegacyMarkerViewModel.service.value)
            func valueChanged(_ value: Int) {}
          }
          """,
        diagnostics: [
          DiagnosticSpec(
            id: MessageID(
              domain: "VISOR",
              id: "sourceBackedBoundRequiresSource"),
            message: "@Bound requires the source: form",
            line: 6,
            column: 5,
            severity: .error),
          DiagnosticSpec(
            id: MessageID(
              domain: "VISOR",
              id: "sourceBackedPolledUnsupported"),
            message:
              "@Polled is unsupported; use an ObservationSource or an explicit clock-owned activity",
            line: 8,
            column: 5,
            severity: .error),
          DiagnosticSpec(
            id: MessageID(
              domain: "VISOR",
              id: "sourceBackedReactionRequiresSource"),
            message: "@Reaction requires the source: form",
            line: 14,
            column: 3,
            severity: .error),
        ],
        macros: viewModelOnlyV11Macros)
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
            severity: .error)
        ],
        macros: viewModelV11Macros)

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
            severity: .error)
        ],
        macros: viewModelV11Macros)
    }

  }
#endif
