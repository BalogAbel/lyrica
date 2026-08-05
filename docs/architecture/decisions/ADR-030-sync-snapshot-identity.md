# ADR-030: Sync Snapshot Identity via Local Revision

- Status: Accepted
- Date: 2026-08-05
- Spec: `docs/specs/2026-08-05-sync-snapshot-identity.md`
- Relates to: ADR-019 (exactly-once planning mutation sync)
- Scope: both halves of the spec — planning (`PlanningMutationSyncController`)
  and song/catalog (`SongMutationSyncController`/`reconcileSyncedSong`) — plus
  the fold-status follow-up flagged when this ADR was first written and
  resolved in a later change on the same branch.

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

The song/catalog half of the same PR #64 finding has the identical shape.
`SongMutationSyncController._runSync` snapshots a pending song, sends it, and
awaits the backend; on success it calls `reconcileSyncedSong`, keyed only by
song identity, which unconditionally both deleted the mutation row and
upserted the reconciled summary/source into the cached snapshot. A local
edit to the same song during that remote wait was destroyed the same way —
confirmed by the same style of test, gated on a `Completer` and driven
against the real `DriftSongCatalogStore`/`DriftSongMutationStore`, not a
hand-rolled fake.

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

`CachedCatalogSongMutations` gains the identical column (schemaVersion
2 → 3), incremented by `DriftSongCatalogStore._saveSongMutation` — the
store's one write path for the mutation table's content, shared by every
local writer of a song mutation row, including the status write
`DriftSongMutationStore.saveSyncAttemptResult` makes through it. Where
planning has several distinct `record*` writers each needing their own
increment, song funnels through this single upsert, so "every local write
bumps it" reduces to one call site.

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

### D2 (song/catalog) — one combined write, gated as a whole

The song/catalog half has no separate "accepted" status write the way
planning's `saveSyncAttemptResult` is one write and `clearMutation` is
another: `SongMutationSyncController._applySuccessfulSync` calls
`DriftSongCatalogStore.reconcileSyncedSong` as a single combined operation
that both deletes the song's mutation row and upserts the reconciled
summary/source into the cached snapshot tables. `reconcileSyncedSong` gained
an optional `expectedRevision` parameter, gated the same way as D2 above —
inside the storage boundary, as the `WHERE localRevision = ?` clause on the
mutation row's own `DELETE` statement, never a preceding `SELECT` compared in
Dart. When that `DELETE` removes zero rows, the **entire** reconcile is
skipped, not merely the delete: the snapshot upsert never runs either,
because the backend response being reconciled describes content a newer
local edit has already superseded, and nothing from that stale response
should land in the cache.

`reconcileSyncedSong` returns `Future<bool>` rather than planning's
`Future<int?>`. Songs have no separate durable-accept write whose new
revision a caller would need reported back — planning's `int?` return
carries the accept-write's own post-write revision forward so `clearMutation`
can gate against *that* value rather than the pre-send snapshot (D2's table
above). Song's reconcile is the accept-write and the clear in one
transaction, so there is no intermediate revision to report; `bool` (did it
apply) is the complete answer, the same shape planning's `clearMutation`
already returns. `SongMutationSyncController._applySuccessfulSync` captures
the song's `localRevision` from the pre-send read — either the sync's
pending-songs snapshot, or `keepMine`'s own read before it sends — and
threads it through as `expectedRevision`.

Unconditional, deliberately, on the song side: `clearSongMutation` (the
discard path — there is no remote round trip for a local discard to race)
and the `pendingDelete` → `deleteSong` branch in `_applySuccessfulSync` (a
converged delete has no "newer content" for a fold to preserve; the row is
gone either way, sent or not). Both mirror the planning-side scope boundary
above: only the write that concludes a remote-accepted content sync is
gated; a write that never claims server confirmation, or that has no
content a stale revision could lose, is not.

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
without any special handling. `reconcileSyncedSong` reports the same outcome
through its `bool` return (`false` = stale) instead of a nullable int, for
the reason given in D2 (song/catalog) above; `SongMutationSyncController`
checks it the same way — no logging, no status change, nothing beyond
moving on.

## Non-Goals

- Changing OCC or `baseVersion` semantics. `localRevision` is local
  bookkeeping and never leaves the device.
- Holding the per-context write queue across the remote call.
- Any change to what the backend authorizes.
- Gating the failure-status writes in `PlanningMutationSyncController._run`
  or `SongMutationSyncController._applySuccessfulSync` by revision (see D2
  and D2 (song/catalog)).
- Riverpod 3, web offline E2E, or any Phase 5 item.

## Fold-Status Follow-Up (resolved)

