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
silent loss. The user decided on 2026-09-30 to fix it in its own slice, not
in the plan-delete PR.

## STOP condition 5 clarification

The originating plan's STOP condition 5 forbids a base value that was not
captured from the local projection or moved by D7's contiguity rules. A
creation-time base of `(1, 1)` does not break the invariant that rule
protects (I3: a base never absorbs a foreign write).

- 1 is the smallest value either version can have. Every accepted write
  only raises it, so a base of 1 cannot include a write the client has not
  seen.
- D5(b) and D5(c) already use the same value: a new plan's content
  version is 1.
- If anyone wrote to the object in the meantime, the backend's version
  check turns the delete into a `conflict`. That is the fail-safe
  direction.

## Solution options

### (a) Convert at run start to a delete based on `(1, 1)`

- At the start of a sync run, turn every stale `cancelling` row into a
  pending delete of its object with the creation-time base:
  - plan: `baseVersion = 1`, `baseContentVersion = 1`
  - session: `baseVersion = 1`
- A `*_not_found` response to a delete converted from a tombstone closes the
  row automatically. The create never committed, so there is nothing to
  delete.
  - The converted row must record that it came from a tombstone. A
    user-recorded delete keeps today's visible `failedRemoteDelete` path
    (D9 classification).
- If the create committed and nobody has touched the object since, the
  delete succeeds.
- Otherwise it conflicts visibly, and the conflict retry (D9) deletes it as
  it now is.
- Session items need extra care. `delete_session_item` checks the session's
  version before it looks for the item, and the item's own creation already
  bumped that version.
  - A base of 1 therefore conflicts whenever the session has moved past 1,
    even if the item never committed. The result is a visible conflict
    rather than an automatic close.
  - The slice must decide whether that noise is acceptable, or whether an
    item needs a different creation-time base.

### (b) Resend the create and keep the tombstone

- Resend the create behind a stale tombstone. Do not write the `sending`
  marker over the tombstone.
- Resolve the tombstone through `resolveCancelledCreate` with the
  backend-returned `acceptedBaseVersion`, exactly as D5(b) does for a live
  one.
- This only works with an idempotent create RPC.
  - Today's create RPCs are not idempotent. For example, `create_session`
    re-raises any `unique_violation` other than its slug and position keys.
  - So resending a create that had already committed fails on the
    duplicate primary key. That failure looks like "not created", the
    tombstone is discarded, and the deleted object comes back.
  - Option (b) therefore first needs the create RPCs to return the existing
    row, or a distinguishable "already exists" result, for a duplicate id.

## Requirements for the slice that picks this up

- At the start of a sync run no call of this context can be in flight
  (single-flight), so any `cancelling` row seen there is stale.
- Choose (a) or (b) and record the choice in an ADR amendment (ADR-030's
  in-flight create cancellation follow-up).
- Whatever the choice, a connectivity failure must keep the stale intent
  for the next run, never discard it.
- Cover plan, session, and session-item tombstones alike. Check whether the
  song side (`pendingCreate` tombstones in the catalog) has the same gap.
- Red tests first: a tombstone stranded by an aborted run is resolved by the
  next run, for both a committed and an uncommitted create.

## Roadmap (2026-10-01)

Scheduled in slice **S5b** (`fix/planning-mutation-gaps`) of
`docs/plans/2026-10-01-delivery-roadmap.md`. The S5b spec confirms or
overrides the recommended defaults:

- **Option (a).** Option (b) needs idempotent create RPCs, a backend change
  that would also pull in LF-T5b.
- **For session items, accept the visible conflict noise** of a creation-time
  base of 1.
