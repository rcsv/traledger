# ADR 0013: Replay scoped mutations against the latest local Trip

Status: Accepted; migration in progress

Date: 2026-07-25

## Context

SwiftUI screens receive a `Trip` value snapshot. `StoredTrip.applyPlan` replaces
most persisted fields from that value. If another writer changes an unrelated
field after the screen was rendered, saving the older full snapshot can erase
that newer change.

This is already undesirable for multiple windows and becomes a release blocker
for future CloudKit replicas. Enabling CloudKit does not make a broad
application-level replacement into a field-aware merge.

## Decision

Represent small user intents as `TripMutation`. At save time:

1. Read the latest valid Domain snapshot from `StoredTrip`.
2. Apply and validate the mutation against that snapshot.
3. Write only the SwiftData fields owned by the mutation.
4. Save or roll back the `ModelContext` as one UI operation.

The first mutation set owns:

- Trip title;
- Trip date range and its Day membership/sequence;
- Trip cover image;
- Trip default currency and time-zone identifier;
- Plan Activity details: title, start time, category, duration, note, and an
  explicitly changed Venue;
- Guide Activity details: start time, note, an explicitly changed Venue,
  progress, reservation, and reminder;
- one travel-leg preference: transport type, manual duration, and note;
- Activity append with a caller-generated stable UUID;
- Activity delete with its expected parent Day UUID;
- Activity move using an explicit before/after anchor, plus an anchored inverse
  mutation for Undo/Redo;
- Day Activity replication with caller-generated Activity/Place UUIDs and the
  source Activity UUID order observed by the initiating UI;
- Day plan swap with the Activity UUID order observed for both Days;
- user-selected Venue image;
- derived external Venue image metadata;
- Activity progress and its change timestamp;
- Memory photo/reflection plus the required completed progress state.

Plan and Guide pass a mutation callback from the persistence-owning workspace.
Previews and isolated callers may omit it and retain the existing full-snapshot
callback while migration is incomplete.

Production AppShell workspaces reject that compatibility callback. A user
operation without a scoped mutation therefore fails closed instead of reaching
`StoredTrip.applyPlan`. Full-snapshot application remains available only for
fixture setup, persistence round-trip tests, and isolated non-production
callers.

## Boundaries

`TripMutation` is not a general merge engine and does not define remote
same-field conflict policy. A mutation can preserve independent local fields,
but CloudKit activation remains blocked until schema migration and the
three-device matrix are complete.

Trip title editing uses a scoped mutation. Trip date-range editing records the
complete ordered Day UUID/date identity observed by the initiating UI and
pre-generates stable UUIDs for every added Day. Extending a range creates only
empty Days. Contracting a range may remove only empty Days; a Day with an
Activity must be cleared or moved first. A changed Day identity/date/order
rejects the stale intent. Retained Days and all their current fields remain
untouched except for the sequence needed by the new contiguous range. macOS
Planner and iPhone/iPad Guide present the same date-range sheet and submit this
same mutation; mobile does not maintain a second date editing contract. The
sheet dismisses only after persistence succeeds, retaining the proposed range
after a removal rejection, concurrent structure change, or save error.

Interactive Activity insertion generates its UUID before persistence and
records the previous and next Activity IDs of the selected gap. Unchanged gaps
accept insertion and normalize the Day sequence; a changed gap is rejected
instead of falling back to an index. Activity delete requires the Day UUID
observed by the initiating UI, renumbers only that Day, deletes owned
Venue/reservation records and referencing travel-leg preferences, and rejects
an Activity that moved to another Day. Its inverse restores the complete
Activity and its directly referencing travel-leg preferences at the original
gap, enabling scoped Undo/Redo without replaying a Trip snapshot.

Move/reorder records whether the dragged Activity belongs before or after a
stable anchor Activity. Undo records the original neighbor as an inverse
mutation, so neither Undo nor Redo restores a complete Trip snapshot.

Day replication records the complete source Activity UUID order and generates
all destination Activity and Place UUIDs before persistence. It reapplies the
latest source fields only when that source structure is unchanged, appends the
copies to the latest target Days, and therefore preserves target Activities
added after the sheet opened. A changed source structure rejects the stale
intent.

Day swap records both complete Activity UUID orders. When both structures still
match, it swaps the latest Day titles and existing Activity relationships
without replaying Activity fields or unrelated Trip fields. An append, delete,
or reorder on either Day rejects the stale swap. Cross-replica ordering still
needs an explicit convergence policy.

