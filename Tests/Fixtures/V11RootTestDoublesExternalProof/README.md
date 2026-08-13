# Root VISORTestDoubles external proof

This package depends on the repository's real, independent
`VISORTestDoubles` product and sets `packageAccess: false` for both targets.
The `VISORTestDoubles` target depends only on the shared `VISORMacros` target
and uses the standard `Observation` and `os` modules. This fixture's production
module imports only `VISORTestDoubles`: it declares a public ordinary stub with
module-qualified custom defaults and a public `.sendable` spy.

The test target depends on and imports only the production models (plus Swift
Testing). It verifies that both generated public types cross a genuine module
boundary, and that the Sendable spy's synchronised storage records concurrent
calls without losing updates.

Both external tests pass in debug and release. The root product's three focused
tests also pass in both configurations, covering qualified ordinary-stub
defaults, concurrent Sendable-spy recording and `StubSequence` ordering.

Test-double declarations live only in `VISORTestDoubles`. There is no umbrella
or re-export between products, so production modules do not acquire testing
support through `VISOR` and test targets import the dedicated product directly.

The Sendable storage retires its complete pre-mutation State after unlocking,
preventing a displaced reference's deinitialiser from re-entering the same
non-recursive lock while it is held. An existing root runtime regression proves
that narrow retirement behaviour in the dedicated product; neither
this fixture's concurrent-call test nor that regression claims fairness,
throughput or safety for arbitrary locking designs.

Run it from the repository root after building the root product:

```sh
swift test --package-path Tests/Fixtures/V11RootTestDoublesExternalProof
swift test -c release --package-path Tests/Fixtures/V11RootTestDoublesExternalProof
```
