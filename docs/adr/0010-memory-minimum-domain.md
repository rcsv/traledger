# ADR 0010: Memory records belong to Activity, not Venue

Status: Accepted for the P7 Memory minimum slice

Date: 2026-07-24

## Decision

The existing `ActivityProgress.completed` value is the first persisted signal
that an Activity was visited. Memory presentation may label it “visited,” but
the stored raw value is not renamed during this slice because that would create
an unnecessary migration risk.

A visited Activity may own:

- one optional normalized JPEG photo;
- one optional trimmed reflection of at most 500 characters.

These are Activity-owned memory fields. They are not added to `PlaceSnapshot`.
The existing user-selected Venue image describes the place and remains eligible
for Place Card presentation; it must not silently become evidence that the user
visited or photographed an Activity.

The first slice reuses the existing PhotosPicker and `TripImageProcessor`
pipeline, but not the Venue image data itself. Capturing multiple photos,
reading the photo library’s time/location metadata, and suggesting Activity
matches are later work.

## State invariants

Photo or reflection data requires `ActivityProgress.completed`. Changing a
recorded Activity back to planned or skipped is rejected until its memory fields
are explicitly cleared. This avoids silent loss.

Day replication does not copy progress or memory records. Day swapping moves
the existing Activity and its explicit record together.

`MemoryProjection` is a pure ordered view of visited Activities. Its Trip
summary counts total, visited, skipped, and visited Activities with a photo or
reflection. Venue images do not affect the recorded count.

## Persistence

Reflection is stored as an optional scalar on `StoredActivity`. The normalized
photo uses SwiftData external storage, matching the app’s existing local image
strategy. Both remain local-first and are included in the same Activity
ownership/cascade boundary.

## Verification

Tests cover the visited-state invariant, reflection normalization and limit,
non-destructive progress behavior, Venue/Memory image separation, ordered
summary counts, and SwiftData round-trip. UI and PhotosPicker integration are
the next implementation slice.