Changing time zone is validated against the latest Domain snapshot but writes
only `timeZoneIdentifier`. Local day codes and minute-of-day storage remain
unchanged, which preserves the wall-clock itinerary semantics.

Plan and Guide Activity mutations intentionally have different ownership.
Plan does not write progress, reservation, reminder, or Memory. Guide does not
write title, category, duration, or Memory. Venue is written only when the
sheet changed it, and replacement requires the Place UUID that the sheet
originally displayed.

Derived Look Around/Wikimedia resolution may only update external image
metadata. It must not write the user image field or recreate a Venue that has
been cleared.

## Consequences

- Cover, Venue image, external image, progress, and Memory saves no longer
  replay stale unrelated values.
- Trip rename trims and validates the new title while preserving concurrent
  Activity changes.
- Trip date-range extension preserves retained Day identities and fields,
  creates stable empty Days, and rejects contraction over a Day with Activities
  or any concurrently changed Day structure. The same editor and mutation are
  reachable from macOS, iPhone, and iPad.
- Plan and Guide Activity edits preserve fields owned by the other workflow.
- Venue replacement/clear and reservation replacement/clear delete superseded
  SwiftData children in the same `ModelContext` transaction.
- A travel-leg edit updates or removes only its directional leg preference and
  preserves other legs and Activity fields.
- Currency and time-zone changes preserve concurrent Activity edits; time-zone
  changes preserve local calendar days and start minutes.
- Activity insertion preserves unrelated concurrent additions, rejects a
  changed selected gap, and uses stable identities.
- Activity delete preserves concurrent additions, cascades owned children and
  referencing leg preferences, rejects a changed parent Day, and has a scoped
  restore inverse.
- Activity move and its inverse update only sequence fields and preserve edits
  made before Undo.
- Day replication preserves target-side appends, copies the latest source
  fields into stable caller-generated identities, and rejects a changed source
  Activity structure.
- Day swap moves existing identities and latest fields, preserves unrelated
  Trip fields, and rejects a changed Activity structure on either Day.
- Venue image intents carry the Place UUID observed by their initiating UI.
  A replaced or cleared Venue rejects the stale result, so an old Look
  Around/Wikimedia task cannot decorate the new Venue.
- Missing Activity or Venue targets and changed Place identities fail
  explicitly instead of silently modifying a detached snapshot.
- Memory completion and its content persist as one intent.
- Reminder reconciliation after a Guide mutation uses the latest persisted
  snapshot.
- Production AppShell workspaces fail closed if a future UI operation omits its
  scoped mutation.

## Verification

In-memory SwiftData regression tests must prove that:

- a cover update preserves a concurrent Activity edit;
- a Trip rename preserves a concurrent Activity append and rejects a blank
  title;
- Trip date-range extension retains Day identities and concurrent Activity
  edits; contraction removes only empty boundary Days; an Activity added to a
  removal target or a changed Day structure rejects the stale intent;
- a Plan edit preserves execution fields while replacing its Venue;
- a Guide edit preserves planning and Memory fields while clearing Venue and
  reservation children;
- an Activity edit based on a replaced Venue is rejected atomically;
- a travel-leg edit preserves another leg and concurrent Activity edit, while
  clearing the default preference removes only its own record;
- currency/time-zone changes preserve concurrent Activity data and local
  calendar semantics;
- beginning, middle, and end insertion normalize sequence; unrelated concurrent
  additions survive while a changed insertion gap is rejected;
- Activity delete removes owned children and referencing leg preferences while
  preserving unrelated additions and preferences; scoped restore recovers the
  complete Activity and its leg intent without removing a concurrent append;
- Activity move followed by concurrent edits and its inverse restores relative
  order without discarding the edits or an appended Activity;
- Day replication preserves a target append, uses its pre-generated
  Activity/Place UUIDs, copies current source fields, and rejects a source
  whose Activity UUID order changed;
- Day swap preserves a concurrent Activity field edit and unrelated Trip field,
  moves the existing Activity identities, and rejects a changed Day structure;
- a user Venue image changes only its owned image field;
- an external image result for a replaced Place UUID is rejected;
- Memory completion preserves an unrelated Activity edit and normalizes the
  reflection;
- mutation errors do not fall back to a broad write.
- the production broad-write boundary returns an error rather than accepting a
  complete Trip snapshot.

Device-to-device convergence remains governed by the
[`P8 Sync Research Gate Matrix`](../qa/sync-research-gate-matrix.md).
