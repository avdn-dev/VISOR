# VISORTesting boundary proof

This downstream package verifies `VISORTesting` from nonisolated and
MainActor-by-default test targets with implicit package access disabled. It
exercises `observe`, each `perform` form, exact history, invariants, and the
public error contract in debug and release.

The selector probe confirms that only generated, accessible, top-level State
fields enter the public selector namespace.

```sh
swift test --package-path Tests/Fixtures/V11RootTestingExternalProof
swift test -c release --package-path Tests/Fixtures/V11RootTestingExternalProof
sh Tests/Fixtures/V11RootTestingExternalProof/verify-selector-contracts.sh
```
