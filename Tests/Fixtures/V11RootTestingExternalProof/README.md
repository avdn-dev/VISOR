# Root VISORTesting external proof

This package depends on the repository's real `VISOR`, `VISORObservation`, and
`VISORTesting` products. Every fixture target disables implicit package access.

It verifies in debug and release that public, source-backed `@ViewModel`
expansions can cross module boundaries and use `observe`, both action and
closure `perform` overloads, `hasExactChanges`, and `alwaysSatisfies` from
consumer targets with nonisolated and MainActor-by-default isolation. Its Bound
projection and Reaction are reconciled before the body, and a publication made
inside `perform` is source-fenced before the closed window is inspected. The
consumer needs no package, SPI or testable access to VISOR's recipe, session or
journal controls.

The real production `VISOR` target does not use
`.defaultIsolation(MainActor.self)`. This fixture's two target settings form
the downstream half of the debug/release proof that the root product does not
depend on inheriting either consumer isolation default.

The exercised model and State declarations deliberately retain unconditional
empty `deinit {}` bodies. The macros preserve those user declarations. For a
source-backed outer ViewModel or State without one, the root macros now
synthesise an empty deinitialiser to avoid a Swift 6.2.4 release-optimiser crash
involving explicitly MainActor classes under default-MainActor compilation;
`V11RootGatewayExternalProof` exercises that synthesis in release under both
consumer isolation defaults. A conditional deinitialiser fails closed because
it cannot guarantee that the workaround exists in every configuration. This is
an implementation-only toolchain workaround, not public API, teardown logic, a
lifetime guarantee or a v11 semantic requirement.

The `RootTestingSelectorProbe` target also verifies that the real generated
selector API remains flat: inaccessible stored fields, computed properties,
nested key paths and the removed projecting overload must all fail to compile.

This fixture does not repeat every root lifecycle/deadline test. It also does
not exercise the root production SwiftUI owner itself. Mounted root tests
separately cover the structured
`@LazyViewModel(VM.self)` path. A deterministic root
macOS host additionally injects
active → background → active → inactive → active for `.pauseWhenInactive`,
proving disabled publication suppression, readiness/latest reconciliation,
exact zero/one source-subscription counts and joined lease teardown. That
controlled environment proof is separate from this testing fixture and does
not cover arbitrary scene scheduling, other platforms or Align presentation
and renderer migration. The independently integrated `VISORTestDoubles` product
is covered by `V11RootTestDoublesExternalProof`, not this fixture.

Run it from the repository root:

```sh
swift test --package-path Tests/Fixtures/V11RootTestingExternalProof
swift test -c release --package-path Tests/Fixtures/V11RootTestingExternalProof
sh Tests/Fixtures/V11RootTestingExternalProof/verify-selector-contracts.sh
```
