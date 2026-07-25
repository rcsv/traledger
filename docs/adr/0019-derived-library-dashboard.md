# ADR 0019: Library Dashboard is a derived secondary destination

Status: Accepted

Date: 2026-07-25

## Context

TripMap already stores Trips, Participant assignments, Activities, Activity
categories, and one local `ReservationReference` per Activity. The Library had
no cross-Trip summary, even though the same data was already projected inside
individual Trip overviews.

A Dashboard must not replace or delay the primary Library job of finding and
opening a Trip. It also must not introduce denormalized counters that can drift
from Activity or Reservation ownership. Country history is not yet safe:
`PlaceSnapshot` has no persisted ISO 3166-1 alpha-2 country code, and address
or coordinate inference is not an acceptable historical source of truth.

## Decision

`LibraryDashboardProjection` derives one immutable summary from readable
`Trip` snapshots and Participant IDs from assignments that still reference a
Trip. It stores nothing.

The first enabled metrics are:

- readable Trip count;
- distinct Participants assigned to at least one Trip;
- all non-skipped Activities, including uncategorized Activities in the
  denominator;
- category counts and fractions, plus the largest category or uncategorized
  bucket;
- all Reservation references, kind counts, and unscheduled count;
- the earliest future Reservation belonging to a planned Activity.

The next Reservation projection carries only Trip, Day, Activity, kind, title,
and start-time identifiers needed for navigation and presentation. It never
copies confirmation code, note, or URL.

macOS exposes Dashboard as a secondary Library sidebar destination while
keeping Upcoming as the initial destination. iPhone and iPad expose the same
summary in a collapsed disclosure above the Trip list, so charts and metrics
are never forced ahead of navigation. Both surfaces can open the Trip
containing the next Reservation.

Country metrics remain visibly unavailable until country code persistence and
migration pass the versioned model freeze. The Dashboard does not inspect
legacy country-name inference.

## Consequences

- Dashboard values update from the same SwiftData relationships as the
  Library and never need invalidation or migration.
- An unreadable Trip is omitted from every content-derived metric instead of
  partially contributing inconsistent counts.
- Duplicate assignments of the same Participant count once.
- Skipped Activities do not affect Activity distribution; their existing
  Reservation reference remains part of Reservation inventory, while it can
  never become the next Reservation.
- Fractions always appear beside exact counts because rounded percentages may
  not sum to 100%.
- Country history and estimated cost remain blocked without weakening the
  current schema gate.

## Verification

- Unit coverage proves readable Trip aggregation, Participant deduplication,
  skipped Activity exclusion, uncategorized denominator behavior, Reservation
  kind aggregation, and cross-Trip next-Reservation selection.
- The complete macOS model suite passes.
- Generic iPhone/iPad `Debug-QA` compilation passes.
- Stable-Xcode visual, Dynamic Type, VoiceOver, keyboard, and viewport checks
  remain deferred.
