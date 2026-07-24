# P8 Sync Research Gate Matrix

Status: Stage A in progress; CloudKit is not enabled

Date: 2026-07-24

This matrix is the release evidence contract for same-person private sync. A
successful launch or a single two-device edit is not sufficient.

## Supported topology

| Role | Required platform | Purpose |
| --- | --- | --- |
| A | iPhone | primary edits, offline return, PhotosPicker assets |
| B | iPad | concurrent edits and adaptive UI |
| C | Mac | bulk review, relaunch, migration and conflict observation |

Use separate physical devices or stable Simulator runtimes signed into a
dedicated test account. Beta-only results may inform investigation but cannot
close the release gate.

## Stage A — versioning and local migration

| ID | Scenario | Required result | Automation |
| --- | --- | --- | --- |
| M01 | Open an unversioned production-shaped store with local V1 | All entity counts, UUIDs, dates, order, and images remain equal | macOS test |
| M02 | Reopen local V1 after save and relaunch | No duplicate root or child records | macOS test |
| M03 | Migrate V1 to local V2 | Optional relationships normalize to empty Domain arrays | macOS test |
| M04 | Interrupt migration using a copied store | Original copy remains recoverable; no reset path is offered | integration test |
| M05 | Open a future/unknown schema | Show non-destructive store-unavailable UI | integration test |
| M06 | Upgrade a store with empty, dense, and adversarial Trips | All validation invariants remain true | macOS test |
| M07 | Freeze V1 into version-specific model definitions | Existing V1 store entity identities and checksums remain compatible on iOS 17 / macOS 14 | stable-toolchain fixture test |

Current evidence:

- M01 passes in
  `testVersionedStoreOpensUnversionedStoreWithoutDataLoss`.
- M02 passes in `testDiskBackedStoreReopensSavedTrip`.
- A test-only, macOS 26-available spike proves the core M03 relationship change:
  `testOptionalToManyRelationshipSupportsLightweightMigration` preserves the
  parent, child, UUIDs, scalar values, and inverse when `[Child]` becomes
  `[Child]?`.
- M03 is not closed for the production graph. The current V1 schema references
  live top-level models rather than frozen version-specific definitions.
- M04–M07 remain required before a Cloud-compatible V2 can ship. M07 must run
  with a stable toolchain at the supported iOS 17 / macOS 14 minimums; beta-only
  evidence cannot close it.

## Stage B — image budget

| ID | Scenario | Required result | Automation |
| --- | --- | --- | --- |
| Q01 | Normalize very large HEIC/JPEG/PNG | Accepted output meets pixel and byte ceilings | platform unit test |
| Q02 | Cover + Venue + Memory assets near Trip soft budget | Inventory is exact and UI warns before adding data | unit + UI |
| Q03 | Asset upload fails or is deferred | Local photo remains visible and retryable | device integration |
| Q04 | One asset changes while another device edits text | Both changes survive | three-device |
| Q05 | User removes a photo | Removal converges without removing its Activity | three-device |

No automatic deletion policy may be introduced to make Q02–Q04 pass.

Current evidence:

- Q01 is partially automated: a 3200×2400 PNG is normalized to JPEG within the
  1600-pixel and 2 MiB ceilings, and malformed data is rejected.
- The pure Trip inventory has automated Cover/Venue/Memory separation and count
  coverage.
- Q02's product rule and UI wiring are implemented: only growth above 25 MiB
  asks for confirmation; removal and size-reducing replacement are never
  blocked. Cover, Venue, and Memory all use the same replacement-aware
  projection.
- HEIC/JPEG device inputs, orientation, visual/device confirmation of Q02, and
  Q03–Q05 remain open.

## Stage C — account and lifecycle

| ID | Scenario | Required result |
| --- | --- | --- |
| A01 | `available` | Local saves continue; sync state may progress asynchronously |
| A02 | `noAccount` | Existing local data stays readable and editable |
| A03 | `restricted` | Explain account restriction without a destructive recovery action |
| A04 | `couldNotDetermine` | Keep local mode; offer passive retry |
| A05 | `temporarilyUnavailable` | Keep cached data, do not enqueue a retry storm, observe account change |
| A06 | Sign out while app is running | No local deletion; status refreshes |
| A07 | Sign into another account | Never merge identities silently; require an explicit product decision |
| A08 | Remote notification is delayed/coalesced | Foreground/relaunch reconciliation still converges |
| A09 | App is killed during import/export | Relaunch reaches a valid local graph |

## Stage D — three-device convergence

For every row, start all devices at the same revision, perform the listed edits
without relying on push timing, reconnect, foreground each app, and compare
Domain snapshots by stable UUID.

| ID | A edit | B edit | Required result |
| --- | --- | --- | --- |
| C01 | Rename Trip | Add Activity | Both survive |
| C02 | Edit Activity title | Add reservation to another Activity | Both survive |
| C03 | Add Memory photo | Edit its reflection | Both survive or an explicit conflict is shown |
| C04 | Move Activity | Edit that Activity on B | No duplicate or orphan; policy is documented |
| C05 | Delete Activity | Edit same Activity on B | No resurrection without an explicit, documented policy |
| C06 | Reorder Day | Reorder a different Day | Both orderings survive |
| C07 | Change Venue | Set user Venue image | Venue and image ownership remain coherent |
| C08 | Clear Venue | Automatic Look Around/Wikimedia resolution on B | Derived image work cannot recreate cleared user data |
| C09 | Complete Activity | Schedule its reminder on B | Invalid reminder/progress combinations are rejected or reconciled |
| C10 | Delete Trip | Edit child on B | No orphan graph or silent duplicate Trip |
| C11 | 30 days offline, then reconnect | Continue editing on B/C | All supported changes converge |
| C12 | Three simultaneous independent Trip edits | Different Trip on each device | No cross-Trip blocking or data loss |

## Observability record

Each manual run must capture:

- app version, schema version, OS, Xcode, and hardware/runtime;
- test account and CloudKit environment, without credentials;
- initial and final entity counts plus stable-ID snapshot digest;
- timestamps for local save, first remote observation, and convergence;
- account status transitions and recoverable errors;
- screenshots for conflict/account/quota UX;
- exported `.xcresult`, device logs, and a redacted CloudKit Console record
  inventory.

Sync latency is diagnostic only. Correct eventual state and non-destructive
recovery are the pass criteria.
