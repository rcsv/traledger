# ADR 0016: Share one Travel Leg editor between Planner and Guide

Status: Accepted

Date: 2026-07-25

## Context

Travel Leg rows are derived transitions between adjacent Activities. Guide
already allowed a row to open a detail/editor sheet, but Planner rendered the
same row without an edit action. That split made transport preferences,
manual duration, notes, and route retry appear Guide-owned even though they are
part of itinerary planning.

Providing a second Planner-specific form would create two interaction
contracts for the same `TravelLegPreference` and make validation, accessibility
identifiers, and retry behavior drift over time.

## Decision

Planner and Guide open the same `TravelLegEditSheet` from the same
`ActivityList` Travel Leg row.

The editor remains progressively disclosed between adjacent Activity Cards. It
supports driving, walking, transit, and other transport; optional manual
duration; a short note; MapKit recalculation where a directions mode exists;
and an explicit handoff to Apple Maps.

Planner resolves the selected directional `TravelLegID` against both its
transient `TripTravelLoadModel` state and the current Trip snapshot before
presenting the sheet. If either endpoint no longer exists, it presents an
unavailable state instead of editing a guessed replacement.

Save and retry both persist a scoped `setTravelLegPreference` mutation first.
Only after persistence succeeds does Planner refresh or retry its transient
MapKit calculation. A retry therefore includes unsaved transport, duration,
and note changes, while a persistence error leaves the editor open.

Manual duration remains user authority and is not overwritten by a successful
MapKit calculation. The `other` transport type has no inferred MapKit mode and
therefore offers neither recalculation nor Apple Maps route launch.

## Consequences

- Planner becomes the primary place to plan an Activity interval without
  removing Guide's in-trip adjustment path.
- Both surfaces share labels, controls, accessibility identifiers, range
  limits, route-source language, and Apple Maps behavior.
- The persisted Domain continues to own user intent only. Route calculations
  remain transient and refresh from the updated Trip snapshot.
- A Travel Leg row without an edit callback remains a read-only summary, so
  other `ActivityList` consumers do not gain accidental mutation behavior.

## Verification

- The full macOS model suite exercises scoped Travel Leg mutations, validation,
  manual-duration precedence, and preservation of unrelated edits.
- A macOS build compiles both Planner and Guide against the single editor type.
- A generic iOS build confirms that exposing the shared editor does not change
  the mobile composition.
- Clicking Planner and Guide rows, editing each transport mode, retrying
  MapKit, opening Apple Maps, and checking compact/regular layouts remain in
  the stable-Xcode UI gate.
