# ADR 0008: Travel Leg detail is progressive and delegates route rendering

Status: Accepted for the P6 Guide readiness slice

Date: 2026-07-24

## Decision

Travel Leg rows remain compact transitions between Activity Cards. Selecting a
row opens one detail/editor sheet that presents:

- departure and arrival Activity names;
- the persisted departure and arrival Venue snapshot names;
- effective duration;
- whether the duration is manual, current MapKit, stale MapKit, unavailable, or
  failed;
- transport choice, explicit recalculation, optional manual duration, and note;
- an explicit Apple Maps route action for driving, walking, and transit.

TripMap does not render a route polyline on every Guide map, persist MapKit route
geometry, or make route geometry part of the itinerary Domain. A route is
high-churn, online-derived information. Apple Maps is the system-owned surface
for turn-by-turn route inspection and can recalculate against current
conditions.

The `other` transport type has no reliable MapKit directions mode, so its sheet
does not guess one. The user-authored duration and note remain available.

## Rationale

The Guide map answers “where are my plans?” A constantly visible route answers a
different question, adds visual noise, can imply stale authority, and competes
with Venue selection. Progressive disclosure keeps the list scannable while
making route inspection one tap away.

The app retains only explicit user intent (`TravelLegPreference`). MapKit
duration state remains transient and may be retried. Launching Apple Maps is an
explicit user action and does not alter the saved preference.

## Verification

- Existing Domain tests verify directional identity, preference persistence,
  manual-duration precedence, and stale estimates.
- The universal iOS build verifies the shared iPhone/iPad detail composition and
  MapKit launch API.
- Viewport and cross-app launch checks remain a visual gate and must be resumed
  when a stable Simulator/Xcode runtime is available.
