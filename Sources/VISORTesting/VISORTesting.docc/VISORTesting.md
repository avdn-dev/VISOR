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

## Topics

### Observation scopes

- ``observe(_:sourceLocation:_:)``
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
