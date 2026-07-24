# ADR 0006: Guide Now / Next is a pure temporal projection

Status: Accepted for the P6 Guide readiness slice

Date: 2026-07-24

## Context

Guide must answer “what am I doing now?” and “what is next?” without turning
the clock into user intent. Activity progress is explicitly controlled by the
user under ADR 0005. A late start, an unfinished past Activity, overlapping
plans, and Activities without a time or duration are all legitimate itinerary
states. None may cause an automatic completion, skip, or reorder.

## Decision

`GuideTimelineProjection` is a pure function of a Trip and a reference instant.
It never writes to the Trip, SwiftData, Activity progress, or selection state.

The projection first interprets “today” in `Trip.timeZoneIdentifier`. It returns
no Today Summary when the Trip has no Day matching that local calendar date.
When a matching Day exists:

- remaining count is every Activity whose explicit progress is `planned`,
  including untimed and overdue Activities;
- `Now` is a `planned` Activity with both an explicit start time and explicit
  positive duration whose half-open interval `[start, end)` contains the
  reference instant;
- `Next` is the earliest future `planned` Activity with an explicit start time;
- `completed` and `skipped` Activities are excluded from both roles;
- a missing time is never guessed from sequence;
- a missing duration is never guessed from category suggestions and therefore
  cannot produce `Now`;
- temporal ties and overlapping candidates are deterministic: earlier start
  wins, then lower Activity sequence wins.

The projection returns Activity value snapshots and a role lookup for
presentation. It creates no new persisted model.

## Guide presentation

- Opening an in-progress Trip selects its Today Day unless a specific Activity
  deep link was supplied.
- Guide reevaluates the projection on a one-minute `TimelineView` cadence.
- Compact and regular Guide layouts show a Today Summary only while the Today
  Day is selected.
- Summary rows expose Now and Next as explicit text plus SF Symbols. Tapping a
  row uses the existing `TripInteractionState`; it does not create a second
  selection model.
- Activity Cards repeat the Now / Next role using text and a symbol so the
  state is not dependent on color or on the summary remaining visible.
- When Now and Next are an active adjacent Travel Leg with an effective
  duration, the summary may show that duration and derive a departure estimate
  as `next start - effective duration`. Manual duration retains its existing
  priority over MapKit, and unavailable route data simply omits this line.

Today Summary does not claim arrival, completion, or location awareness.
CoreLocation and Live Activities remain separate Research Gate decisions.

## Verification boundary

Deterministic tests cover:

- Trip-time-zone Today selection;
- Now interval and future Next selection;
- completed and skipped exclusion;
- missing-duration behavior;
- no Today result outside Trip dates;
- byte-for-byte-equivalent Trip value before and after projection.

The iOS universal Debug-QA build must compile the same presentation for iPhone
and iPad. Standard and accessibility viewport screenshots remain a separate UI
gate and do not change the Domain decision.
