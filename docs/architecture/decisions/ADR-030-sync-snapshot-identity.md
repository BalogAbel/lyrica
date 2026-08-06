# ADR-030: Sync Snapshot Identity via Local Revision

- Status: Accepted
- Date: 2026-08-05
- Spec: `docs/specs/2026-08-05-sync-snapshot-identity.md`,
  `docs/specs/2026-08-06-in-flight-create-cancellation.md`
- Relates to: ADR-019 (exactly-once planning mutation sync)
- Scope: both halves of the spec — planning (`PlanningMutationSyncController`)
  and song/catalog (`SongMutationSyncController`/`reconcileSyncedSong`) — plus
  the fold-status follow-up flagged when this ADR was first written and
  resolved in a later change on the same branch, and the in-flight create
  cancellation follow-up (the `sending` marker, the `cancelling` tombstone,
  the accepted-window case, and D4) resolved in a later change still.

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

## In-Flight Create Cancellation Follow-Up (resolved)

Spec: `docs/specs/2026-08-06-in-flight-create-cancellation.md`.

D1-D3's `localRevision` gate protects an edit against a concurrent sync by
assuming that newer local intent arriving during a remote round trip always
leaves a **higher-revision pending row**. That holds for an edit. It does not
hold for a delete of a still-pending create: ADR-028 D10 deliberately admits
physically collapsing a still-pending create's row on delete, which *removes*
the row instead of bumping its revision. If the create's own remote send was
in flight at the exact moment of that delete, the collapse destroyed the only
local record of the delete's intent before the create's outcome was known --
if the create then succeeded, the object existed on the server and nothing
would ever delete it.

### The `sending` marker

The sync now writes a durable `sending` marker to a candidate's mutation row
immediately **before** the remote call, the mirror of the `accepted` marker
D1-D3 above already write immediately **after** it. `sending` reuses the
existing free-text `syncStatus` column -- the same choice this ADR made for
`accepted` -- so no schema migration is needed. The write is gated on the
pre-send `localRevision`, exactly like every other conditional write D2
established: a local edit or delete that already landed on the row before the
send even started leaves it unmarked and the send does not proceed.

