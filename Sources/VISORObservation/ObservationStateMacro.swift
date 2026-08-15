/// Declares a producer-owned durable latest-State source.
///
/// Prefer the source-first form for public service APIs. The declared property
/// is the read-only consumer capability; the macro synthesises a private
/// channel and a private `publish<Property>(_)` operation for publishing
/// complete snapshots synchronously:
///
/// ```swift
/// @ObservationState(initial: PlaybackSnapshot.stopped)
/// public var playback: ObservationSource<PlaybackSnapshot>
///
/// func stop() {
///   publishPlayback(.stopped)
/// }
/// ```
///
/// Protocol requirements use the same declaration. `@GenerateStub` and
/// `@GenerateSpy` synthesise the source and a `publish<Property>(_)` control
/// for tests:
///
/// ```swift
/// @GenerateSpy
/// protocol PlaybackService {
///   @ObservationState(initial: PlaybackSnapshot.stopped)
///   var playback: ObservationSource<PlaybackSnapshot> { get }
/// }
/// ```
///
/// The value-first `@ObservationState var playback = ...` spelling remains
/// available for source compatibility. It generates a `<property>Source`, but
/// new public APIs should declare the source directly so their names describe
/// domain State rather than its implementation.
///
/// Prefer one observation State value over several independently published
/// fields when those fields form one coherent domain revision.
/// Keep an explicit `ObservationChannel` for classes whose initialiser can
/// throw before initialisation completes; current Swift toolchains can
/// miscompile partial cleanup for macro-owned storage in that case.
///
/// If the enclosing type also uses `@Observable`, place
/// `@ObservationIgnored` immediately below `@ObservationState`. The compiler
/// expands both macros from the authored declaration, so they would otherwise
/// both try to provide its accessors.
///
/// ```swift
/// @ObservationState(initial: PlaybackSnapshot.stopped)
/// @ObservationIgnored
/// public var playback: ObservationSource<PlaybackSnapshot>
/// ```
@attached(
  accessor,
  names: named(init), named(get), named(set))
@attached(peer, names: arbitrary)
public macro ObservationState<Value: Sendable>(initial: Value) = #externalMacro(
  module: "VISORMacros",
  type: "ObservationStateMacro")

/// Compatibility form for a directly mutated producer value.
///
/// Prefer ``ObservationState(initial:)`` for new public service APIs.
@attached(
  accessor,
  names: named(init), named(get), named(set))
@attached(peer, names: arbitrary)
public macro ObservationState() = #externalMacro(
  module: "VISORMacros",
  type: "ObservationStateMacro")
