# Root VISORTestDoubles external proof

This package depends on the repository's real, independent
`VISORTestDoubles` product. Its public-boundary target pair sets
`packageAccess: false`; the production module imports only
`VISORTestDoubles` and declares a public ordinary stub with module-qualified
custom defaults and a public `.sendable` spy. The product itself depends only
on the shared `VISORMacros` target and the standard `Observation` and `os`
modules.

A second target pair leaves package access enabled. Its model target declares
an ordinary package stub and a Sendable package spy, while its consumer test
target imports those generated peers and constructs them across a real target
boundary. This proves that both generated package types expose a usable
package initialiser.

The public-boundary test target depends on and imports only the production
models (plus Swift Testing). It verifies that both generated public types cross
a genuine module boundary, and that the Sendable spy's synchronised storage
records concurrent calls without losing updates.

Both boundary suites pass in debug and release. The root product's three
focused tests also pass in both configurations, covering qualified
ordinary-stub defaults, concurrent Sendable-spy recording and `StubSequence`
ordering.

The root runtime test target is nonisolated by default and enables
`NonisolatedNonsendingByDefault`, so ordinary async doubles remain on their
caller's actor. Requirements that must leave that actor spell `@concurrent`
explicitly. This fixture's dedicated MainActor-by-default target proves that
ordinary async generated peers also retain an implicitly isolated protocol's
execution domain across a module boundary.

Test-double declarations live only in `VISORTestDoubles`. There is no umbrella
or re-export between products, so production modules do not acquire testing
support through `VISOR` and test targets import the dedicated product directly.

The Sendable storage borrows reads and retires only values selected before a
mutation. Generated setters and call recorders therefore keep displaced
references alive until after unlocking without internally sharing every call
history buffer before an append. Root runtime regressions prove both the
re-entrant deinitialiser boundary and selective copy-on-write behaviour;
neither this fixture's concurrent-call test nor those regressions claims
fairness, throughput or safety for arbitrary locking designs.

Run it from the repository root after building the root product:

```sh
swift test --package-path Tests/Fixtures/V11RootTestDoublesExternalProof
swift test -c release --package-path Tests/Fixtures/V11RootTestDoublesExternalProof
```
