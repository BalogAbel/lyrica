# Sync Snapshot Identity

> Status: Draft

## Goal

Close the PR #64 re-review finding: a local edit made **while a sync is waiting on
the backend** can be silently discarded, never sent.

## Problem

Both sync controllers read a snapshot of pending work, send it, and then write
the result back **keyed only by aggregate identity** — never checking that the
local row is still the one that was sent.

**Planning** (`PlanningMutationSyncController._run`): the loop sends
`syncMutation(record: mutation)` and awaits the backend. On success it calls
`saveSyncAttemptResult(..., accepted)` keyed by `aggregateType`/`aggregateId`,
and later `clearMutation` on the same key.

**Songs** (`SongMutationSyncController._runSync`): the same shape, with
`reconcileSyncedSong` unconditionally deleting the song's mutation row.

The window is the remote round trip. During it, the user can edit the same
aggregate. Because `CachedPlanningMutations` holds one row per aggregate and
`recordPlanEdit` folds into it, the newer intent lands in the very row the sync
is about to mark accepted and delete. The result: the backend has version *n*,
the user's later edit is gone, and nothing was ever sent for it. No error, no
conflict, no trace.

The per-context write queue added earlier does not prevent this and must not: the
remote wait is deliberately outside the queue, because holding a local write lock
across a network call would block every local edit for the duration of a sync.

This is the most serious class of defect in this phase — a silent loss of
unsynced user intent on the sync path — and it is reachable in ordinary use:
edit a plan, go online, keep typing while the sync runs.

## Decisions

### D1 — Every local mutation row carries a monotonic local revision

Both mutation tables gain a `localRevision` integer column, incremented by the
store on **every** local write to that row. It identifies the exact content that
was handed to the sync, and it is local bookkeeping only — never sent to the
backend, never part of OCC, and unrelated to the record's `version`/`baseVersion`,
which track the *server's* view.

**Why not reuse `updatedAt`.** Two writes inside the same millisecond produce the
same timestamp, and a device clock can step backwards — LF-T6 records exactly
that the device clock is unanchored, and this is a guarantee that must not depend
on it. A counter the store owns is monotonic by construction.

This requires a schema migration on both the planning and the catalog database.
The remediation plan that preceded this work stated it would add no migration;
that boundary is deliberately crossed here, because the alternative is a
correctness guarantee resting on a clock the codebase already documents as
untrustworthy.

### D2 — Post-sync writes are conditional on the revision that was sent

The sync captures each record's `localRevision` when it takes its snapshot, and
passes it back into the write that concludes the exchange:

| write | condition |
|---|---|
| planning `saveSyncAttemptResult(accepted)` | apply only if the row's revision still equals the one sent |
| planning `clearMutation` after reconcile | delete only if the revision still matches |
| song `reconcileSyncedSong` | drop the mutation row only if the revision still matches |

When the revision has moved, the row is left **pending** with the newer content,
so the next sync sends it. The already-accepted remote write is not undone —
it happened, and the newer local intent is a subsequent edit on top of it, which
is exactly what the user expressed.

Conditioning happens **inside the storage boundary**, as part of the same
statement, not as a read-then-write in Dart: a check in application code would
reopen the same window it is closing.

### D3 — A stale conclusion is not an error

Discovering that the revision moved is an ordinary outcome, not a failure. The
sync does not throw, does not mark a conflict, and does not retry the remote
call. It simply leaves the row pending and moves on, and the next sync picks it
up. Failing loudly here would turn "the user kept working" into an error state.

## Non-Goals

- Changing OCC or `baseVersion` semantics. `localRevision` is local bookkeeping
  and never leaves the device.
- Holding the write queue across the remote call.
- Any change to what the backend authorises.
- Riverpod 3, web offline E2E, or any Phase 5 item.

## Testing

Both domains get a gated-remote test, in the shape the finding specifies:

1. **Planning: an edit during the remote call survives.** Gate the remote call on
   a `Completer`. Start a sync; while it is blocked, apply a further local edit to
   the same aggregate; release the remote call. Afterwards the mutation is still
   **pending**, carries the newer content, and a second sync sends it.
2. **Songs: the same**, against `reconcileSyncedSong`.
3. **The unchanged case still completes.** With no concurrent edit, the record is
   marked accepted and cleared exactly as before — the condition must not break
   the ordinary path.
4. **The revision is monotonic** across every local write path that touches a
   mutation row, including folds and status writes.
5. **Migration.** Both databases open an existing pre-migration database, gain the
   column, and keep their pending rows intact — extending the existing
   `planning_migration_test.dart` and `song_catalog_migration_test.dart` rather
   than starting new harnesses.

Each of tests 1 and 2 must fail against the current unconditional writes; watch
them fail before implementing.

## Documentation

- An ADR for the snapshot-identity contract, or an amendment to ADR-019 if that
  is where exactly-once already lives — decide by reading it, and record why
  `localRevision` is not OCC.
- `docs/architecture/architecture.md` Offline Strategy and
  `docs/testing/testing-strategy.md`.
- `docs/architecture/repository-review-2026-06-22.md`: extend the PR #64
  remediation status block.
