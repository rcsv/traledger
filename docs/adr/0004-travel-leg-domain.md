# ADR 0004: Travel Leg domain and MapKit estimate boundary

Status: Accepted for the P3 Travel Leg slice

## Context

Travel time belongs to the relationship between two Activities, not to either
Activity. The current prototype derives consecutive pairs whose Activities both
have a Venue, requests an automobile route from MapKit, keeps the result in
memory, and gives complete Day estimates to Doctor.

Before Travel Leg becomes visible and editable, the product needs one definition
of identity, persistence, routing state, invalidation, and failure behavior.
MapKit coverage is not guaranteed, and a route estimate is observation data that
must not silently become user-authored itinerary data.

## Decision

### 1. Leg topology and identity

- An active Travel Leg is derived between two immediately adjacent Activities
  in the same Day's sequence-first ordering.
- A routable leg exists only when both Activities have a primary
  `PlaceSnapshot`. An Activity without a Venue remains visible, but no route is
  inferred across it.
- The domain identity is the ordered pair
  `(fromActivityID, toActivityID)`. Reversing the pair creates a different leg.
- Day ID is context and a validation field, not identity. A valid active leg
  cannot cross Day boundaries.
- Activity IDs are durable application identity. MapKit identifiers and
  coordinates are inputs to resolution and cache invalidation, never Travel Leg
  identity.

Reordering Activities recomputes the active topology. A preference for a pair
that is no longer adjacent becomes inactive rather than being reassigned to a
different pair. If that exact pair becomes adjacent again, its explicit user
preference may become active again.

### 2. User intent and derived observation are separate

The future persistent record stores only explicit user intent:

- from Activity ID;
- to Activity ID;
- transport type;
- optional manual duration in whole minutes;
- optional short note.

No record is created merely because MapKit calculated a route. Records without
any explicit user choice are not persisted.

The MapKit estimate is a replaceable derived value:

- estimated duration in whole minutes;
- calculation timestamp;
- routing input fingerprint;
- calculation state and optional diagnostic category.

The estimate and route polyline are not part of `Trip`, the SwiftData source of
truth, or the exchange schema. Persistent caching may be added later behind a
cache repository, but must remain disposable and independently migratable.

### 3. Transport types

The first domain set is:

- `automobile`;
- `walking`;
- `transit`;
- `other`.

The default is `automobile` to preserve the current product behavior. The first
three map to the corresponding MapKit routing profile. `other` represents a
user-described transfer that MapKit cannot reliably model and therefore needs a
manual duration if it is to contribute to time calculations.

Labels such as taxi or rideshare may use the automobile routing profile without
creating a false promise that MapKit models pickup wait time. New transport
types require a domain migration and explicit fallback behavior; raw MapKit enum
values are never persisted.

### 4. Effective duration precedence

The duration shown and used for load calculations is selected in this order:

1. valid manual duration;
2. loaded MapKit estimate for the current routing fingerprint;
3. stale MapKit estimate, visibly marked stale;
4. no duration.

A manual duration is never overwritten by refresh. MapKit may still be
recalculated on an explicit route-detail request, but it remains supporting
information until the user clears the override.

Valid manual and estimated durations are `1...1439` minutes. Values outside that
range are rejected at editing and persistence boundaries.

### 5. Calculation state

Every active routable leg exposes one of these states:

- `idle`: eligible but not requested;
- `loading`: a request for the current fingerprint is in flight;
- `loaded`: a current estimate is available;
- `unavailable`: MapKit returned no usable route for the inputs;
- `failed`: a transient or unexpected request failure occurred;
- `stale`: an older estimate can be displayed but its freshness or inputs no
  longer meet the current policy.

`unavailable` and `failed` never block Trip, Day, or Activity viewing and
editing. The list reserves a stable, compact row for each active leg and uses
text and symbols rather than color alone to distinguish these states.

The initial freshness window is 24 hours while the app is active. This is a UI
freshness policy, not a claim of traffic accuracy. The initial request does not
set a departure time, because local Activity times alone do not justify a
real-time traffic promise.

### 6. Routing fingerprint and invalidation

The routing fingerprint contains:

- ordered from/to Activity IDs;
- from/to PlaceSnapshot IDs;
- from/to coordinates;
- transport type.

Changing Activity title, note, category, start time, or duration does not
invalidate a route. Replacing or clearing either Venue, changing transport type,
changing adjacency, or changing either coordinate does.

Refresh cancellation uses a generation token. A result from an obsolete
generation or fingerprint is discarded and cannot overwrite the current leg.
Unchanged loaded estimates are reused rather than restarted when an unrelated
Trip field changes.

### 7. Doctor and UI consumption

- Activity lists place a compact Travel Leg row between the two Activities.
- The row shows transport type and the effective duration, or a clear calculation
  state such as calculating, unavailable, failed, or stale.
- Route detail may show the polyline and actions. The full Day route is not
  permanently overlaid on the map.
- Doctor aggregates active legs by Day only when every leg that should
  contribute has an effective duration. It may use manual, loaded, or visibly
  stale durations and must retain the source/confidence distinction.
- A partial calculation does not produce a misleading low total. Instead,
  Doctor reports no high-travel conclusion until the Day has a complete set.
- Doctor observes and explains; it never changes transport type, ordering, or
  duration automatically.

### 8. Persistence and deletion rules

P3 begins with derived default automobile legs and in-memory estimates. The
SwiftData preference record is introduced only with the transport/manual
duration editor.

When introduced:

- deleting an Activity deletes preferences that reference it;
- deleting a Day or Trip removes descendants through the existing ownership
  boundary;
- reordering only activates or deactivates pair preferences;
- Venue replacement invalidates the estimate but preserves the user's transport,
  manual duration, and note;
- orphan or cross-Day preferences are rejected on load/import and never repaired
  by silently selecting a new Activity.

## Verification boundary

Domain tests must cover:

- active legs are produced only for adjacent, same-Day Activities with two
  Venues;
- pair identity is directional and stable across unrelated edits;
- reorder, deletion, and Venue replacement invalidate only affected estimates;
- transport changes alter the routing fingerprint;
- manual duration wins over loaded and stale estimates;
- stale, unavailable, and failed states remain readable;
- obsolete asynchronous results are discarded;
- Doctor waits for complete effective durations and aggregates each active leg
  exactly once;
- a future persistence adapter round-trips explicit preferences without storing
  MapKit estimates or polylines.

UI tests must cover a loaded leg, loading state, unavailable fallback, manual
override, Dynamic Type, VoiceOver labels, and compact/regular width placement.

Live MapKit checks remain opt-in integration tests. Deterministic tests inject a
route-estimating boundary and do not assert Apple server availability or map tile
rendering.

## Consequences

- P3 can add leg rows and calculation states without committing transient
  MapKit data to SwiftData.
- The current `TripTravelEstimate` and `TripTravelLoadModel` are a prototype
  projection. They should be replaced by the stateful domain projection
  described here before transport editing is added.
- A placeless Activity intentionally breaks route continuity; the product does
  not guess a route across unknown itinerary intent.
- Offline use can always read the itinerary and any manual duration. A previous
  estimate may be shown only if a later disposable cache is implemented and the
  value is labeled stale.
- Route polylines, traffic-aware departure times, background refresh, and
  persistent MapKit cache are separate follow-up decisions.
