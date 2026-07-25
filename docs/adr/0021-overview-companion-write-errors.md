# ADR 0021: Overview companion writes fail visibly and roll back

Status: Accepted

Date: 2026-07-25

## Context

Trip Overview edits Participant assignments and Checklist items through their
own SwiftData models. These writes are not `TripMutation` operations because
they do not own fields in the immutable `Trip` snapshot.

The Overview previously used `try?` for these saves. A store failure could
therefore look successful until the next fetch or app launch, and the
Participant picker or Checklist editor could close without a durable change.

## Decision

Participant assignment, assignment removal, Checklist creation, and Checklist
completion changes use one local persistence boundary:

1. mutate only the intended companion model;
2. call `ModelContext.save()`;
3. dismiss an initiating picker or editor only after success;
4. roll back the context and present the localized error after failure.

A missing owning `StoredTrip` is also a visible failure. It does not create a
detached assignment or Checklist item.

## Consequences

- The UI never reports a companion-model save as successful when SwiftData
  rejected it.
- Checklist text and Participant selection remain available for retry.
- A failed toggle, removal, or insertion is restored by rollback.
- `TripMutation` remains limited to fields owned by the Trip snapshot; this
  change does not broaden its scope or alter the schema.

## Verification

- macOS and generic iPhone/iPad builds pass.
- The local Participant round-trip persistence regression test passes.
- Store-failure alert presentation and retained picker/editor state remain in
  the stable-Xcode interaction gate.
