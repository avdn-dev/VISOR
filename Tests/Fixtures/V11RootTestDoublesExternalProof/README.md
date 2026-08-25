# VISORTestDoubles boundary proof

This downstream package verifies public and package generated peers across
real target boundaries in debug and release. It covers ordinary and Sendable
stubs and spies, collision-safe generated names, anonymous and escaped
parameter bindings, protocol isolation, and
synchronised call recording.

The model targets intentionally import only `VISORTestDoubles`. This proves the
product supplies the Apple Observation import required by generated peers.

```sh
swift test --package-path Tests/Fixtures/V11RootTestDoublesExternalProof
swift test -c release --package-path Tests/Fixtures/V11RootTestDoublesExternalProof
```
