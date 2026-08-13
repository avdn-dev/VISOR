# VISOR 11 root observation and State-gateway downstream proof

This separate Swift 6.2 package depends on the real root `VISOR` product. Its
consumer targets disable SwiftPM package access and use ordinary imports only.

The package also consumes the real root `VISORObservation` product, exercises
public channel publication and snapshot reads, and compiles generated-style
recipe registration through the public underscored visitor. It cannot create
that visitor or name session, lane, recipe, or source-control internals.

It compiles and executes the root `_ViewModelState` expansion under both a
nonisolated target default and `MainActor`-by-default. The proof covers inferred
and explicitly typed fields, custom initialisation without a declaration
default, direct State methods, typed routed selectors, value-member write-back,
both SwiftUI `Bindable` spellings and normal Observation invalidation.

The access-control matrix proves that generated descriptor shells can cross the
consumer-module boundary while their name, identity, reference-eligibility and
erased-reader operations remain package-inaccessible. The public underscored
gateway is implementation ABI for downstream macro expansion, not ordinary
consumer vocabulary.

The two model targets also compile the real root `@ViewModel` cascade for a
public source-backed ViewModel. They exercise both whole-snapshot
`@Bound(source:)`/`@Reaction(source:)` entries and projected
`@Bound(source:selecting:)`/`@Reaction(source:selecting:)` entries, along with
the public recipe witness and private package runtime boundary. Public views in
both targets use the ordinary
`@LazyViewModel(VM.self, observationPolicy:)` spelling, with no source-backed
opt-in label, and their generated bodies resolve VISOR's unified bridge to
source-backed ownership. A separate ordinary-import target can form those
public bodies while the generated `viewModel` property remains module-internal.
Both models omit manual model and State deinitialisers so release compilation
also exercises the macro-synthesised empty deinitialisers that work around the
Swift 6.2.4 release optimiser crash under both isolation defaults. Root macro
snapshots separately prove that an unconditional user deinitialiser is
preserved and a conditional deinitialiser fails closed without partial
source-backed expansion.

Mounted root tests, rather than this downstream compile fixture, exercise the
structured owner: it withholds content until readiness, serialises lifecycle
generations and joins observation teardown on root removal.

The real root VISOR target now compiles without a target-wide MainActor default.
This package proves that configuration in debug and release while exercising
consumers with both nonisolated and MainActor-by-default target settings. It
does not prove downstream session execution, VISORTesting runtime behaviour or
the mounted SwiftUI-owner lifecycle.

Run the positive proof with:

```sh
swift test --package-path Tests/Fixtures/V11RootGatewayExternalProof
swift build -c release --package-path Tests/Fixtures/V11RootGatewayExternalProof
```

Run the expected-failure access-control matrix with:

```sh
sh Tests/Fixtures/V11RootGatewayExternalProof/verify-access-control.sh
```
