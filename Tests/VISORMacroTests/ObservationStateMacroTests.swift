import SwiftSyntaxMacros
import Testing
@testable import VISORMacros

@Suite("ObservationState macro")
struct ObservationStateMacroTests {
  private let macros: [String: Macro.Type] = [
    "ObservationState": ObservationStateMacro.self,
  ]

  @Test
  func `A source declaration synthesises private producer storage`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Player {
        @ObservationState(initial: PlaybackSnapshot.stopped)
        public var playback: ObservationSource<PlaybackSnapshot>

        func stop() {
          publishPlayback(.stopped)
        }
      }
      """,
      expandedSource: """
      final class Player {
        public var playback: ObservationSource<PlaybackSnapshot> {
            get {
              __visorObservationStatePlaybackChannel.source
            }
        }

        private let __visorObservationStatePlaybackChannel:
          VISORObservation.ObservationChannel<PlaybackSnapshot> =
          VISORObservation.ObservationChannel(PlaybackSnapshot.stopped)

        private func publishPlayback(
          _ snapshot: sending PlaybackSnapshot
        ) {
          __visorObservationStatePlaybackChannel.publish(snapshot)
        }

        func stop() {
          publishPlayback(.stopped)
        }
      }
      """,
      macros: macros)
  }

  @Test
  func `A nonisolated source synthesises nonisolated producer storage`() {
    assertMacroExpansionSwiftTesting(
      """
      actor Player {
        @ObservationState(initial: PlaybackSnapshot.stopped)
        nonisolated public var playback: VISORObservation.ObservationSource<PlaybackSnapshot>
      }
      """,
      expandedSource: """
      actor Player {
        nonisolated public var playback: VISORObservation.ObservationSource<PlaybackSnapshot> {
            get {
              __visorObservationStatePlaybackChannel.source
            }
        }

        nonisolated private let __visorObservationStatePlaybackChannel:
          VISORObservation.ObservationChannel<PlaybackSnapshot> =
          VISORObservation.ObservationChannel(PlaybackSnapshot.stopped)

        private func publishPlayback(
          _ snapshot: sending PlaybackSnapshot
        ) {
          __visorObservationStatePlaybackChannel.publish(snapshot)
        }
      }
      """,
      macros: macros)
  }

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
  func `A protocol source declaration carries its test-double initial State`() {
    assertMacroExpansionSwiftTesting(
      """
      protocol PlaybackService {
        @ObservationState(initial: PlaybackSnapshot.stopped)
        var playback: ObservationSource<PlaybackSnapshot> { get }
      }
      """,
      expandedSource: """
      protocol PlaybackService {
        var playback: ObservationSource<PlaybackSnapshot> { get }
      }
      """,
      macros: macros)
  }

  @Test
  func `A source backing name does not collide with a conventional channel`() {
    assertMacroExpansionSwiftTesting(
      """
      final class Player {
        @ObservationState(initial: PlaybackSnapshot.stopped)
        var playback: ObservationSource<PlaybackSnapshot>

        private let _playbackChannel = ExistingChannel()
      }
      """,
      expandedSource: """
      final class Player {
        var playback: ObservationSource<PlaybackSnapshot> {
            get {
              __visorObservationStatePlaybackChannel.source
            }
        }

        private let __visorObservationStatePlaybackChannel:
          VISORObservation.ObservationChannel<PlaybackSnapshot> =
          VISORObservation.ObservationChannel(PlaybackSnapshot.stopped)

        private func publishPlayback(
          _ snapshot: sending PlaybackSnapshot
        ) {
          __visorObservationStatePlaybackChannel.publish(snapshot)
        }

        private let _playbackChannel = ExistingChannel()
      }
      """,
      macros: macros)
  }

  @Test
  func `A source protocol requirement is read-only`() {
    assertMacroExpansionSwiftTesting(
      """
      protocol PlaybackService {
        @ObservationState(initial: PlaybackSnapshot.stopped)
        var playback: ObservationSource<PlaybackSnapshot> { get set }
      }
      """,
      expandedSource: """
      protocol PlaybackService {
        var playback: ObservationSource<PlaybackSnapshot> { get set }
      }
      """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@ObservationState requires either a stored value with an explicit type and initial value, or an ObservationSource property with an explicit initial: argument",
          line: 2,
          column: 3),
      ],
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
            "@ObservationState requires either a stored value with an explicit type and initial value, or an ObservationSource property with an explicit initial: argument",
          line: 2,
          column: 3),
      ],
      macros: macros)
  }
}
