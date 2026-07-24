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

- Trip cover image;
- user-selected Venue image;
- derived external Venue image metadata;
- Activity progress and its change timestamp;
- Memory photo/reflection plus the required completed progress state.

Plan and Guide pass a mutation callback from the persistence-owning workspace.
Previews and isolated callers may omit it and retain the existing full-snapshot
callback while migration is incomplete.

## Boundaries

`TripMutation` is not a general merge engine and does not define remote
same-field conflict policy. A mutation can preserve independent local fields,
but CloudKit activation remains blocked until schema migration and the
three-device matrix are complete.

Structural and composite operations still use `applyPlan`, including Trip
metadata, Day add/delete/reorder, Activity add/delete/move/edit, Venue
replacement, reservation, reminder, and travel-leg preference changes. Those
paths must become scoped operations or gain proven field-level merge behavior
before development sync is enabled.

Derived Look Around/Wikimedia resolution may only update external image
metadata. It must not write the user image field or recreate a Venue that has
been cleared.

## Consequences

- Cover, Venue image, external image, progress, and Memory saves no longer
  replay stale unrelated values.
- Venue image intents carry the Place UUID observed by their initiating UI.
  A replaced or cleared Venue rejects the stale result, so an old Look
  Around/Wikimedia task cannot decorate the new Venue.
- Missing Activity or Venue targets and changed Place identities fail
  explicitly instead of silently modifying a detached snapshot.
- Memory completion and its content persist as one intent.
- Reminder reconciliation after a Guide mutation uses the latest persisted
  snapshot.
- Undo for structural Plan edits remains on the old full-snapshot path until a
  mutation-aware undo design is introduced.

## Verification

In-memory SwiftData regression tests must prove that:

- a cover update preserves a concurrent Activity edit;
- a user Venue image changes only its owned image field;
- an external image result for a replaced Place UUID is rejected;
- Memory completion preserves an unrelated Activity edit and normalizes the
  reflection;
- mutation errors do not fall back to a broad write.

Device-to-device convergence remains governed by the
[`P8 Sync Research Gate Matrix`](../qa/sync-research-gate-matrix.md).
