# VISOR agent guide

## Map

- `Package.swift`: products and dependency boundaries.
- `Sources/VISORObservation`: observation primitives.
- `Sources/VISOR`: ViewModel, SwiftUI ownership, and navigation.
- `Sources/VISORTesting`: observation test support.
- `Sources/VISORTestDoubles`: generated stubs and spies.
- `Sources/VISORMacros`: macros shared by the products above.
- `Tests/<Target>Tests`: root tests.
- `Tests/Fixtures/V11Root*ExternalProof`: downstream API-boundary tests.
- `Sources/VISOR/VISOR.docc`: architecture and behavioural documentation.
- `MIGRATION_V11.md`: VISOR 10 migration contract.

## Rules

- Use Australian English in text and code you touch.
- Preserve the four-product dependency boundaries.
- Test public macro and access-level changes through the relevant external
  fixture as well as root tests.
- Use SwiftPM's normal `.build` directory and Xcode's default DerivedData.
- Do not run simulator tests; this repository has no simulator test suite.
- Use one-line Conventional Commit messages.
- Update the relevant README, DocC, or migration guide when behaviour changes.

## Validate

Use focused `swift test` filters while iterating. Before handoff, run:

```sh
scripts/validate.sh
```
