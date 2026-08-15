import SwiftSyntaxMacros
import Testing
@testable import VISORMacros

@Suite("ObservationState macro")
struct ObservationStateMacroTests {
  private let macros: [String: Macro.Type] = [
    "ObservationState": ObservationStateMacro.self,
  ]

  @Test
  func `A stored snapshot owns a channel and exposes its source`() {
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
            @storageRestrictions(accesses: _playbackChannel)
            init(initialValue) {
              _playbackChannel.publish(initialValue)
            }
            get {
              _playbackChannel.source.currentSnapshot()
            }
            set {
              _playbackChannel.publish(newValue)
            }
        }

        private let _playbackChannel:
          VISORObservation.ObservationChannel<PlaybackSnapshot> =
          VISORObservation.ObservationChannel(.stopped)

        public var playbackSource:
          VISORObservation.ObservationSource<PlaybackSnapshot> {
          _playbackChannel.source
        }
      }
      """,
      macros: macros)
  }

  @Test
  func `A protocol State annotation marks an explicit source pair`() {
    assertMacroExpansionSwiftTesting(
      """
      protocol PlaybackService {
        @ObservationState
        var playback: PlaybackSnapshot { get }
        var playbackSource: ObservationSource<PlaybackSnapshot> { get }
      }
      """,
      expandedSource: """
      protocol PlaybackService {
        var playback: PlaybackSnapshot { get }
        var playbackSource: ObservationSource<PlaybackSnapshot> { get }
      }
      """,
      macros: macros)
  }

  @Test
  func `Observation State requires an explicit stored type`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Player {
        @ObservationState
        var playback = PlaybackSnapshot.stopped
      }
      """,
      expandedSource: """
      final class Player {
        var playback = PlaybackSnapshot.stopped
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ObservationState requires one non-static protocol property requirement or stored var with an explicit type and initial value inside a class or actor",
          line: 2,
          column: 3),
      ],
      macros: macros)
  }
}
