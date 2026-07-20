# ADR 0002: Model invariants and transient interaction state

Status: Accepted for M1.1; persistence representation to be verified in the M2 SwiftData spike

## Context

M1 proved that a `Trip → Day → Activity → optional PlaceSnapshot` model can drive Plan and Guide map experiences. The prototype also exposed ambiguous behavior for empty data, activities without places, user-controlled map cameras, and `Date` values that are intended to mean a local calendar date or wall-clock time.

## Domain invariants

- A saved, usable Trip has at least one Day. Loading and draft UIs must still tolerate zero Days.
- Day sequence values are positive, unique, and contiguous within a Trip. Activity sequence values follow the same rule within a Day.
- UI order is derived from sequence; array insertion order is only a stable tie-breaker for invalid prototype data.
- Each Day date is unique and belongs to the Trip date range.
- An Activity belongs to exactly one Day and has at most one optional primary PlaceSnapshot.
- PlaceSnapshot coordinates are finite, latitude is within `-90...90`, and longitude is within `-180...180`.
- MapKit identifiers are lookup hints, not durable application identity.

M1.1 reports violations through `Trip.validationIssues`. M2 creation, editing, import, and persistence boundaries will reject invalid models atomically. Views retain explicit empty states because drafts, loading, migration, and corrupt external data can temporarily violate saved-model invariants.

## Date and time semantics

- Trip will own an IANA time-zone identifier.
- A Day date is a local calendar date in the Trip time zone, not an absolute instant.
- An optional Activity start time is a local wall-clock time belonging to its Day.
- M2 will spike a persistence representation based on explicit date components or an ISO local-date value. It will not rely on a bare `Date` interpreted in the device time zone.
- Absolute instants remain available for future reservation or transport facts that genuinely identify a moment in time.

The M1 structs retain `Date` temporarily so the SwiftData representation can be tested before the public domain shape changes.

## Interaction-state rules

Selected Day, selected Activity, Guide display mode, and map camera are transient UI state and are not persisted.

| Event | Selection | Camera |
|---|---|---|
| Open Trip | First Day by sequence; first Activity by sequence | Fit all places in the selected Day |
| Change Day | First Activity by sequence, including one without a place | Fit all places in the new Day |
| Select a list Activity with a place | Select that Activity | Focus its place |
| Select a list Activity without a place | Select that Activity and clear map annotation selection | Preserve camera and show a no-place notice |
| Select a map pin | Select its Activity | Preserve camera because the pin is already visible |
| Switch Map/List | Preserve selection | Preserve the Map camera |
| Reorder Activities | Preserve selection by Activity ID | Preserve camera |
| Delete selected Activity | Select next, then previous, then none | Follow the resulting explicit selection policy |

Plan and Guide share these rules through a small value-type interaction state. The Map owns its live camera position; data changes communicate explicit camera requests rather than treating every selection mutation as a camera command.

## PlaceSnapshot update policy

PlaceSnapshot records what the user selected at planning time: display name, address, coordinate, and an optional MapKit lookup hint. It is not silently refreshed. A future explicit refresh or replacement operation may produce a new snapshot while keeping the Activity identity stable.

## Consequences

- SwiftData is not yet the domain contract.
- CloudKit and migration compatibility must be proven for local dates, local times, and the Trip time zone before M2 adopts a schema.
- Dense or coincident map markers are represented correctly by the model but may require clustering or disambiguation in a later map-experience milestone.
- Tests should primarily assert invariant and interaction-state transitions rather than MapKit tile rendering.
