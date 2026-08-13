# VISOR 11 external Swift 6.2 compile proof

This package is a genuine downstream consumer of `V11CompileProof`. Every
consumer target disables SwiftPM package access, imports only public products
and exercises macro expansion in the downstream module.

It proves that ordinary consumers need neither `@testable import`, SPI imports
nor package-visible implementation access to use the generated State gateway,
generated observation recipe and source-fenced testing DSL.

The package exercises all four product dependency paths. `VISORObservation`
backs a naturally isolated actor service that constructs an
`ObservationChannel`, exposes a nonisolated `ObservationSource`, publishes
synchronously and permits downstream point-in-time snapshot reads.
This historical prototype's `VISORTestDoubles` target remains a marker. The
root package now integrates the real independent product and proves it through
the separate `V11RootTestDoublesExternalProof` package; this fixture's marker is
not evidence against that root integration.

This proves the ordinary public channel/source surface and product boundaries.
Under both nonisolated and MainActor-by-default target settings, downstream
macro expansion generates a source-backed Bound projection and Reaction, then
`observe` reconciles them before entering its body and `perform` fences the
published revision before returning. It also generates a LazyViewModel that
names only VISOR's opaque production-owner View bridge; downstream code does
not obtain its concrete host or lifecycle controls. The same downstream slice
passes in debug and release builds. The four accepted v11.0 source declaration
spellings are `@Bound(source:)`, `@Bound(source:selecting:)`,
`@Reaction(source:)` and `@Reaction(source:selecting:)`. Source-backed Polled,
debounce and throttle markers are outside v11.0: cooperative polling belongs to
the producer-owned `ObservationSource` consumed through Bound or Reaction, and
other delayed work uses explicit injected-clock structured ownership outside
the source fence.

The generated witness can populate VISOR's public underscored
`_ObservationRecipeVisitor` only when VISOR supplies it. Negative probes prove
that downstream code cannot construct that visitor or name the package-only
recipe, and cannot reach the raw session or lane controls.

The provider fixture separately exercises
`ObservationChannel(_:groupedWith:)`, the underscored raw and grouped control
planes and a hand-written heterogeneous session. Those grouped operations do
not provide atomic batch publication. The provider also proves stored startup
ownership, scoped pause and supervised session teardown in that hand-written
runtime. This downstream package does not itself exercise grouped construction
or repeat the provider's adversarial session-lifecycle matrix. The provider
additionally stress-tests lock-linearised direct and grouped contention,
post-lock snapshot retirement and same-session handler-context re-entrancy;
this downstream package does not exercise those runtime paths. The provider's
Stage D slice additionally exercises generated recipes over two heterogeneous
sources, source-identity merging, projection and Reaction ordering, async
Reaction acknowledgement, post-startup failure/lifecycle revalidation before
readiness, source-fenced journal windows, failure/cancellation lifecycle,
overlap rejection and stale-handle release. This downstream package proves the
basic generated bridge and scoped testing path rather than repeating that entire
lifecycle matrix.

The provider's passing Stage H slice additionally proves private phase-specific
control-plane deadlines. Its production `ContinuousClock` captures an absolute
deadline before synchronous preparation, the watchdog publishes its race
outcome off MainActor, and a due fence skips a source checkpoint when expiry has
won at the pre-cut linearisation check. If that check wins first, the cut may
complete and later expiry still tears down. It also proves
cancellation/first-cause ordering, opening/closing perform attribution,
readiness/teardown observe attribution and the deliberate absence of deadlines
around user actions and closed expectations. The downstream package does not
repeat those provider-only runtime paths.

The provider also distinguishes bounded API return from true join. On teardown
expiry one supervisor retains the old graph; the production identity lease
remains releasing and the testing State keeps a dormant write-discarding
reservation until eventual join, so neither a new owner nor a new testing scope
can overlap stale work. A false-to-true policy request queued before expiry
starts one fresh generation only after that join. The provider separately
proves the Stage F complete-or-fail active-window guard and fixed-size metadata-
only outside-window ring, the cancellation-safe A-to-B-to-C ownership hand-off
and a mounted macOS host's readiness gating and joined root-removal teardown.

Neither prototype fixture proves arbitrary custom/composite sources, the root
package's real production SwiftUI owner or environment-to-policy wiring, or
the Align background-presentation migration. The root `VISORObservation`
source/channel layer, generated State gateway, v11 `@ViewModel`
recipe/session bridge, `VISORTesting`
product, independent `VISORTestDoubles` product and structured production owner
are integrated separately. The root production `VISOR` target does not use
`.defaultIsolation(MainActor.self)`. Focused root paths and the
external nonisolated and MainActor-by-default consumer paths pass in debug and
release. Root `@LazyViewModel(VM.self, observationPolicy:)`
keeps its unchanged first-argument spelling and selects the opaque structured
runtime bridge. Root mounted tests cover that lifecycle; the real root gateway
fixture compiles the source-backed
path under both consumer isolation defaults and exercises macro-synthesised
empty outer and State deinitialisers in Swift 6.2.4 release builds. Root macro
snapshots preserve an unconditional user deinitialiser and fail closed on a
conditional one. A separate mounted root macOS test injects
active → background → active → inactive → active through `.pauseWhenInactive`
and proves disabled publication suppression, readiness/latest reconciliation,
exact zero/one source-subscription counts and joined lease teardown. That root
proof is intentionally limited to the controlled macOS host path; it does not
extend this prototype fixture's claims or prove arbitrary platform scene
scheduling and Align presentation/renderer behaviour.

The real test-double product is proved separately in debug and release with
package access disabled. Its production fixture imports only
`VISORTestDoubles`, uses module-qualified custom defaults and declares an
ordinary stub plus a Sendable spy.

`V11RootGatewayExternalProof` exercises the real root gateway, while
`V11RootTestingExternalProof` exercises the real public source-fenced testing
path under both isolation defaults in debug and release. This downstream
package proves compilation through the prototype's complete opaque bridge, not
the provider's adversarial deadline, full Stage F/G resource/parity or owner
runtime matrices. Deliberate negative
access-control probes separately prove
that descriptor debug name, identity and reference-eligibility metadata, the
package recipe and the raw observation session and lane controls remain
package-inaccessible; the provider and downstream probes also cover the
accepted flat nested/computed-selector boundary.

Run it with:

```sh
swift test --package-path Tests/Fixtures/V11ExternalCompileProof
```

Run the expected-failure access-control matrix with:

```sh
Tests/Fixtures/V11ExternalCompileProof/verify-access-control.sh
```
