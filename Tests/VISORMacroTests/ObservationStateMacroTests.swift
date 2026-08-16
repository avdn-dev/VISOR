import SwiftSyntaxMacros
import Testing
@testable import VISORMacros

@Suite("ObservationState macro")
struct ObservationStateMacroTests {
  private let macros: [String: Macro.Type] = [
    "ObservationState": ObservationStateMacro.self,
    "ObservationProtocol": ObservationProtocolMacro.self,
  ]

  @Test
  func `A stored State publishes assignments as snapshots`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Player {
        @ObservationState
        public private(set) var playback: PlaybackSnapshot = .stopped
      }
      """,
      expandedSource: """
      final class Player {
        public private(set) var playback: PlaybackSnapshot {
            @storageRestrictions(initializes: __visorObservationStatePlaybackChannel)
            init(initialValue) {
              __visorObservationStatePlaybackChannel = VISORObservation.ObservationChannel(initialValue)
            }
            get {
              __visorObservationStatePlaybackChannel.source.currentSnapshot()
            }
            set {
              __visorObservationStatePlaybackChannel.publish(newValue)
            }
        }

        nonisolated(unsafe) private var __visorObservationStatePlaybackChannel:
          VISORObservation.ObservationChannel<PlaybackSnapshot>

        nonisolated public var playbackSnapshots:
          VISORObservation.ObservationSource<PlaybackSnapshot> {
          __visorObservationStatePlaybackChannel.source
        }
      }
      """,
      macros: macros)
  }

  @Test
  func `A scalar State can expose values`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Counter {
        @ObservationState(observedAs: .values)
        var count: Int = 0
      }
      """,
      expandedSource: """
      final class Counter {
        var count: Int {
            @storageRestrictions(initializes: __visorObservationStateCountChannel)
            init(initialValue) {
              __visorObservationStateCountChannel = VISORObservation.ObservationChannel(initialValue)
            }
            get {
              __visorObservationStateCountChannel.source.currentSnapshot()
            }
            set {
              __visorObservationStateCountChannel.publish(newValue)
            }
        }

        nonisolated(unsafe) private var __visorObservationStateCountChannel:
          VISORObservation.ObservationChannel<Int>

        nonisolated var countValues:
          VISORObservation.ObservationSource<Int> {
          __visorObservationStateCountChannel.source
        }
      }
      """,
      macros: macros)
  }

  @Test
  func `A custom plural names the generated sequence`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Permissions {
        @ObservationState(observedAs: .named("permissionStatuses"))
        var status: PermissionSnapshot = .undetermined
      }
      """,
      expandedSource: """
      final class Permissions {
        var status: PermissionSnapshot {
            @storageRestrictions(initializes: __visorObservationStateStatusChannel)
            init(initialValue) {
              __visorObservationStateStatusChannel = VISORObservation.ObservationChannel(initialValue)
            }
            get {
              __visorObservationStateStatusChannel.source.currentSnapshot()
            }
            set {
              __visorObservationStateStatusChannel.publish(newValue)
            }
        }

        nonisolated(unsafe) private var __visorObservationStateStatusChannel:
          VISORObservation.ObservationChannel<PermissionSnapshot>

        nonisolated var permissionStatuses:
          VISORObservation.ObservationSource<PermissionSnapshot> {
          __visorObservationStateStatusChannel.source
        }
      }
      """,
      macros: macros)
  }

  @Test
  func `An initialiser can establish the baseline`() {
    assertMacroExpansionSwiftTesting(
      """
      actor Player {
        @ObservationState
        nonisolated public private(set) var playback: PlaybackSnapshot

        init() {
          playback = .stopped
        }
      }
      """,
      expandedSource: """
      actor Player {
        nonisolated public private(set) var playback: PlaybackSnapshot {
            @storageRestrictions(initializes: __visorObservationStatePlaybackChannel)
            init(initialValue) {
              __visorObservationStatePlaybackChannel = VISORObservation.ObservationChannel(initialValue)
            }
            get {
              __visorObservationStatePlaybackChannel.source.currentSnapshot()
            }
            set {
              __visorObservationStatePlaybackChannel.publish(newValue)
            }
        }

        nonisolated private let __visorObservationStatePlaybackChannel:
          VISORObservation.ObservationChannel<PlaybackSnapshot>

        nonisolated public var playbackSnapshots:
          VISORObservation.ObservationSource<PlaybackSnapshot> {
          __visorObservationStatePlaybackChannel.source
        }

        init() {
          playback = .stopped
        }
      }
      """,
      macros: macros)
  }

  @Test
  func `An Observable State participates in Apple Observation`() {
    assertMacroExpansionSwiftTesting(
      """
      @Observable
      final class Player {
        @ObservationState
        @ObservationIgnored
        var playback: PlaybackSnapshot = .stopped
      }
      """,
      expandedSource: """
      @Observable
      final class Player {
        @ObservationIgnored
        var playback: PlaybackSnapshot {
            @storageRestrictions(initializes: __visorObservationStatePlaybackChannel)
            init(initialValue) {
              __visorObservationStatePlaybackChannel = VISORObservation.ObservationChannel(initialValue)
            }
            get {
              access(keyPath: \\.playback)
              return __visorObservationStatePlaybackChannel.source.currentSnapshot()
            }
            set {
              withMutation(keyPath: \\.playback) {
                __visorObservationStatePlaybackChannel.publish(newValue)
              }
            }
        }

        nonisolated(unsafe) private var __visorObservationStatePlaybackChannel:
          VISORObservation.ObservationChannel<PlaybackSnapshot>

        nonisolated var playbackSnapshots:
          VISORObservation.ObservationSource<PlaybackSnapshot> {
          __visorObservationStatePlaybackChannel.source
        }
      }
      """,
      macros: macros)
  }

  @Test
  func `An Observable State requires the exclusion attribute in order`() {
    assertMacroExpansionSwiftTesting(
      """
      @Observable
      final class Player {
        @ObservationIgnored
        @ObservationState
        var playback: PlaybackSnapshot = .stopped
      }
      """,
      expandedSource: """
      @Observable
      final class Player {
        @ObservationIgnored
        var playback: PlaybackSnapshot = .stopped
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ObservationState properties in an @Observable type require @ObservationIgnored immediately below @ObservationState",
          line: 3,
          column: 3),
      ],
      macros: macros)
  }

  @Test
  func `A protocol State synthesises its observation requirement`() {
    assertMacroExpansionSwiftTesting(
      """
      @ObservationProtocol
      protocol CounterService {
        @ObservationState(observedAs: .values)
        var count: Int { get }
      }
      """,
      expandedSource: """
      protocol CounterService {
        var count: Int { get }

          nonisolated var countValues: VISORObservation.ObservationSource<Int> {
              get
          }
      }
      """,
      macros: macros)
  }

  @Test
  func `A source cannot be mistaken for producer State`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Player {
        @ObservationState(initial: PlaybackSnapshot.stopped)
        var playback: ObservationSource<PlaybackSnapshot>
      }
      """,
      expandedSource: """
      final class Player {
        var playback: ObservationSource<PlaybackSnapshot>
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ObservationState requires mutable class or actor State with an explicit type and no initial: argument, or a get-only protocol State",
          line: 2,
          column: 3),
      ],
      macros: macros)
  }

  @Test
  func `Concrete State uses normal Swift initialisation`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Counter {
        @ObservationState(initial: 0)
        var count: Int
      }
      """,
      expandedSource: """
      final class Counter {
        var count: Int
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ObservationState requires mutable class or actor State with an explicit type and no initial: argument, or a get-only protocol State",
          line: 2,
          column: 3),
      ],
      macros: macros)
  }

  @Test
  func `Storage-only modifiers are rejected`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Counter {
        @ObservationState
        lazy var count: Int = 0
      }
      """,
      expandedSource: """
      final class Counter {
        lazy var count: Int = 0
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ObservationState requires mutable class or actor State with an explicit type and no initial: argument, or a get-only protocol State",
          line: 2,
          column: 3),
      ],
      macros: macros)
  }

  @Test
  func `A protocol State is read-only and supplies an initial value`() {
    assertMacroExpansionSwiftTesting(
      """
      @ObservationProtocol
      protocol CounterService {
        @ObservationState
        var count: Int { get set }
      }
      """,
      expandedSource: """
      protocol CounterService {
        var count: Int { get set }
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ObservationState requires mutable class or actor State with an explicit type and no initial: argument, or a get-only protocol State",
          line: 3,
          column: 3),
      ],
      macros: macros)
  }

  @Test
  func `A protocol State requires its type-level observation macro`() {
    assertMacroExpansionSwiftTesting(
      """
      protocol CounterService {
        @ObservationState(initial: 0)
        var count: Int { get }
      }
      """,
      expandedSource: """
      protocol CounterService {
        var count: Int { get }
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "protocol @ObservationState requirements require @ObservationProtocol on the enclosing protocol",
          line: 2,
          column: 3),
      ],
      macros: macros)
  }

  @Test
  func `ObservationProtocol only accepts protocols`() {
    assertMacroExpansionSwiftTesting(
      """
      @ObservationProtocol
      final class Counter {}
      """,
      expandedSource: """
      final class Counter {}
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ObservationProtocol can only be attached to a protocol",
          line: 1,
          column: 1),
      ],
      macros: macros)
  }

  @Test
  func `A custom sequence name must be a free Swift identifier`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Counter {
        @ObservationState(observedAs: .named("count"))
        var count: Int = 0
      }
      """,
      expandedSource: """
      final class Counter {
        var count: Int = 0
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ObservationState cannot generate 'count' because that member name is already in use",
          line: 2,
          column: 3),
      ],
      macros: macros)
  }

}
