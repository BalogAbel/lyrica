# ADR-030: Sync Snapshot Identity via Local Revision

- Status: Accepted
- Date: 2026-08-05
- Spec: `docs/specs/2026-08-05-sync-snapshot-identity.md`
- Relates to: ADR-019 (exactly-once planning mutation sync)
- Scope: planning half only. The song/catalog half of the same spec is a
  separate change; this ADR does not claim it.

## Context

The PR #64 re-review found the most serious class of defect in the offline
durability phase: a silent loss of unsynced user intent on the sync path,
reachable in ordinary use — edit a plan, go online, keep typing while the
sync runs.

`PlanningMutationSyncController._run` reads a snapshot of pending mutations,
sends one to the backend, and awaits the remote round trip. On success it
writes `saveSyncAttemptResult(..., accepted)` and later `clearMutation`, both
keyed only by `aggregateType`/`aggregateId` — never checking that the local
row is still the one that was sent.

`CachedPlanningMutations` holds one row per aggregate, and `recordPlanEdit`
folds a new edit into that same row (this is deliberate — see the squash
correctness work behind ADR-028's D-series). During the remote wait, the user
can edit the same aggregate; the newer intent lands in the very row the sync
is about to mark accepted and delete. Before this change, both post-sync
writes were unconditional: `saveSyncAttemptResult` would overwrite the row's
status to `accepted` regardless of what it now contained, and the
`clearMutation` that follows would delete it outright. The backend ends up
with version *n*; the user's later edit is gone, and nothing was ever sent
for it. No error, no conflict, no trace — confirmed by a test that watched
this exact loss happen against the pre-fix code (the mutation was found
`null` — deleted — after the race, not merely stale).

The per-context write queue `BudgetedPlanningMutationStore` already
serializes (`ADR-028` D9) does not close this window and must not: the
remote wait is deliberately outside that queue, because holding a local
write lock across a network call would block every local edit for the
duration of a sync.

## Decision

### D1 — Every local mutation row carries a monotonic local revision

`CachedPlanningMutations` gains a `localRevision` integer column
(schemaVersion 5 → 6), incremented by the store on **every** local write to
that row: every `record*` call (including a fold, such as `recordPlanEdit`
landing on a still-pending `planCreate`), `retryMutation`, and
`saveSyncAttemptResult`. It identifies the exact content that was handed to
a sync attempt.

**This is not OCC, and it never leaves the device.** `baseVersion` (and the
projection's `version`) track the *server's* view of the aggregate, feed
optimistic-concurrency checks on the backend RPCs, and are exactly the
mechanism ADR-019 already relies on. `localRevision` tracks only "has
anything local written to this row since I last looked," is never read by
the backend, and is never part of a conflict decision. The two columns sit
next to each other in the same table and are easy to conflate; they answer
different questions for different parties (the device asking about itself,
versus the device and backend agreeing about the aggregate).

**Why not reuse `updatedAt`.** Two local writes inside the same millisecond
produce the same timestamp, and LF-T6 already documents that the device
clock is unanchored and can step backwards. A guarantee that a write
happened *after* another one cannot rest on a clock the codebase already
distrusts for exactly that reason. A counter the store owns is monotonic by
construction, independent of wall-clock behavior.

This crosses a boundary the LF-T3/LF-T4 remediation plan (ADR-028) stated it
would not: it adds a schema migration. That trade was made deliberately —
the alternative is a correctness guarantee for the most serious defect in
this phase resting on exactly the untrustworthy clock LF-T6 already flags.

### D2 — Post-sync writes are conditional on the revision that was sent

The sync captures a mutation's `localRevision` when it snapshots the
candidate list, before the remote call, and passes it back into the writes
that conclude the exchange:

| write | condition |
|---|---|
| `saveSyncAttemptResult(accepted)` | applies only if the row's revision still equals the one captured at snapshot time |
| `clearMutation` after a successful refresh or reconcile | deletes only if the row's revision still equals the value the accept-write itself just landed (not the pre-send snapshot — the accept-write is itself a local write, so it advances the revision too) |

Both `saveSyncAttemptResult` and `clearMutation` gained an optional
`expectedRevision` parameter. **The condition is expressed inside the
storage boundary, as a `WHERE localRevision = ?` clause on the same `UPDATE`
or `DELETE` statement that performs the write** — not as a preceding
`SELECT` compared in Dart. A read-then-decide in application code would
reopen the exact window this decision closes: the row could change between
the read and the write. Because the actual gating value (`expectedRevision`)
is the one the *caller* captured before the remote round trip, a store-side
`SELECT` used only to raise "record not found" (never used to decide the
write) does not reintroduce that race — the WHERE clause is still the sole
arbiter of whether the write applies.

This requirement could not be met by extending `_upsertRecord` (the
`INSERT ... ON CONFLICT DO UPDATE` every other `record*` write uses):
Drift's typed `Companion` writes hold literal values, not an atomic
compare-and-set condition, and an upsert has no WHERE clause to attach one
to. `saveSyncAttemptResult` and `clearMutation` were rewritten as targeted,
typed `UPDATE`/`DELETE` statements instead — a deliberate, narrow deviation
from the store's established upsert shape, confined to exactly the two
writes D2 conditions.

Only the accepted-status write and the clears that follow it are gated. The
failure-status writes in the same controller (marking `failedAuthorization`,
`conflict`, etc. after a remote error, and the `failedDependency` write for
a corrupt reconcile) are out of this contract's scope: they never claim the
backend accepted anything, so they cannot manufacture the specific silent
loss this ADR closes. Widening the gate to every status write is a
plausible future hardening, not something this change claims.

### D3 — A stale conclusion is not an error

Discovering that a row's revision moved is an ordinary outcome, not a
failure. `saveSyncAttemptResult` returns the row's new revision (an `int`)
when the write applied, or `null` when it did not; `clearMutation` returns
`bool`. Neither throws for a stale condition, marks a conflict, or retries
the remote call. The sync controller checks the return value and, on a
miss, simply moves on to the next candidate — no logging, no status change,
nothing. The already-accepted remote write is not undone (it happened), and
the row is already exactly where it needs to be: every local write
(including the fold that caused the staleness) resets `syncStatus` back to
`pending`, so the newer content is picked up by the very next sync run
without any special handling.

## Non-Goals

- Changing OCC or `baseVersion` semantics. `localRevision` is local
  bookkeeping and never leaves the device.
- Holding the per-context write queue across the remote call.
- Any change to what the backend authorizes.
- The song/catalog half of the same spec (`reconcileSyncedSong`) — a
  separate change.
- Gating the failure-status writes in `PlanningMutationSyncController._run`
  by revision (see D2).
- Riverpod 3, web offline E2E, or any Phase 5 item.

## Known Follow-Up (not fixed here)

While implementing D1, a related but distinct gap surfaced: `recordPlanEdit`
folding onto a `planCreate` row copies forward whatever `syncStatus` that
row currently has (`existing.copyWith(...)` never touches `syncStatus` on
that branch), rather than resetting it to `pending`. In the narrow window
where a `planCreate` mutation is `accepted` but not yet cleared — reachable
per ADR-019's own LF-1 scenario (a crash between accept and clear) — an edit
landing in that window keeps the row `accepted` with newer, never-sent
content. The `localRevision` gate on `clearMutation` still protects the row
itself from being deleted (a mismatched revision leaves it pending... in
this case, still marked `accepted`, not `pending`), but a *subsequent* sync
run's durable-marker branch (`syncStatus == accepted` skips the remote send
entirely) would then reconcile and clear that row using the unsent edited
content as if the backend had already confirmed it — silently diverging the
local projection from server truth. This is a different mechanism than the
defect D1-D3 close (it is not caused by an unconditional post-sync write; it
is caused by a local write not resetting status on an already-concluded
row) and is out of this ADR's scope. Flagged for a follow-up, not fixed
here.

## Validation

Watched failing before the fix, against the real `DriftPlanningMutationStore`
(not a hand-rolled fake, since the fix lives inside the storage boundary): a
sync gated on a `Completer`, with a `recordPlanEdit` applied to the same
aggregate while the gate is held, resulted in the mutation being read back as
`null` — deleted outright by the unconditional `clearMutation` — after the
gate released and the sync completed.

- `apps/lyron_app/test/offline/adversarial/planning_sync_snapshot_identity_test.dart`
  — the gated-remote-call race described above (now passes: the row survives,
  pending, with the newer content, and a second sync sends it) and the
  unchanged-case regression check (no concurrent edit still accepts and
  clears exactly as before).
- `apps/lyron_app/test/offline/planning/planning_mutation_store_test.dart`
  (`PlanningMutationStore.localRevision` group) — the revision advances by
  exactly one on every local write path, including the fold this ADR's
  Context section names and a status write; a matching `expectedRevision`
  applies and reports the new revision, a stale one reports `null`/`false`
  and leaves the row untouched.
- `apps/lyron_app/test/offline/adversarial/planning_migration_test.dart` — a
  genuine pre-migration (schemaVersion 5) database, built by hand against the
  exact schema Drift generated before this column existed, gains
  `localRevision` on open with a sane starting value and keeps its pending
  row intact.
