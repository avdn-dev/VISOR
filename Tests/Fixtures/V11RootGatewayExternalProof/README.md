# VISOR 11 gateway boundary proof

This downstream Swift 6.2 package verifies that the public
`VISORObservation` and `VISOR` APIs compile without package, SPI, or testable
access. It covers both nonisolated and MainActor-by-default consumers in debug
and release, including generated State routing, source-backed ViewModels,
`@LazyViewModel`, push-only navigation scenes, and public channel iteration.

`verify-access-control.sh` separately proves that generated descriptor shells
remain usable while Router hierarchy state, recipe, session, source-control,
and erased-field internals remain inaccessible.

```sh
swift test --package-path Tests/Fixtures/V11RootGatewayExternalProof
swift build -c release --package-path Tests/Fixtures/V11RootGatewayExternalProof
sh Tests/Fixtures/V11RootGatewayExternalProof/verify-access-control.sh
```
