# Sync Snapshot Identity

> Status: Implemented

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

## Implementation

Landed on `feat/offline-durability-phase4`, in three parts, in this order:

Planning half:

- `61717fe` test(planning): red — local edit during remote sync is destroyed
- `4d50c1e` feat(planning): green — add `localRevision` schema column (D1)
- `faef372` fix(planning): green — gate post-sync writes on `localRevision` (D2/D3)
- `54e7700` test(planning): green — D2/D3 characterization coverage
- `94d974c` docs(planning): record the sync-snapshot-identity contract (ADR-030)

Song/catalog half:

- `9f3c303` feat(catalog): green — add `localRevision` schema column (D1)
- `fdadaff` test(catalog): red — local edit during remote sync is destroyed
- `febd111` fix(catalog): green — gate `reconcileSyncedSong` on `localRevision` (D2/D3)
- `db6f87e` test(catalog): green — D2/D3 characterization coverage
- `e0873de` style(catalog): dart format `song_sync_snapshot_identity_test.dart`

Fold-status follow-up (see below):

- `a98c496` test(planning): red — content folds must reset status to pending
- `8f45988` fix(planning): green — content folds reset status to pending

Both domains match the D1-D3 contract as specified, with one shape
difference the spec did not anticipate: `reconcileSyncedSong` returns
`Future<bool>` rather than an `int?` revision, because the song/catalog side
has no separate accept-status write to gate the way planning's
`saveSyncAttemptResult` is gated — the mutation-row delete and the
summary/source snapshot upsert are one combined operation, so there is no
intermediate accept-write revision for an `int?` to report back. `bool` (did
the reconcile apply) is the complete answer, matching the shape planning's
own `clearMutation` already uses. See ADR-030's "D2 (song/catalog)" section.

Evidence: both `song_sync_snapshot_identity_test.dart` (gated-remote-call
race plus the unchanged-case regression) and the `SongCatalogStore
.localRevision` group in `song_catalog_store_test.dart` (monotonic
increment, and that a stale `reconcileSyncedSong` call skips the snapshot
upsert as well as the delete) pass; `song_catalog_migration_test.dart`
confirms a genuine pre-migration (schemaVersion 2) database gains the column
on `onUpgrade` and keeps its pending row intact.

### A defect implementation found that this spec had not anticipated

Implementing D1 on the planning side surfaced a related but distinct gap
this spec's problem statement does not describe: `recordPlanEdit` folding
onto a `planCreate` row (and, it turned out, three sibling fold paths) carried
forward whatever `syncStatus` the existing row already had, via a bare
`copyWith`, instead of resetting it to `pending`. In the ADR-019
durable-marker window — a mutation accepted by the backend but not yet
locally cleared, e.g. a crash between accept and clear (LF-1) — a further
local edit landing on that row kept it labelled `accepted` while it now held
newer, never-sent content. The `localRevision` gate this spec specifies
protects the row from being *deleted* under that condition, but does not
protect it from being *reconciled*: a later sync's own durable-marker
shortcut (`syncStatus == accepted` skips the remote send) would treat that
unsent content as server-confirmed and clear it, silently diverging the
local projection from server truth. This is a different failure mode from
the one D1-D3 close — not an unconditional post-sync write, but a local
write that fails to reset status on an already-concluded row — and it was
recorded as a known follow-up in ADR-030 rather than fixed in the same
change.

It was resolved on the same branch shortly after (`a98c496`/`8f45988`):
every planning-store write that folds new user content onto an existing row
via `copyWith` — `recordPlanEdit` onto a pending `planCreate`,
`recordSessionRename` onto a pending `sessionCreate`, and both reorder-trim
folds (`_removeSessionFromPendingReorder`/
`_removeSessionItemFromPendingReorder`) — now resets `syncStatus` to
`pending` and clears any stale `errorCode`/`errorMessage`, on the reasoning
that new local intent is unsent by definition. `retryMutation` and
`saveSyncAttemptResult` were deliberately left untouched: they compute
`syncStatus` as their entire purpose, not as a side effect of carrying
content forward. The song/catalog side was checked, not assumed, to have no
equivalent gap: `SongSyncStatus` has no two-phase accepted-but-not-cleared
marker, so the window this follow-up closes does not exist there. See
ADR-030's "Fold-Status Follow-Up (resolved)" section for the full account,
and `docs/architecture/repository-review-2026-06-22.md`'s 2026-08-05
song/catalog and fold-status status block.
