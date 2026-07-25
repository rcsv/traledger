# ADR 0003: SwiftData local calendar storage

Status: Accepted for the M2 local-persistence slice

## Decision

TripMap uses SwiftData as its local store. Persistent types are storage records and remain separate from the `Trip`, `Day`, `Activity`, and `PlaceSnapshot` domain values used by the UI.

- Trip and Day calendar dates are stored as validated Gregorian `YYYYMMDD` integers.
- Activity wall-clock times are stored as an optional minute offset in `0...1439`.
- Each Trip stores an IANA time-zone identifier.
- Domain `Date` values are produced only at the persistence adapter boundary using the Trip time zone.
- Plan and Guide inject that Trip time zone at the workspace root so every
  Day, Activity, Reservation, and Venue inspector format uses the same civil
  calendar even when the device is in another time zone.
- Relationships use cascade deletion and optional inverses. Application UUIDs remain ordinary attributes rather than SwiftData uniqueness constraints so the initial schema stays compatible with a future CloudKit spike.

## Why

A bare `Date` represents an instant. Trip calendar dates and Activity start times are local civil values and must not shift when the Mac or iPhone changes time zone. Explicit compact values also make invalid dates and times rejectable before persistence.

SwiftData records are not the public Travel Ledger exchange schema. Future import and export code will map through the domain model rather than expose the local database layout.

## Verification boundary

M2 tests must cover:

- invalid local date and time rejection;
- a SwiftData save and fresh-context fetch;
- preservation of Trip time zone, Day calendar date, Activity wall-clock time, sequence, and PlaceSnapshot;
- atomic rejection at creation and editing boundaries before invalid records are saved.

CloudKit synchronization is still a separate spike. This decision only avoids known schema choices that would unnecessarily prevent that experiment.
