# ADR 0017: Anchor Activity insertion and scoped structural Undo

Status: Accepted

Date: 2026-07-25

## Context

Activity creation previously appended to the selected Day regardless of where
the user was reading the itinerary. The persisted mutation carried a stable
Activity ID and Day ID, but no intended gap. It could not distinguish adding
at the beginning, between two Activities, or at the end, and creation was not
registered with the Planner Undo coordinator.

An integer index or sequence is not a durable insertion intent. Concurrent
Activity changes can shift either value and silently place a new Activity
somewhere the user did not choose.

## Decision

`InsertActivityMutation` carries:

- the target Day ID;
- a pre-generated Activity ID and its creation fields;
- an `ActivityInsertionAnchor` containing the previous and next Activity IDs.

The valid anchor shapes are:

- empty Day: neither previous nor next;
- beginning: next only, which must still be first;
- middle: previous and next, which must still be adjacent;
- end: previous only, which must still be last.

Mutation application validates the gap against the latest snapshot. A changed
gap fails with an actionable error instead of falling back to an index or the
end of the Day. Unrelated changes outside the selected gap are preserved.
Successful application inserts the Activity and normalizes every sequence in
the target Day.

Planner exposes one insertion control at the beginning, in every Activity gap,
and at the end. These controls share the vertical Activity Weaver spine with
sequence markers and Travel Leg transitions. On macOS the full label appears
for hover or keyboard focus; the plus remains visible at rest. Touch layouts
keep a minimum 44-point action area and a visible label. Every control exposes
its insertion position to accessibility independently of color.

Toolbar and menu creation remain end insertion. An empty Day retains one
primary creation action.

Creation registers the insertion and its scoped delete inverse with
`PlanUndoCoordinator`. Deletion now registers a scoped
`RestoreActivityMutation` inverse containing the complete Activity snapshot,
its original gap, and only its referencing Travel Leg preferences. Undo and
Redo therefore preserve unrelated concurrent additions without replaying a
whole Trip snapshot. If the original gap changes before restoration, Undo
fails rather than guessing another position.

## Consequences

- Activity double-click and Return remain editing gestures.
- Insertion intent is stable across sequence renumbering.
- Adding into the same gap from another context is a visible conflict; adding
  elsewhere is not.
- Restoring a deletion recovers user-owned Activity, Venue, Reservation,
  reminder, progress, and Memory fields through the Activity snapshot, plus
  only directly owned Travel Leg preferences.
- Legacy `appendActivity` remains for existing non-interactive callers and is
  implemented as a current-end insertion. Planner uses only the anchored
  mutation.

## Verification

- Unit tests cover beginning, middle, and end insertion; changed-gap rejection;
  sequence normalization; and delete/restore/redo with Travel Leg intent.
- In-memory persistence tests prove unrelated concurrent end insertion is
  preserved for both insertion and restoration.
- The macOS full model suite and generic iOS build cover all mutation switches,
  persistence branches, and adaptive SwiftUI compilation.
- Hover, keyboard focus, VoiceOver, 44-point touch targets, visual spine
  alignment, and Command-Z / Shift-Command-Z remain in the stable-Xcode UI
  gate.
