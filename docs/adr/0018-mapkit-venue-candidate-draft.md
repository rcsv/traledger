# ADR 0018: MapKit Venue candidates require Activity confirmation

Status: Accepted

Date: 2026-07-25

## Context

Venue search previously existed only inside an Activity editor. Planner could
show saved Activity pins, but it had no representation for a MapKit result
that the user was still evaluating. Adding search directly to persistence
would blur the boundary between a Venue and an Activity and would make
canceling or changing the intended Day and insertion position unsafe.

The deployed floor remains iOS 17 and macOS 14. SwiftUI exposes tappable
`MapFeature` selection on iOS 17, but the equivalent direct feature-selection
initializer is unavailable on macOS 14. `MKMapItemRequest` also cannot resolve
a macOS map feature at that deployment floor. A macOS implementation must not
invent a Venue from an arbitrary coordinate.

## Decision

MapKit search resolves an `MKMapItem` into a transient `VenueCandidate`. The
candidate retains the Map item only for candidate UI and Apple Maps actions,
and carries an exchange-friendly `PlaceSnapshot` for a possible confirmed
Activity. It is not part of `Trip` and selecting or dismissing it performs no
write.

Planner offers Venue search both from the Map and from the toolbar. This is
the accessible fallback required when direct map-feature resolution is not
available. Selecting a result:

- clears saved-Activity selection;
- focuses the map on the candidate;
- displays a separate candidate panel with name, MapKit category when known,
  address, automatic image preview, `予定に追加`, and `Mapsで開く`;
- does not create an Activity.

`予定に追加` opens a confirmation draft seeded with
`<Venue名>で過ごす` and the selected `PlaceSnapshot`. Category remains unset:
MapKit category labels are presentation metadata, not a sufficiently reliable
mapping to TripMap's Activity categories. The user confirms Day, exact
beginning/between/end insertion anchor, title, optional time, optional
duration, and category.

Confirmation extends the existing `InsertActivityMutation` with an optional
`PlaceSnapshot`. It uses the same gap validation, scoped persistence,
validation, selection, and Undo registration as place-less insertion. The
draft dismisses only after persistence succeeds; a changed insertion gap or
save error leaves the user's draft open so they can choose a valid position
and retry. Canceling the candidate search or draft therefore leaves the Trip
unchanged.

Candidate image resolution follows the existing user → Look Around →
Wikimedia → placeholder policy. A candidate has no user image, and derived
Wikimedia metadata is not persisted until the Activity exists; the saved
Venue Card remains responsible for durable derived-image state.

## Consequences

- Saved Activity, unsaved Venue candidate, and no selection have distinct UI
  states.
- Empty itineraries can still search for a Venue from the map.
- Search is not a second persistence path; all creation converges on anchored
  Activity insertion.
- MapKit objects do not enter the domain or SwiftData schema.
- Direct point-of-interest tapping on macOS remains a future enhancement,
  gated by an API that can resolve an exact feature at the supported OS floor.
  Arbitrary coordinate taps and nearest-POI guesses are explicitly rejected.
- No non-Apple image provider, app server, reverse proxy, rating, phone, or
  website field is introduced.

## Verification

- A unit test proves Venue draft seeding leaves the Trip unchanged and that
  confirmed insertion carries the exact `PlaceSnapshot` while leaving category
  unset.
- An in-memory persistence test proves scoped insertion persists the Venue and
  preserves an unrelated concurrent Activity append.
- The full macOS test suite passes.
- Generic iPhone/iPad `Debug-QA` compilation passes.
- Candidate-panel layout, VoiceOver order, keyboard traversal, cancellation,
  Maps launch, and end-to-end MapKit search remain stable-Xcode UI gates.
