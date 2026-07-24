# P9 System Experience Gate Matrix

Status: App Intent implementation complete; stable-device invocation open

Date: 2026-07-24

## Automated projection and build gates

| ID | Scenario | Required result | Current evidence |
| --- | --- | --- | --- |
| S01 | No Trip has a Day today | Return a neutral no-current-plan response | projection test boundary |
| S02 | Today has a future planned Activity | Return Next using the Trip time zone | projection test |
| S03 | Today has active and future Activities | Return Now then Next from Guide projection | projection test |
| S04 | Multiple Trips overlap | Active Activity wins, then earliest time, then stable UUID | projection test |
| S05 | Activity is completed or skipped | Never expose it as Now or Next | shared Guide tests |
| S06 | Stored snapshot is invalid or store open fails | Do not reset or write; ask the user to open TripMap | Intent implementation |
| S07 | Intent metadata extraction | One discoverable read-only Intent and expected App Shortcut phrases | generic iOS build artifact |

## Privacy gates

The Intent response may expose Trip title, Activity title, local start time, and
Venue name after explicit invocation.

The following must never appear in the dialog, logs, shortcut parameters, or
returned values:

- reservation confirmation code, URL, or note;
- Activity note;
- Participant name or note;
- Memory reflection or image data;
- Venue image provider URL, author metadata, or cached bytes.

Automated coverage currently injects a reservation title, confirmation code,
and note and verifies that none is included.

## Stable-device invocation gates

Run on one supported iPhone, iPad, and Mac with the same fixtures:

| ID | Invocation | Required result |
| --- | --- | --- |
| D01 | Find “次の予定” in Shortcuts | Tile, symbol, and Japanese title are present |
| D02 | Run from Shortcuts while app is closed | Correct local response; app need not foreground |
| D03 | Run both Japanese Siri phrases | Intent resolves without asking for an unrelated parameter |
| D04 | Change device time zone during a Trip | Activity time remains formatted in the Trip time zone |
| D05 | Complete the returned Activity, then run again | Response advances to the next planned Activity |
| D06 | Enable Airplane Mode and run | Local response remains available |
| D07 | Corrupt-copy fixture or unavailable store | Non-destructive recovery message; data is not reset |
| D08 | Inspect Siri/Shortcuts history and logs | No prohibited privacy field is present |
| D09 | Invoke while all participating devices are locked | Authenticate before itinerary details are returned |
| D10 | Invoke from an authenticated paired device | Follow system authentication policy without disclosing to an unauthenticated requester |

Beta-toolchain build and metadata evidence cannot close D01–D08. These rows are
deferred while a stable Xcode and supported runtime are unavailable.

## Expansion gate

Before Spotlight, Handoff, or WidgetKit:

1. define and test a versioned Trip/Activity deep-link route;
2. define deletion and stale-index cleanup;
3. decide whether search results may expose Trip and Activity titles while the
   device is locked;
4. keep Widget content free of confirmation codes and private notes;
5. decide and test App Group store migration before any extension reads
   SwiftData.
