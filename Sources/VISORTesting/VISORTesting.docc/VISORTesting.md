# ``VISORTesting``

Fence structured ViewModel actions and assert their complete routed State
mutation history with Swift Testing.

## Overview

Call ``observe(_:sourceLocation:_:)`` inside a Swift Testing test. VISOR starts
and reconciles the ViewModel's generated observation session before invoking
the body, then supplies an ``ObservationTest`` handle for one structured action
at a time.

`perform` establishes a baseline, awaits the complete operation, and fences all
participating sources before expectations inspect the journal. Work launched
without awaiting it is intentionally outside the action window.

Each `perform` window retains at most 8,000 raw State commits by default across
all fields, including equal-value writes. Use
``observe(_:maximumCommitCountPerAction:sourceLocation:_:)`` to choose a larger
positive bound for an intentional high-volume action. Exceeding the bound fails
the complete window closed and poisons the scope rather than returning partial
history.

Use ``ControllableOperation`` for asynchronous dependencies whose ordering a
test must control. Prepare an invocation when its identity or metadata must be
fixed before its task is scheduled, then pass that token to `run` and
`resolve`. The operation is `Sendable` and has no actor-isolation requirement.

Concurrency-control waits cooperate with task cancellation and throw
`CancellationError` rather than retaining a suspended continuation. A
``TestBarrier`` arrival remains counted when its participant is cancelled
after arriving, so later participants can still open the one-shot barrier.

## Topics

### Observation scopes

- ``observe(_:sourceLocation:_:)``
- ``observe(_:maximumCommitCountPerAction:sourceLocation:_:)``
- ``ObservationTest``
- ``ObservationTestError``
- ``VISORObservation/ObservationSource/waitUntil(_:)``

### History matching

- ``ObservationTest/expect(_:hasExactChanges:sourceLocation:)``
- ``ObservationTest/expect(_:alwaysSatisfies:sourceLocation:)``

### Concurrency control

- ``ControllableOperation``
- ``TestEventCounter``
- ``TestBarrier``
