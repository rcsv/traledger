# ADR 0012: System experiences begin with a read-only Now / Next projection

Status: Accepted; first App Intent implemented

Date: 2026-07-24

## Context

TripMap already derives Today, Now, and Next from a `Trip` snapshot, the Trip
time zone, explicit Activity progress, start time, and duration. P9 needs to
surface useful travel context through Siri, Shortcuts, Spotlight, Handoff, and
eventually WidgetKit without creating a second scheduling engine or exposing
private reservation data.

System experiences may run while the main UI is closed. They must remain useful
offline and must not imply CloudKit convergence.

## Decision

Start P9 with one parameterless, read-only App Intent:
`CheckNextActivityIntent`.

- The Intent opens the local SwiftData store read-only and maps valid
  `StoredTrip` records back through the Domain snapshot.
- `TripSystemExperienceProjection` reuses
  `GuideTimelineProjection.todaySummary`; it does not independently infer Now
  or Next.
- When multiple Trips have relevant activities, an explicitly active Activity
  wins, then the earliest effective activity time, then stable Trip UUID order.
- The response may contain Trip title, Activity title, local start time, and
  persisted Venue name.
- The Intent requires authentication. It must not disclose itinerary details
  while every participating device is locked.
- It must not contain reservation confirmation code, reservation URL,
  reservation note, Activity note, Participant data, reflection, image bytes,
  or derived online provider metadata.
- Store or validation failure returns a non-destructive instruction to open the
  app. A malformed Trip is not silently omitted in favor of a potentially
  misleading “no plan” or different-Trip response. The Intent does not reset,
  repair, or rewrite the store.
- App Shortcut phrases are static and require the application-name token.

Apple documents App Intents as the action boundary used by Siri, Shortcuts, and
other system experiences, and App Shortcuts as install-time discoverable
preconfigured actions:

- [AppIntent](https://developer.apple.com/documentation/appintents/appintent)
- [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)
- [IntentAuthenticationPolicy.requiresAuthentication](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy/requiresauthentication)

## Evidence

- Unit coverage proves the Intent projection selects shared Now / Next state,
  prefers an active Activity across overlapping Trips, formats the Trip time
  zone, excludes private reservation fields, and fails closed when any stored
  Trip cannot produce a valid snapshot.
- macOS tests compile the Intent at the macOS 14 deployment target.
- the generic iOS build compiles at the iOS 17 deployment target;
- Xcode's metadata processor emits exactly one discoverable
  `CheckNextActivityIntent` and one `TripMapAppShortcuts` provider with two
  Japanese phrase templates.

These build results are implementation evidence, not a substitute for invoking
the shortcut with Siri and the Shortcuts app on supported stable OS releases.

## Deferred boundaries

- No write Intent is allowed until granular mutation and conflict behavior are
  complete.
- Spotlight and Handoff require one tested deep-link contract before indexing
  begins.
- A Widget extension cannot assume it can open the main app's private store.
  App Group storage, migration, privacy, and failure behavior require a separate
  decision before WidgetKit is added.
- Live Activity remains behind the product-necessity and ActivityKit research
  gate.

## Consequences

The first system feature is useful offline and has the same temporal truth as
Guide. Its output is intentionally compact and privacy-bounded. P9 can expand
by adding a shared deep-link route and search entities without making System
Experiences a second source of truth.