While implementing D1, a related but distinct gap surfaced: `recordPlanEdit`
folding onto a `planCreate` row copied forward whatever `syncStatus` that
row currently had (`existing.copyWith(...)` never touched `syncStatus` on
that branch), rather than resetting it to `pending`. In the narrow window
where a `planCreate` mutation is `accepted` but not yet cleared — reachable
per ADR-019's own LF-1 scenario (a crash between accept and clear) — an edit
landing in that window kept the row `accepted` with newer, never-sent
content. The `localRevision` gate on `clearMutation` still protected the row
itself from being deleted (a mismatched revision leaves it pending... in
this case, still marked `accepted`, not `pending`), but a *subsequent* sync
run's durable-marker branch (`syncStatus == accepted` skips the remote send
entirely) would then reconcile and clear that row using the unsent edited
content as if the backend had already confirmed it — silently diverging the
local projection from server truth. This is a different mechanism than the
defect D1-D3 close: it is not caused by an unconditional post-sync write; it
is caused by a local write not resetting status on an already-concluded row.
The `localRevision` gate limited the damage but did not fix it — the
reconcile still wrote unsent local content as server-confirmed.

Fixed on the same branch (`a98c496`/`8f45988`), by resetting `syncStatus` to
`pending` and clearing any stale `errorCode`/`errorMessage` in every
`DriftPlanningMutationStore` write that folds new user content onto an
existing row via `copyWith`: `recordPlanEdit` onto a pending `planCreate`,
`recordSessionRename` onto a pending `sessionCreate`, and both reorder-trim
folds, `_removeSessionFromPendingReorder` and
`_removeSessionItemFromPendingReorder`, which drop a deleted sibling's id
out of an in-flight `session_order`/`session_item_order` row. New local
intent is unsent by definition, so a content fold cannot leave the row
labelled with an outcome that content never received.

This does not weaken ADR-019's durable marker: the marker prevents a resend
after a *crash* between acceptance and clear; a deliberate user edit after
acceptance is a new change on top of what the server already has and must
be sent. The line between a content fold and a bookkeeping write:
`saveSyncAttemptResult` and `retryMutation` compute `syncStatus` as their
entire purpose and are untouched by this fix; only writes that carry new
user content through `existing.copyWith(...)` reset it.

The song side has no equivalent defect, verified rather than assumed:
`SongSyncStatus` (`pendingCreate`, `pendingUpdate`, `pendingDelete`,
`synced`, `conflict`) has no two-phase accepted-but-not-cleared marker the
way planning's `PlanningMutationSyncStatus.accepted` does, so the window
this follow-up closes does not exist on the song/catalog side — there is no
status a song mutation row can hold that means "the backend confirmed this,
but the local row has not been cleared yet."

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

Song/catalog half (D2 (song/catalog)), watched failing the same way, against
the real `DriftSongCatalogStore`/`DriftSongMutationStore`: a sync gated on a
`Completer`, with a further local edit to the same song applied while the
gate is held, resulted in the mutation being read back as `null` after the
gate released — `reconcileSyncedSong` had deleted it outright.

- `apps/lyron_app/test/offline/adversarial/song_sync_snapshot_identity_test.dart`
  — the gated-remote-call race for `reconcileSyncedSong` (now passes: the row
  survives, `pendingCreate`, with the newer content, and a second sync sends
  it) and the unchanged-case regression check (no concurrent edit still
  reconciles and clears exactly as before).
- `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
  (`SongCatalogStore.localRevision` group) — the revision advances by
  exactly one on every local write path through `saveSongMutation`,
  including a fold onto a still-pending row and the status write
  `DriftSongMutationStore.saveSyncAttemptResult` makes; a `reconcileSyncedSong`
  call whose `expectedRevision` still matches applies and returns `true`, a
  stale one returns `false` and leaves both the mutation row and the
  snapshot tables untouched (proving the skip covers the snapshot upsert,
  not only the delete).
- `apps/lyron_app/test/offline/adversarial/song_catalog_migration_test.dart`
  — a genuine pre-migration (schemaVersion 2) database, built by hand via raw
  `sqlite3` against the exact `CREATE TABLE` text Drift generated before
  `localRevision` existed (not through `SongCatalogDatabase`, which would
  build the current schema directly via `onCreate` and never exercise
  `onUpgrade`), gains the column on open with a sane starting value (1) and
  keeps its pending row intact.

Fold-status follow-up, watched failing against the current fold logic before
the fix (`a98c496`), fixed by it (`8f45988`):

- `apps/lyron_app/test/offline/planning/planning_mutation_store_test.dart`
  (`PlanningMutationStore content folds reset status (ADR-030 follow-up)`
  group) — each of the four fold paths (`recordPlanEdit` onto an
  accepted-but-uncleared `planCreate`, `recordSessionRename` onto an
  accepted-but-uncleared `sessionCreate`, and both reorder-trim folds against
  an accepted-but-uncleared `session_order`/`session_item_order` row) resets
  `syncStatus` to `pending` and carries the new content; a fifth test proves
  a stale `errorCode`/`errorMessage` left by a prior failed attempt does not
  survive a content fold either.
- `apps/lyron_app/test/offline/adversarial/planning_sync_snapshot_identity_test.dart`
  — a controller-level test: a `recordPlanEdit` folded onto an
  accepted-but-uncleared `planCreate` is confirmed actually sent on the next
  sync (`remote.syncedDescriptions` carries the edited content), proving the
  durable-marker shortcut in `PlanningMutationSyncController._run` no longer
  skips it.
