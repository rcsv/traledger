# TripMap

TripMap is a local-first Apple-platform trip workspace built with SwiftUI,
SwiftData, and MapKit.

- macOS is the primary **Planner** surface.
- iPhone is the primary **Guide** surface.
- iPadOS will adapt between Planner and Guide according to the available width.
- The same Trip, Day, Activity, Venue, and participant data grows into a
  post-trip **Memory** surface.

The current implementation includes a SwiftData-backed Trip library, Trip and
Activity editing, Venue search, MapKit maps and travel estimates, participants,
checklists, Trip Doctor diagnostics, user-selected images, Look Around, and a
Wikimedia exact-venue image fallback.

## Development environment

- The project currently deploys to macOS 14 and iOS 17 or later.
- The repository is being developed with Xcode 27 beta.
- Use the iOS 27 Simulator runtime with the current beta toolchain. The installed
  iOS 17 runtime has a known binary compatibility problem described in
  [Known issues](docs/known-issues.md).

## Build

```sh
xcodebuild -project TripMap.xcodeproj -scheme TripMap-macOS -destination 'platform=macOS' build
xcodebuild -project TripMap.xcodeproj -scheme TripMap-iOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -project TripMap.xcodeproj -scheme TripMap-macOS -destination 'platform=macOS' test
```

The app opens a Trip library. macOS opens each Trip in its own Planner window;
iPhone opens the selected Trip in the Guide. Development fixtures include the
“沖縄・瀬底 4日間” sample and adversarial model cases.

## Product and implementation direction

- [Apple Platform Product Master Plan](docs/apple-platform-product-master-plan.md)
  is the cross-platform implementation directive.
- [Product direction](docs/product-direction.md) defines the Planner / Guide /
  Memory concept and the current product sequence.
- [Venue Card specification](docs/place-card-spec.md) defines the Activity /
  Venue boundary and image-source policy.
- [ADR 0002](docs/adr/0002-model-invariants.md) defines shared selection and
  model invariants.

Update the relevant specification and acceptance criteria in the same change
that alters a product decision.

## Scope

This repository is the native `0.x` product line. `travel-ledger-cli` remains a
reference implementation and the future schema-v8 exchange boundary; its Rust
code, SQLite schema, and CLI architecture are not application dependencies.
