# ADR 0015: Route macOS commands through window and focus context

Status: Accepted

Date: 2026-07-25

## Context

TripMap's toolbar actions existed before its macOS menu commands. Calling a
View's temporary sheet state directly from an app-level command would couple
the menu to one rendered View, behave unpredictably with multiple Trip
windows, and allow Activity creation without a visible Day context.

Global commands and Trip-local commands also have different ownership:

- Library, Trip creation, and global Participant registration must work when
  no Trip window is focused.
- Activity creation/editing, date-range editing, and Participant assignment
  must target only the focused Trip window.

## Decision

Use two explicit routing layers.

`MacCommandRouter` carries tokenized global Library intents. The single
`library` Window consumes each token once and routes to the existing Trip or
Participant editor:

- show Library;
- create Trip;
- register Participant.

`MacTripCommandActions` is published through `FocusedValues` by each
`PlanView`. The active Trip window supplies closures that open the same sheets
used by its toolbar:

- create Activity;
- edit the selected Activity;
- edit the Trip date range;
- assign a Participant.

Activity creation is enabled only when the focused Planner is displaying a
specific Day. A Trip existing in memory is not sufficient context. Activity
editing additionally requires a selected Activity. Disabled commands do not
guess another Trip or Day and do not fail after invocation.

The Library is a single SwiftUI `Window`, so `Command-Option-L` brings the
canonical Library window forward rather than intentionally creating another
Library instance. Trip workspaces remain value-addressed `WindowGroup`
windows. The standard Settings scene remains the source of the app-menu
Settings command.

## Command mapping

- `Command-N`: new Trip
- `Shift-Command-N`: add Activity, when a focused Day exists
- `Command-Option-L`: show Library
- `Command-Option-P`: register Participant
- `Command-E`: edit the selected Activity
- `Trip` menu: add/edit Activity, change date range, assign Participant

## Consequences

- Menu, keyboard, and toolbar entry points converge on the same editor and
  Domain mutation paths.
- Global commands remain available from Library and Trip windows.
- Focused actions cannot leak from one Trip window into another.
- Routing tokens make repeated identical commands observable without storing
  sheet presentation as app-level state.
- Insert-at-anchor, Trip navigation destinations, and theme commands remain
  later slices; this ADR does not invent placeholder behavior for them.

## Verification

- A unit test proves consecutive global intents receive distinct tokens and
  preserve their requested kind.
- macOS build and the full model regression suite cover command declarations
  and existing edit paths.
- iOS generic build confirms the macOS-only routing adds no mobile dependency.
- Menu placement, keyboard dispatch, focus switching between multiple Trip
  windows, and Settings presentation remain in the stable-Xcode UI gate.
