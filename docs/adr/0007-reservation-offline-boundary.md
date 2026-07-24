# ADR 0007: Reservation references are local; offline review names online edges

Status: Accepted for the P6 Guide readiness slice

Date: 2026-07-24

## Decision

An Activity may own one optional `ReservationReference`. It is a user-authored
reference, not a synchronized booking object. The first model contains:

- stable ID;
- kind: accommodation, transport, restaurant, admission, or other;
- non-empty display title;
- optional confirmation code;
- optional HTTPS URL;
- optional note.

All text is trimmed at the Domain editing boundary. Empty optional text becomes
nil. Non-HTTPS and hostless URLs are rejected before persistence. The
confirmation code is ordinary local data so the user can read and copy it; it
must not be placed in notifications, widgets, logs, or analytics by default.

`StoredReservationReference` is an Activity-owned SwiftData child with cascade
deletion. Replacement keeps the Activity identity. Deleting an Activity, Day,
or Trip deletes its reservation through the existing ownership boundary.

## Offline review

Offline readiness is a deterministic projection, not a network reachability
test. `GuideOfflineReview` counts locally persisted Activity, Venue snapshot,
user image, and reservation data, then names only the online edges:

- MapKit Travel Leg estimates without a manual duration;
- external Venue images that have no user-image bytes;
- reservation web links.

These edges are enhancements. Their presence is not a user error and does not
make the local itinerary unreadable. The Guide review sheet explicitly says
that saved plan fields, Venue snapshots, confirmation codes, and notes remain
available.

The first slice does not cache arbitrary web pages, import email, integrate
Wallet, infer bookings, or monitor connectivity. Network.framework reachability
would not prove that a provider endpoint or captive portal is usable and is
therefore not the source of truth for this review.

## UI boundary

- Reservation editing lives inside the existing one-handed Activity Quick Edit.
- Activity Cards show the reservation title and kind symbol.
- Selecting an Activity exposes a separate read-only reservation sheet. Only
  that explicit action reveals the confirmation code, URL, and reservation
  note.
- Opening the HTTPS URL and copying the confirmation code are explicit buttons.
  Copying uses the system clipboard and the sheet tells the user that copied
  content remains there.
- Guide toolbar exposes a read-only offline review.

## Verification

Tests cover normalization, unsafe URL rejection, SwiftData round-trip and
cascade deletion, local inventory counts, and online-edge classification.
iPhone and iPad use the same universal SwiftUI build.
