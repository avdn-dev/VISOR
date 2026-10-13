# ``VISORTestDoubles``

Generate configurable stubs and call-recording spies without depending on the
VISOR production or testing runtimes.

## Overview

Attach `@GenerateStub` or `@GenerateSpy` to a protocol. Generated peers preserve
the protocol's access level and isolation. Use the `.sendable` trait only when
the protocol is `Sendable`; the generated double then uses checked, lock-backed
storage without holding its lock across asynchronous work.

Spies record each call in `calls` and in per-method call counts and received
arguments. Recording is not observable, so a spy called while its caller is
tracked, such as from a SwiftUI update, does not invalidate that caller.
Protocol properties remain observable. To wait for or hold a call, set the
method's implementation closure.

Anonymous parameters receive generated local bindings. Escaped labels and
parameter names retain valid source spelling in the generated witness while
compound generated names use their canonical identifier.

Importing `VISORTestDoubles` also imports Apple Observation, which the macros
need when they emit an observable peer in the declaration's source file.

Override inferred property and method defaults with `@DefaultValue` and
`@DefaultReturn`. Use ``StubSequence`` when successive calls should return a
deterministic series of values.

## Topics

### Generation

- ``GenerateStub(_:)``
- ``GenerateSpy(_:)``
- ``TestDoubleTrait``

### Configuration

- ``DefaultValue(_:)``
- ``DefaultReturn(_:)``
- ``StubSequence``
