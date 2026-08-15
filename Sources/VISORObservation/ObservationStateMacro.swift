/// Makes a stored producer value available as durable latest State.
///
/// Apply `@ObservationState` to one stored `var` with an explicit `Sendable`
/// type and an initial value. Every assignment publishes the new complete
/// value synchronously. Consumers receive the stable generated
/// `<property>Source`.
///
/// On a protocol property requirement, use the same annotation to associate
/// the value with its explicitly named companion source. `@GenerateStub` and
/// `@GenerateSpy` then keep their generated value and source in sync:
///
/// ```swift
/// @GenerateSpy
/// protocol PlaybackService {
///   @ObservationState
///   @DefaultValue(PlaybackSnapshot.stopped)
///   var playback: PlaybackSnapshot { get }
///   var playbackSource: ObservationSource<PlaybackSnapshot> { get }
/// }
/// ```
///
/// ```swift
/// @MainActor
/// final class PlaybackService {
///   @ObservationState
///   public private(set) var playback: PlaybackSnapshot = .stopped
/// }
///
/// // Generated for consumers:
/// // public var playbackSource: ObservationSource<PlaybackSnapshot>
/// ```
///
/// Prefer one observation State value over several independently published
/// fields when those fields form one coherent domain revision.
/// Keep an explicit `ObservationChannel` for classes whose initialiser can
/// throw before initialisation completes; current Swift toolchains can
/// miscompile partial cleanup for macro-owned storage in that case.
///
/// A source-first producer does not need `@Observable`. If its enclosing type
/// still uses `@Observable` for other properties during a migration, place
/// `@ObservationIgnored` immediately below `@ObservationState`; both
/// `@Observable` and `@ObservationState` are accessor macros and cannot own the
/// same property storage.
///
/// ```swift
/// @ObservationState
/// @ObservationIgnored
/// public private(set) var playback: PlaybackSnapshot = .stopped
/// ```
@attached(
  accessor,
  names: named(init), named(get), named(set))
@attached(peer, names: arbitrary)
public macro ObservationState() = #externalMacro(
  module: "VISORMacros",
  type: "ObservationStateMacro")
