# ADR 0001: Native Apple foundation

Status: Accepted

## Context

The existing travel-ledger implementation proves the `Trip → Day → Itinerary` semantics and schema-v8 exchange format. The Apple product needs a map-first experience rather than a port of the React/Tauri application.

## Decision

- Build a new SwiftUI multiplatform application with an independent `0.x` version line.
- Use app-language concepts `Trip`, `Day`, `Activity`, and `PlaceSnapshot`.
- Preserve sequence-first ordering and the rule that an activity has at most one primary place.
- Use MapKit for SwiftUI and Apple-standard navigation patterns.
- Treat schema v8 as a future import/export boundary, not as the internal store contract.
- Keep the M1 vertical slice in memory. Evaluate SwiftData dates, migration tests, and CloudKit compatibility before M2.
- Do not link Rust, read legacy SQLite directly, or mirror CLI service boundaries.

## Consequences

The first slice can validate list/map interaction without persistence risk. A later adapter must explicitly map schema-v8 data to the app model and report unsupported data rather than silently dropping it.
