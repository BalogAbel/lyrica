# Create Tombstones Stranded by an Interrupted Sync Run

**Slice:** feat/plan-delete-session-cascade (found by review gate 3 on
2026-09-30; the gap predates that slice for session and session-item
creates, and the slice extends it to plan creates)
**Related:**
- `docs/specs/2026-08-06-in-flight-create-cancellation.md` (D1–D4)
- `docs/specs/2026-09-29-plan-delete-and-session-cascade.md` (D5(b), D9)
- ADR-030's in-flight create cancellation follow-up
- `docs/deferred/2026-09-28-client-abandoned-committed-write-lf-t5b.md`

**Files:**
- `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
  (`_run`: candidate filter, tombstone resolution)
- `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
  (`resolveCancelledCreate`, `recordPlanDelete`, `recordSessionDelete`,
  `recordSessionItemDelete`)

## Problem

Deleting a create whose remote call is in flight (`sending`) rewrites its
row as a `cancelling` tombstone. The run that sent the create resolves the
tombstone once the call concludes: a success converts it into a pending
delete based on the response, and a failure discards it.

Nothing else ever resolves a tombstone. If the run never reaches
`resolveCancelledCreate`, the tombstone is stranded. That happens when the
app is killed, or the run aborts on an exception from the accepted-marker
write, on an `Error`, and so on. After that:

- The candidate filter (`pending`, `accepted`, `sending`) never picks the
  row up again, so it is never sent or resolved.
- It is excluded from merged reads, but it shows in the sync popup (as
  "plan added" / "session added" / "song added"). `hasUnsyncedMutations`
  stays true until the user discards it.
- If the create had committed, the next refresh brings the object back
  into the projection, and the delete intent is lost.

## What the originating slice already closed

- **Plan re-delete** (gate 3 F2). A delete of a plan whose create
  tombstone is stranded, once a refresh shows the plan again, records a real
  pending `planDelete` from the projection bases. It is no longer a
  permanent silent no-op.
- **Retry** (gate 3 re-verification N4). `retryMutation` never touches a
  `cancelling`, `sending`, or `accepted` row. A group retry can no longer
  turn a stranded tombstone back into a live create that re-creates what the
  user deleted.

## Still open

- A tombstone whose create never committed, or whose object has not
  reappeared through a refresh, is never sent or resolved. The only exit is
  discarding it in the popup.
- For sessions and session items, deleting the reappeared object while the
  tombstone exists collapses the tombstone. The intent is lost again, and a
  further delete is needed.

## Why it was deferred

The gap predates the slice and is visible and discardable, so it is not a
silent loss. The fix the reviewer first proposed conflicts with the slice's
rule that every base value is captured from the projection or moved by D7's
contiguity rules. That proposal was to convert every leftover tombstone at
run start into a pending delete with base `(1, 1)`. The user decides the
approach.

## Requirements for the slice that picks this up

- At the start of a sync run no call of this context can be in flight
  (single-flight). Any `cancelling` row seen there is stale.
- Preferred approach, with no invented base: treat a stale tombstone like a
  crash-stale `sending` row.
  - Resend the create, keeping the tombstone. Do not write the `sending`
    marker over it.
  - Then resolve the tombstone through `resolveCancelledCreate` with the
    backend-returned `acceptedBaseVersion`, exactly as D5(b) does for a
    live one.
  - A duplicate-key failure is the LF-T5b family: the object reappears
    visibly and can be deleted again.
  - A connectivity failure must keep the tombstone for the next run, not
    discard it. A live tombstone discards it today.
- Cover plan, session, and session-item tombstones alike. Check whether the
  song side (`pendingCreate` tombstones in the catalog) has the same gap.
- Red tests first: a tombstone stranded by an aborted run is resolved by the
  next run, for both a committed and an uncommitted create.
