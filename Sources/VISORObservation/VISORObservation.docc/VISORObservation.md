# ``VISORObservation``

Publish stable, isolation-neutral snapshots through a producer-owned channel
and distribute only a read-only source capability.

## Overview

An ``ObservationChannel`` owns mutation and synchronous publication. Its
``ObservationChannel/source`` exposes the current snapshot and an
initial-plus-latest `AsyncSequence` without exposing producer controls.

Each iterator owns an independent subscription. Iteration is single-consumer,
coalesces intermediate revisions when its consumer is busy, and throws
``ObservationSourceError`` if the source can no longer provide coherent State.
Task cancellation ends iteration normally.

The `@ObservationState` macro keeps an ordinary stored property canonical while
generating its stable source. Apply `@ObservationStateRequirements` when a
protocol declares observation-State properties; it synthesises their companion
read-only source requirements.

## Topics

### Producer and consumer capabilities

- ``ObservationChannel``
- ``ObservationSource``
- ``ObservationSnapshots``
- ``ObservationSourceError``

### Observation State macros

- ``ObservationState()``
- ``ObservationState(observedAs:)``
- ``ObservationState(initial:)``
- ``ObservationState(initial:observedAs:)``
- ``ObservationStateSequenceName``
- ``ObservationStateRequirements()``