**Why this does not weaken exactly-once.** A record left `sending` by a crash
carries the identical uncertainty the `accepted` marker exists to bound: it
may or may not have reached the backend before the crash. The two markers
resolve that uncertainty in opposite, and both correct, directions --
`accepted` means the backend confirmed receipt, so a resend is skipped (this
ADR's D2/D3 decision); `sending` means the backend's answer is unknown, so the
record is treated as pending and resent on the next pass
(`PlanningMutationSyncController._run`'s candidate filter now includes
`sending` alongside `pending`/`accepted`, and the song side's
`readPendingSongs` does the same). Resending on unresolved crash uncertainty
is the direction this ADR already accepts for a crash before acceptance;
`sending` narrows the window in which that ambiguity is invisible (a durable
in-flight signal now exists where none did before) rather than widening any
window this ADR closed.

### The cancellation tombstone and its resolution

Deleting a `sending` `sessionCreate`/`sessionItemCreateSong` (planning) or
`pendingCreate` song no longer physically collapses the row (ADR-028 D10's
collapse still applies, unchanged, to every other state). It rewrites the row
to a `cancelling` tombstone at a bumped revision instead -- the user's delete
intent, held until the in-flight create's fate is known. `cancelling` is
excluded from every actionable/merged read (`readActionableMutations`, the
song catalog's merged visible-row computation) and from the sync candidate
filter, so the tombstone disappears from the UI immediately, before its
create's outcome is even known, and is never itself sent to the backend.

`DriftPlanningMutationStore.resolveCancelledCreate` /
`DriftSongCatalogStore.resolveCancelledSongCreate` resolve the tombstone in
one atomic read-check-write once the in-flight create's remote call
concludes, called from the sync controller on both outcomes:

- **create succeeded** -- the object now exists on the server, so the
  tombstone becomes a real pending delete (`kind` flips to the matching
  `*Delete` kind; `baseVersion` is rebased on the backend-assigned version
  returned in the create's own RPC response), and the very next sync sends
  it. The already-accepted remote create is never undone; the delete is
  expressed as a subsequent operation, which is what the user actually asked
  for.
- **create failed** -- the object never existed remotely, so the tombstone is
  discarded outright, with no further backend call -- exactly the physical
  collapse a plain, not-in-flight delete would have performed.

Both controllers resolve the tombstone **before** the unconditional
failure-status write that follows a failed remote call. Wiring this found an
ordering bug: that failure-status write is deliberately ungated by revision
(it never claims backend acceptance, so it stays out of D2's
snapshot-identity scope), and an ungated write landing after tombstone
resolution would clobber the `cancelling` status with a failure status,
stranding the tombstone forever (`resolveCancelledCreate`/
`resolveCancelledSongCreate` only act on a row still marked `cancelling`).
Resolving the tombstone first closes that trap.

A session's (or session item's) pending item and item-order mutations are
still dropped in every branch that deletes the parent -- tombstone, physical
collapse, or the accepted-window real delete below -- because the session is
going away one way or another and they have no reachable destination: sent to
a session that doesn't exist yet, or sent to one about to be deleted.

### The accepted-but-uncleared window (planning only)

The same defect exists one state over, and closing it needed no tombstone.
`accepted` is this ADR's own durable-marker window (D2/D3 above; the
crash-between-accept-and-clear scenario the Fold-Status Follow-Up below also
documents): the backend has *already confirmed* the create, only the local
clear has not run yet. Unlike `sending`, there is no live remote call to race
-- the create's fate is already known -- so `recordSessionDelete`/
`recordSessionItemDelete` convert an `accepted` row straight into a real
pending delete, with no tombstone and no `resolveCancelledCreate` step.

`baseVersion` for that delete uses `existing.baseVersion ?? draft.baseVersion`
-- the same fallback every other delete path in `DriftPlanningMutationStore`
already uses. This is a deliberate choice, not an oversight left for later:
`existing.baseVersion` was captured for the *create's* own OCC check and is
never updated by the accept write (`saveSyncAttemptResult` only ever touches
`syncStatus`/`errorCode`/`errorMessage`/`localRevision`), so it is not
guaranteed to carry the version the backend assigned as a side effect of
accepting the create -- confirmed against `create_song_session_item`, which
bumps the session's version and returns the new value only in the RPC
response, never persisted back onto the row. Rather than invent that number,
the code reuses the pre-accept value and lets the backend's own version guard
(`delete_empty_session`/`delete_session_item`) reject a wrong precondition
into a visible, recoverable `conflict` instead of silently deleting against
the wrong version or guessing one. That is the honest fail-safe choice this
decision makes deliberately.

This window does not exist on the song side -- verified, not assumed, the
same way the Fold-Status Follow-Up below verified song has no
`accepted`-but-uncleared status at all: `reconcileSyncedSong` is one atomic
delete-plus-upsert, so "backend confirmed but not locally cleared" is not a
representable state for a song mutation row. Song's tombstone path above is
therefore the complete fix on that side, with no second branch.

### A vanished record is not a programming error (D4)

`DriftPlanningMutationStore.saveSyncAttemptResult`/`retryMutation` and
`DriftSongMutationStore.saveSyncAttemptResult` used to throw `StateError`
when the row a sync attempt was concluding had disappeared. With the
tombstone above in place that row is normally still there, but a genuinely
vanished record -- collapsed by an ordinary, not-in-flight delete racing
something else -- is an ordinary concurrent-world outcome, not a defect.
Because `Error` is rethrown untouched by the storage-recovery boundary (by
design: `Error` signals a programming defect the boundary should not paper
over), a thrown `StateError` here escaped
`PlanningMutationSyncController._run`/`SongMutationSyncController._runSync`
uncaught and **killed the entire sync pass**, discarding every unrelated
mutation or song queued behind the vanished one.

These now report "did not apply" in the vocabulary D3 above already
established for a stale revision: `saveSyncAttemptResult` returns
`null`/`false` instead of throwing; `retryMutation` returns `Future<bool>`
(`true` = reset, `false` = row gone) instead of `Future<void>`. The existing
`if (newRevision == null) continue;` in `PlanningMutationSyncController._run`
(D3) covers this case for free; the song controller's failure branch already
discarded the return value, so it needed no logic change either, only updated
comments. No new user-facing signal is raised: the row is already gone from
every list the sync overview reads, exactly the state a user-initiated delete
asked for.

**Deliberately out of scope.** `SongLibraryService.deleteSong`/`updateSong`
and `SongMutationSyncController._requireSong` (the single-record lookup
behind `keepMine`/discard-style calls) throw the same-looking `StateError`
for a target absent from local storage entirely, and keep doing so. Those are
single-record, user-initiated calls with no sync loop and no queued sibling
work behind them to protect -- converting them would not close any
silent-failure window the way D4 closes one for the two sync controllers.
Pinned by regression tests in `song_library_service_test.dart` so a future
change does not silently widen D4's scope to cover them.

### Domain shape difference: why song's `sending` marker is create-only

Planning's `sending` marker is written before every mutation kind's send.
Song's `markSongCreateSending` is deliberately scoped to `pendingCreate` rows
only: the song domain has no separate `kind` field the way planning does --
the sync status *is* the operation type -- and only a create can be raced by
a physical row collapse (`SongLibraryService.deleteSong`'s `pendingCreate`
branch). A delete of an already-synced song racing its own in-flight
`pendingUpdate`/`pendingDelete` send is already race-safe via
`reconcileSyncedSong`'s pre-existing `localRevision` gate (D2 (song/catalog)
above): those kinds never physically collapse the row, so an unconditional
overwrite plus that gate is sufficient, and no in-flight marker is needed for
them.

