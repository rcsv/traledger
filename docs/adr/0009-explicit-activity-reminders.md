# ADR 0009: Local notifications require explicit Activity reminder intent

Status: Accepted for the P6 Guide readiness slice

Date: 2026-07-24

## Decision

An Activity may store one optional `ActivityReminderLeadTime`. The supported
choices are start time, 5, 15, or 30 minutes before, 1 hour before, and 1 day
before. A reminder is invalid without an Activity start time.

The app never infers reminders from reservations, Venue data, notes, Now / Next,
or imported content. Replicating a Day does not copy reminder intent, preventing
an edit operation from silently multiplying notifications.

`ActivityReminderProjection` converts only future, planned Activities with
explicit reminder intent into deterministic schedules. Completed, skipped,
past, untimed, and unconfigured Activities do not produce schedules.

## UserNotifications boundary

The Guide Quick Edit exposes the reminder toggle next to the Activity time.
Enabling it is the action that may trigger the system notification permission
prompt. Saving an unrelated edit does not request permission.

After plan persistence succeeds, the iOS adapter replaces pending requests for
that Trip with the current projection. Removing a reminder therefore removes
its pending notification. Existing intent remains stored if permission is
denied, and the app explains that the plan was saved.

Notification content is deliberately minimal:

- generic title: “予定のリマインダー”;
- body: Activity title;
- no reservation title or confirmation code;
- no Venue name or address;
- no Participant data or notes.

Lock-screen visibility remains under the system notification settings. The
first slice does not add remote notifications, background refresh, recurring
alerts, critical alerts, or notification actions.

Time scheduling uses the Activity’s absolute `Date`, derived from the Trip
timezone, and a nonrepeating time-interval trigger. This preserves the intended
instant when the device changes timezone.

## Verification

Deterministic tests cover the start-time invariant, explicit clear behavior,
future/planned filtering, lead-time calculation, stable request identifiers,
and SwiftData round-trip. The UserNotifications adapter is compile-checked in
the iOS target. Permission prompts, delivery, and lock-screen presentation are
visual/device gates to resume when a stable Simulator/Xcode runtime is
available.
