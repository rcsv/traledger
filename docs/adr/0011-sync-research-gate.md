# ADR 0011: Sync requires a local migration runway before CloudKit

Status: Accepted research gate; CloudKit activation blocked

Date: 2026-07-24

## Context

TripMap currently has one local SwiftData store shared by the iOS, iPadOS, and
macOS targets. The store has no explicit `VersionedSchema` or
`SchemaMigrationPlan`. It contains a graph rooted at `StoredTrip`, three
externally stored image fields, and several cascade relationships.

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

The current `StoredTrip.applyPlan` method applies a complete value snapshot and
assigns nearly every stored field. This is safe in a single local writer, but it
is too broad for concurrent replicas: an edit to one Activity can write stale
values over unrelated remote edits. Sync therefore also requires granular
mutation paths or a proven merge layer before activation.

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

CloudKit activation remains blocked until all required rows in
[`sync-research-gate-matrix.md`](../qa/sync-research-gate-matrix.md) have
evidence, the local V1-to-V2 path preserves a realistic fixture store, and no
test requires deleting the application or its data to recover.
