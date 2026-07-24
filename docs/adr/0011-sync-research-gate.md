# ADR 0011: Sync requires a local migration runway before CloudKit

Status: Accepted research gate; CloudKit activation blocked

Date: 2026-07-24

## Context

TripMap currently has one local SwiftData store shared by the iOS, iPadOS, and
macOS targets. It contains a graph rooted at `StoredTrip`, three externally
stored image fields, and several cascade relationships. A local
`VersionedSchema` baseline and `SchemaMigrationPlan` now identify this model as
V1, but V1 still references the live top-level model types.

P8 is limited to same-person, private-database synchronization. Collaboration
and CloudKit sharing remain P10 work.

## Evidence

Apple documents that SwiftData managed sync uses
`NSPersistentCloudKitContainer`, requires iCloud plus Remote notifications
capabilities, and requires a CloudKit-compatible model. Unique constraints,
nonoptional relationships, and the deny delete rule are incompatible. CloudKit
production schemas are additive after promotion:

- [Syncing model data across a person’s devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [ModelConfiguration](https://developer.apple.com/documentation/swiftdata/modelconfiguration)
- [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema)
- [WWDC26 SwiftData Group Lab](https://developer.apple.com/videos/play/wwdc2026/8017/)

CloudKit records have a 1 MB non-asset payload limit. Photos and other large
binary values belong in assets; request and service limits can still change:

- [CKRecord](https://developer.apple.com/documentation/cloudkit/ckrecord)
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)
- [CKError.Code.limitExceeded](https://developer.apple.com/documentation/cloudkit/ckerror/code/limitexceeded)

The app must distinguish `available`, `noAccount`, `restricted`,
`couldNotDetermine`, and `temporarilyUnavailable`, and re-check after the
account-change notification:

- [CKAccountStatus](https://developer.apple.com/documentation/cloudkit/ckaccountstatus)
- [CKAccountChangedNotification](https://developer.apple.com/documentation/cloudkit/ckaccountchangednotification)

## Current schema audit

### Compatible foundations

- Persistent identifiers are UUID attributes, not `@Attribute(.unique)`.
- Every nonoptional scalar has a declared default.
- Every inverse to-one relationship is optional.
- Delete rules use cascade rather than deny.
- Cover, Venue user image, and Memory photo use `@Attribute(.externalStorage)`.
- Computed MapKit route results, Look Around scenes, and remote Wikimedia bytes
  are not persisted as sync-owned records.

### Blocking incompatibilities

The following to-many relationships are nonoptional:

- `StoredTrip.days`
- `StoredTrip.participantAssignments`
- `StoredTrip.checklistItems`
- `StoredTrip.travelLegPreferences`
- `StoredDay.activities`

They must become optional in a later schema version before CloudKit is enabled.
Application accessors must continue to expose empty collections so optional
persistence does not leak into the Domain.

`StoredTrip.applyPlan` applies a complete value snapshot and assigns nearly
every stored field. This is safe in a single local writer, but it is too broad
for concurrent replicas: an edit to one Activity can write stale values over
unrelated remote edits. The first scoped paths now cover Cover, Venue images,
Activity progress, and Memory as described in
[`ADR 0013`](0013-scoped-trip-mutations.md). Structural and composite edits
still require granular mutations or a proven merge layer before activation.

The 1600-pixel JPEG normalization policy has no encoded-byte ceiling and no
per-Trip storage budget. External storage is the correct persistence shape, but
it is not itself a quota policy.

## Decision

Do not add CloudKit entitlements, create a production container, initialize a
server schema, or switch `ModelConfiguration` to `.automatic` in the current
schema.

Adopt sync in four independently releasable stages:

1. **Local V1 baseline**
   - Describe the current model list with `VersionedSchema`.
   - Add a `SchemaMigrationPlan`.
   - Keep `cloudKitDatabase: .none` explicit.
   - Prove that a store written by the current unversioned release opens without
     deletion, export, or identity changes.
2. **Cloud-compatible local V2**
   - Make every relationship optional at the persistence boundary.
   - Preserve nonoptional arrays in Domain projections through normalized
     accessors.
   - Add bounded image encoding and a Trip-level byte inventory.
   - Replace broad snapshot writes with scoped mutations, or prove field-level
     merge behavior for every operation in the matrix.
   - Ship and observe this migration locally before enabling sync.
3. **Development private sync**
   - Use one explicit private container identifier, never discovery by order.
   - Add iCloud and Remote notifications capabilities only to a dedicated
     development configuration.
   - Initialize and inspect the development schema; do not promote it.
   - Present account state without blocking local read/write access.
4. **Release gate**
   - Complete the three-device and conflict matrix.
   - Test upgrade, reinstall, sign-out, quota pressure, and long-offline return.
   - Back up production data before promotion and record the immutable server
     schema.

## Stage 1 implementation

The local V1 baseline was implemented on 2026-07-24:

- `TripMapSchemaV1` names the existing model set as version 1.0.0.
- `TripMapMigrationPlan` contains V1 and no migration stages.
- every production and test `ModelConfiguration` created by `TripMapStore`
  explicitly uses `cloudKitDatabase: .none`;
- an automated disk test writes a production-shaped Trip through the prior
  unversioned `Schema`, then opens the same store with V1 and verifies root and
  child UUIDs, local dates, cover image, Venue image, and Memory photo/text.

This establishes the migration runway. It does not make the V1 relationship
shape CloudKit-compatible and does not unblock sync activation.

### V1 freeze finding

`TripMapSchemaV1` identifies the current schema version, but its `models` list
points to the same top-level `@Model` classes compiled by the live app. Changing
one of those classes for V2 would also change the model metadata returned by V1.
V1 is therefore versioned, but not yet an independently frozen historical model
definition.

An isolated test-only spike proves that a lightweight migration can preserve a
parent and child while changing a to-many relationship from `[Child]` to
`[Child]?`. The spike uses separate nested model definitions for V1 and V2 and
passes in
`testOptionalToManyRelationshipSupportsLightweightMigration`.

With the current Xcode 27 beta SDK, those nested version-specific `@Model`
definitions require a macOS 26 availability boundary even though the test
target deploys to macOS 14. This is useful feasibility evidence, not permission
to raise TripMap's deployment target or replace its production schema. The next
production migration must first prove, on a stable toolchain supporting the
app's iOS 17 and macOS 14 minimums, that frozen historical definitions retain
the exact entity identity and checksum of stores already written by the live
types.

The Stage 2 image prerequisite was also implemented locally:

- `TripImageProcessor` uses Image I/O on every platform, strips the selected
  image to JPEG, preserves a maximum 1600-pixel dimension, and progressively
  reduces quality and dimensions until the encoded result is at most 2 MiB;
- `TripImageStorageInventory` separately counts Cover, Venue user-image, and
  Activity Memory bytes and images;
- 25 MiB per Trip is a soft product-review threshold, not a destructive limit;
- Cover, Venue, and Memory selection paths calculate replacement-aware projected
  usage; growth above the threshold requires explicit confirmation, while
  removal and size-reducing replacement remain uninterrupted;
- Plan Overview and Memory editing expose current or projected usage, and the
  warning explains sync cost without claiming that local save or sync failed;
- Look Around and Wikimedia metadata are excluded because they are not
  user-owned stored image bytes.

Large PNG normalization and byte/pixel limits have automated macOS coverage.
The soft-budget decision rule also has unit coverage. Large HEIC/JPEG inputs,
image orientation, on-device PhotosPicker delivery, and visual confirmation of
the warning remain part of the stable-device gate.

## Scoped mutation implementation

The first conflict-risk reduction landed on 2026-07-25:

- `TripMutation` expresses Cover, user Venue image, external Venue image,
  Trip rename, field-owned Plan/Guide Activity edits, travel-leg preference,
  Activity append/delete/move/progress, Day replication/swap, mutation-aware
  reorder Undo, Memory, currency, and time-zone intents;
- `StoredTrip.applyMutation` reapplies an intent to the latest valid local
  snapshot and writes only its owned fields;
- Venue image intents require the initiating Place UUID and reject stale results
  after Venue replacement or clear;
- Plan and Guide production workspaces use the scoped path for those operations;
- production workspaces reject the full-snapshot compatibility callback, so a
  missing mutation cannot silently become a broad write;
- in-memory persistence tests prove that unrelated edits survive Cover, Venue
  image, and Memory writes.

This is not the Stage 2 exit. Trip date-range editing is not exposed and must
receive a scoped structural design before introduction. Same-field resolution,
delete-versus-edit policy, concurrent reorder policy, and real replica
convergence also remain unproven.

## Data and UX rules

- Local data remains usable when iCloud is absent, restricted, indeterminate,
  or temporarily unavailable.
- “Synced” must never be inferred from a successful local save.
- The app must not promise an exact completion time for asynchronous sync.
- Account changes must not cause local deletion or automatic store replacement.
- Remote notification is a change hint, not proof that all changes arrived.
- Same-field conflict behavior must be observed and documented before choosing
  silent resolution. Independent-field edits must not regress.
- Reservation references, confirmation codes, private notes, and reflections
  belong only to the private database in P8.
- Place enrichment remains derived/cache-like. User-selected Venue images and
  Activity Memory photos are user data and must not be silently discarded to
  relieve quota pressure.

## Exit criteria

CloudKit activation remains blocked until V1 has an independently frozen,
back-deployable historical definition, all required rows in
[`sync-research-gate-matrix.md`](../qa/sync-research-gate-matrix.md) have
evidence, the local V1-to-V2 path preserves a realistic fixture store, and no
test requires deleting the application or its data to recover.