### Known limitation: `SongLibraryService.updateSong` does not fold onto `sending`

`updateSong`'s status ternary
(`existing.syncStatus == SongSyncStatus.pendingCreate ? pendingCreate :
pendingUpdate`) does not treat `sending` as create-like the way it treats
`pendingCreate`. An edit landing on a song during its create's `sending`
window becomes `pendingUpdate` rather than folding into the create. This is
traced, not merely suspected, and is **not** data loss: `resolveCancelledSongCreate`
no-ops on a row that is not a tombstone, so the edited content survives
untouched and syncs on the next round. The cost is purely an extra
create-then-update round trip, where planning's content-fold handling (the
Fold-Status Follow-Up below) would have carried the edited content in a
single create. Deliberately left out of
`docs/specs/2026-08-06-in-flight-create-cancellation.md`'s scope; recorded
here so it is not mistaken for an oversight later.

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

In-flight create cancellation (`docs/specs/2026-08-06-in-flight-create-cancellation.md`),
watched failing before each fix, against the real Drift stores throughout (never a
hand-rolled fake, for the same reason as the suites above):

- `apps/lyron_app/test/offline/adversarial/planning_in_flight_create_cancellation_test.dart`
  — session and session-item variants of: deleting a `sending` create survives as a
  `cancelling` tombstone and, once the gated remote call is released with the create
  **succeeding**, converts to a real pending delete that a following sync actually sends
  (watched failing pre-fix with the row lost entirely — expected a pending delete, got
  `null`); the same setup with the create **failing** instead resolves the tombstone
  locally with no delete ever sent; a no-regression check that deleting a pending create
  with no sync in flight still physically collapses, with no tombstone and no backend
  call (ADR-028 D10 unchanged); the accepted-but-uncleared window converts straight to a
  real pending delete with no tombstone, and a following sync sends it; a session's
  pending item and item-order mutations are dropped under both the `sending`-tombstone
  and the accepted-window branches; and crash recovery — a record left `sending` is
  treated as pending on a fresh pass and resent.
- `apps/lyron_app/test/offline/adversarial/song_in_flight_create_cancellation_test.dart`
  — the song/catalog mirror: deleting a `pendingCreate` song while its create is in
  flight survives as a `cancelling` tombstone and converts to a real `pendingDelete` once
  the create succeeds; the create-fails case resolves the tombstone locally with no
  delete sent; a no-regression check that deleting a `pendingCreate` song with no sync in
  flight still collapses exactly as before; and crash recovery for a `sending` song row.
  Song has no accepted-but-uncleared case to cover (see the ADR text above).
- `apps/lyron_app/test/offline/adversarial/planning_vanished_record_sync_test.dart` and
  `apps/lyron_app/test/offline/adversarial/song_vanished_record_sync_test.dart` — D4:
  several pending records/songs queued, the first one's remote call gated, the row
  deleted directly through the store mid-flight (simulating the collapse), then the gate
  released. Watched failing pre-fix with exactly the predicted `StateError` (`Bad state:
  Planning mutation record not found: plan-1` /
  `Bad state: Song mutation record not found: song-1`) escaping the sync loop; passing
  after the fix, with the records/songs queued behind the vanished one still synced.
- `apps/lyron_app/test/offline/planning/planning_mutation_store_test.dart` and
  `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart` — store-level
  D4 coverage: a `saveSyncAttemptResult`/`retryMutation` call against a row that does not
  exist returns `null`/`false` rather than throwing, and the existing-record path behaves
  exactly as before the signature change.
- `apps/lyron_app/test/application/song_library/song_library_service_test.dart` — pins
  the deliberate D4 scope boundary: `updateSong`/`deleteSong` against a song absent from
  local storage entirely still throw `StateError`, so a future change does not silently
  widen D4 to cover these single-record, user-initiated calls.
