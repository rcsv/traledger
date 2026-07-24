# ADR 0005: Activity progress is a user-controlled execution overlay

Status: Accepted for the P6 Guide readiness slice

Date: 2026-07-24

## Context

TripMap needs a one-handed way to mark an Activity complete or skipped while a
trip is underway. This state must not be inferred from the clock, location, or
MapKit because arriving late, changing plans, and completing a placeless
Activity are all normal. It must also remain distinct from the planned
Activity fields and from future Memory details such as photos, actual duration,
and a visit note.

## Decision

`ActivityProgress` has exactly three persisted values:

- `planned`: not yet explicitly completed or skipped;
- `completed`: the user says the Activity is done;
- `skipped`: the user says the Activity was intentionally not done.

`completed` is the Guide term. A completed Activity with a Venue may later be
presented as visited in Memory, but the first slice does not claim that device
location proved a visit.

Progress changes are explicit user intent:

- time, location, route completion, and selection never change progress;
- changing to `completed` or `skipped` records `progressUpdatedAt`;
- changing back to `planned` clears `progressUpdatedAt`;
- assigning the current value again is idempotent and preserves its timestamp.

Progress is an execution overlay. It does not rewrite the title, time, Venue,
sequence, or Travel Leg topology. The first slice also does not hide existing
Doctor issues for completed or skipped Activities. Those rules require a
separate Guide-phase projection so planning data is not silently discarded.

Copying an Activity as a new Activity creates new user intent and therefore
starts as `planned`. Moving or editing the same Activity preserves progress.

## Persistence and compatibility

SwiftData stores the enum raw value and optional update date on
`StoredActivity`. New and migrated records default to `planned` with no date.
An unknown raw value, or a `planned` value with a date / terminal value without
a date, is invalid persisted data and must not be silently interpreted as a
different user decision.

## UI requirements

- Cards show `completed` and `skipped` with text and an SF Symbol; color alone
  is insufficient.
- Compact Guide Quick Edit exposes all three values in one control.
- Reverting to `planned` is available in the same control.
- A failed save leaves the sheet open and reports the persistence error.

## Consequences

The model is deliberately smaller than a task-management workflow. There is no
percentage, automatic state, cancellation reason, or separate arrival state.
Memory metadata and Now / Next derivation can build on this persisted intent
without changing its meaning.
