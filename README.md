# TripMap

TripMap is a native Apple trip-planning experiment built with SwiftUI and MapKit.

- macOS is the **Plan** surface: itinerary and map side by side.
- iPhone is the **Guide** surface: switch between map and list.
- The first vertical slice is intentionally source-only: no persistence, accounts, or legacy import.

## Requirements

- macOS 27
- Xcode 27 beta 3 or later
- iOS 27 Simulator runtime for simulator testing

## Build

```sh
xcodebuild -project TripMap.xcodeproj -scheme TripMap-macOS -destination 'platform=macOS' build
xcodebuild -project TripMap.xcodeproj -scheme TripMap-iOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -project TripMap.xcodeproj -scheme TripMap-macOS -destination 'platform=macOS' test
```

The app opens the fixed “沖縄・瀬底 4日間” sample on Day 2. Selecting an activity selects its map marker; selecting a marker scrolls the activity list to the same item. M1.1 adds explicit empty and no-place states plus shared selection and camera rules documented in [ADR 0002](docs/adr/0002-model-invariants.md).

See [docs/known-issues.md](docs/known-issues.md) for the Xcode 27 beta 3 / iOS 17 Simulator launch incompatibility observed during M1 verification.

## Scope

This repository starts a new `0.x` product line. `travel-ledger-cli` remains a reference implementation and the future schema-v8 exchange boundary; its Rust code, SQLite schema, and CLI architecture are not application dependencies.
