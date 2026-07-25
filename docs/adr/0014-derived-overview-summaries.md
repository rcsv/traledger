# ADR 0014: Derive overview summaries from the current Trip

Status: Accepted

Date: 2026-07-25

## Context

Trip Overview needs Activity distribution and Reservation summary information.
Persisting aggregate counters would add schema and migration work, introduce a
second source of truth, and risk counters becoming stale after scoped
mutations or future replica merges.

Reservation summaries also sit above records that may contain a confirmation
code, private note, or complete URL. Those fields are useful in the explicit
detail sheet but are inappropriate for an always-visible overview.

## Decision

`ActivityAnalysisProjection` and `ReservationSummaryProjection` are pure
Domain projections over the current `Trip` value. No aggregate is written to
SwiftData.

Activity Analysis:

- excludes `skipped` Activities from both counts and the denominator;
- includes planned and completed Activities;
- treats a missing category as `未分類`;
- returns exact fractions and leaves display rounding to the UI;
- sorts populated categories by descending count, then by the stable Domain
  category order.

Reservation Summary:

- counts every stored `ReservationReference` by kind, including references on
  completed or skipped Activities, because the count describes stored trip
  records;
- reports reservations whose Activity has no start time as `時刻未設定` and
  does not invent an ordering for them;
- selects the next reservation only from planned Activities with a start time
  at or after the projection's `now`;
- uses start time, Day sequence, Activity sequence, and Activity UUID as
  deterministic ordering tie-breakers;
- exposes only stable navigation IDs, kind, titles, Day sequence, and start
  time in the overview item. Confirmation code, note, and URL remain in the
  explicit reservation detail flow.

The Overview displays the five largest populated Activity categories by
default, keeps the unclassified count explicit, and offers `すべて表示` when
more categories exist. Selecting the next reservation navigates to its
Activity using the stable Activity and Day identities.

## Consequences

- Existing stores need no migration.
- Every scoped mutation is reflected the next time the Trip snapshot is
  projected.
- Percentage labels may not visually add to exactly 100% after rounding, so
  counts remain visible beside them.
- A reservation without a time remains discoverable in the total and
  `時刻未設定` count but cannot become the next reservation.
- A skipped or completed Activity can retain its reservation record without
  being presented as an upcoming commitment.

## Verification

Unit tests cover:

- skipped exclusion and unclassified denominator behavior;
- stable category ordering and exact fractions;
- all-kind Reservation counts and the unscheduled count;
- exclusion of past, completed, skipped, and unscheduled candidates from the
  next-reservation choice;
- stable IDs and privacy-safe fields returned for Overview navigation.

Visual hierarchy, VoiceOver reading order, and the expanded category list
remain part of the stable-Xcode viewport gate.
