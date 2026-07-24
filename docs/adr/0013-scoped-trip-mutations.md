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
- Trip default currency and time-zone identifier;
- Plan Activity details: title, start time, category, duration, note, and an
  explicitly changed Venue;
- Guide Activity details: start time, note, an explicitly changed Venue,
  progress, reservation, and reminder;
- one travel-leg preference: transport type, manual duration, and note;
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
title/date metadata, Day add/delete/reorder, and Activity add/delete/move.
Those paths must become scoped operations or gain proven field-level merge
behavior before development sync is enabled.

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
- Plan and Guide Activity edits preserve fields owned by the other workflow.
- Venue replacement/clear and reservation replacement/clear delete superseded
  SwiftData children in the same `ModelContext` transaction.
- A travel-leg edit updates or removes only its directional leg preference and
  preserves other legs and Activity fields.
- Currency and time-zone changes preserve concurrent Activity edits; time-zone
  changes preserve local calendar days and start minutes.
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
- a Plan edit preserves execution fields while replacing its Venue;
- a Guide edit preserves planning and Memory fields while clearing Venue and
  reservation children;
- an Activity edit based on a replaced Venue is rejected atomically;
- a travel-leg edit preserves another leg and concurrent Activity edit, while
  clearing the default preference removes only its own record;
- currency/time-zone changes preserve concurrent Activity data and local
  calendar semantics;
- a user Venue image changes only its owned image field;
- an external image result for a replaced Place UUID is rejected;
- Memory completion preserves an unrelated Activity edit and normalizes the
  reflection;
- mutation errors do not fall back to a broad write.

Device-to-device convergence remains governed by the
[`P8 Sync Research Gate Matrix`](../qa/sync-research-gate-matrix.md).
