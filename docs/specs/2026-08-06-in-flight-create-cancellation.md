# In-Flight Create Cancellation

> Status: Implemented

## Implementation

Commits, in landed order:

- `ac0e237` test(sync): red -- a vanished record aborts the whole sync pass
- `7e393da` fix(sync): green -- report vanished record as did-not-apply (D4)
- `2c33864` test(planning): red -- in-flight create delete loses intent (D1/D2/D3)
- `0fbf43d` fix(planning): green -- keep in-flight create deletes as tombstones (D1/D2/D3)
- `28afaca` test(planning): pin item/item-order cleanup for cancelled in-flight creates
- `5798129` test(planning): red -- accepted-but-uncleared delete still collapses
- `7860978` fix(planning): green -- accepted-but-uncleared delete becomes real pending delete
- `fe59e74` test(catalog): red -- in-flight create delete loses intent (D1/D2/D3)
- `baf3c23` fix(catalog): green -- keep in-flight create deletes as tombstones (D1/D2/D3)

D4 landed first because it removes the one failure mode (an unrelated
`StateError` killing the whole sync pass) that would otherwise have made the
D1-D3 work harder to isolate and test in each domain. Planning's D1-D3 landed
before the song/catalog mirror; the song-side store layer (`markSongCreateSending`/
`resolveCancelledSongCreate` on `DriftSongCatalogStore`) was implemented
alongside planning's but its two call sites (`SongLibraryService.deleteSong`,
`SongMutationSyncController._runSync`) were wired in the final commit.

### What the spec did not anticipate

**The ordering trap.** The spec's D3 describes resolving a tombstone once the
in-flight create's remote call concludes, but does not say *when* relative to
the controller's other post-call writes. Both controllers already had an
unconditional failure-status write on the error path (deliberately ungated by
revision, since it never claims backend acceptance — out of D2's
snapshot-identity scope). Writing that status *after* attempting tombstone
resolution is fine; writing it *before* is not: an ungated write landing
first would overwrite `cancelling` with a failure status, and
`resolveCancelledCreate`/`resolveCancelledSongCreate` only act on a row still
marked `cancelling` — so the tombstone would be permanently stranded, invisible
(`cancelling` is excluded from every merged read) and never converted or
discarded. Both controllers resolve the tombstone first, specifically to avoid
this. Caught during implementation by reasoning through call order before
writing the code, not by a failing test that first demonstrated the strand —
worth flagging precisely because a future refactor that reorders these two
writes would reintroduce it silently, with no existing test positioned to
catch a reorder rather than a missing tombstone.

**The accepted-but-uncleared window.** The spec's Decisions and Testing
sections describe only the `sending`/in-flight case (D1-D3) and the ordinary
not-in-flight collapse (Testing #5). They do not name the third state a
still-pending create's mutation row can be in when a delete arrives:
`accepted` — ADR-019's own durable-marker window, where the backend has
already confirmed the create but the local clear has not run yet (the exact
crash-between-accept-and-clear scenario ADR-030's fold-status follow-up
documents, here reached without a crash — the accept write and the clear are
simply two separate writes with a delete able to land between them). This
state has the identical failure shape as D1-D3 (a physical collapse would
still lose the delete intent for an object the backend already has) but a
simpler fix: since the create's fate is already known, there is no live
remote call to race, so the row converts straight to a real pending delete
with no tombstone and no `resolveCancelledCreate` step. Found while
implementing D1-D3 for planning (`5798129`/`7860978`), before the song/catalog
mirror was written — confirmed absent on the song side, not merely assumed
absent, because `reconcileSyncedSong` has no separate accept-then-clear write
for a delete to land between.

**The `updateSong` fold gap.** Tracing through the song/catalog mirror
surfaced that `SongLibraryService.updateSong`'s status ternary treats only
`pendingCreate` as create-like when deciding whether an edit should stay
folded into the create; a `sending` row (D1's marker) falls through to
`pendingUpdate` instead. This is not data loss — `resolveCancelledSongCreate`
no-ops on a non-tombstone row, so the edited content survives and syncs on
the next round — but it costs an extra create-then-update round trip where
planning's content-fold handling would have carried the edit in one create.
Left as a known limitation, out of this spec's scope; recorded in ADR-030's
in-flight create cancellation follow-up rather than fixed here.

## Goal

Close the remaining PR #64 variant: deleting an item **while the create that
introduced it is in flight** loses the delete intent entirely, and on the
planning side takes the whole sync pass down with it.

## Problem

ADR-030's `localRevision` gate assumes that newer intent arriving during a remote
round trip leaves a **pending row at a higher revision**. That holds for edits.
It does not hold for deletes, because deleting a still-pending create physically
removes the row — that is the collapse ADR-028 D10 deliberately admits.

The sequence:

1. the sync sends a pending create and awaits the backend;
2. the user deletes the item while that call is in flight;
3. the planning collapse path, or the song `pendingCreate` branch in
   `SongLibraryService.deleteSong`, physically removes the mutation row;
4. the backend accepts the create;
5. planning's `saveSyncAttemptResult` finds no row and throws `StateError`; the
   song side's revision CAS returns `false` and skips the reconcile;
6. the object now exists on the server, and **the user's delete intent has no
   local trace**. Nothing will ever delete it.

Two distinct harms, and the second is not in the finding:

- **The delete intent is lost.** The user deleted something; the server keeps it.
- **The planning `StateError` aborts the entire sync pass.** The recovery
  boundary rethrows `Error` untouched, by design — `Error` means a programming
  defect, not storage pressure. So this escapes `_run` and kills the loop,
  discarding the sync of every unrelated mutation queued behind it.

This is not ADR-030's accepted `pendingDelete` → `deleteSong` exception. That one
concerns a delete of something the server already has. Here a **local cancel of a
create races the create's own in-flight send**.

## Decisions

### D1 — The sync durably marks a record before it sends

The sync writes a `sending` marker to the record **before** the remote call, as
the mirror of the `accepted` marker ADR-019 already writes immediately after it.
Between those two writes, the record is known to be in flight.

The marker carries the `localRevision` that was sent, so it identifies the exact
content in flight, consistent with ADR-030.

**Crash semantics, and why this does not weaken ADR-019.** A record left
`sending` by a crash may or may not have reached the backend — exactly the
uncertainty the `accepted` marker exists to bound. On restart a `sending` record
is treated as pending and resent, which is the direction ADR-019 already accepts
for a crash before acceptance. The marker narrows a window; it does not widen
one.

### D2 — Deleting an in-flight create leaves a cancellation tombstone

Deleting a pending create behaves differently depending on the marker:

| record state | delete behaviour |
|---|---|
| pending, not in flight | physical collapse, exactly as today (ADR-028 D10) |
| `sending` | the row is **kept** as a cancellation intent, at a bumped revision |

The tombstone is the user's delete intent, held until the fate of the already-sent
create is known. Nothing is lost, and no backend round trip is spent on a purely
local create-then-delete that never left the device — which is the common offline
case and must stay cheap.

### D3 — The in-flight create's outcome decides what the tombstone becomes

When the sync's remote call returns and finds the revision has moved to a
cancellation tombstone:

- **the create succeeded** → the object exists on the server, so the tombstone
  becomes a real pending delete and the next sync sends it;
- **the create failed** → the object never existed remotely, so the tombstone
  resolves locally with no backend call, exactly as a plain collapse would have.

The already-completed remote create is never undone by the local side; the delete
is expressed as a subsequent operation, which is what the user actually asked
for.

### D4 — A missing record is not a programming error

`saveSyncAttemptResult` and `retryMutation` currently throw `StateError` when the
target row is gone. Under D2 the row is normally still there, but "the row I was
told about is no longer present" is an ordinary concurrent-world outcome, not a
defect in the code. Throwing `Error` for it means the recovery boundary correctly
refuses to handle it and the whole sync pass dies.

These become a non-throwing "did not apply" result, in the shape ADR-030 already
established for the conditional writes. A vanished record leaves the sync pass
free to continue with the records behind it.

## Non-Goals

- Changing what the backend authorises.
- Undoing an accepted remote write.
- Reworking ADR-028's collapse admission for the non-in-flight case, which stays
  as it is.
- Riverpod 3, web offline E2E, or any Phase 5 item.

## Testing

Gated-remote tests, in both domains, for each shape the finding names:

1. **Planning session:** send a pending `sessionCreate`, gate the remote call,
   delete the session while it is in flight, release the call with the create
   **succeeding**. The delete intent survives as a pending delete and the next
   sync sends it. **Must fail today**, and the observed failure should be the
   lost intent, not only the `StateError`.
2. **Planning session item:** the same, for `sessionItemCreateSong`.
3. **Song:** the same, for a `pendingCreate` song.
4. **The create fails instead.** Same setup, remote create rejected: the
   tombstone resolves locally with no delete sent.
5. **No regression on the ordinary collapse.** Deleting a pending create with no
   sync in flight still collapses physically, with no tombstone and no backend
   call — ADR-028 D10 unchanged.
6. **A vanished record does not kill the sync pass.** With one record removed
   mid-flight, the remaining queued mutations still sync. This pins D4
   independently of the tombstone.
7. **Crash recovery.** A record left `sending` is treated as pending on restart
   and resent.

## Documentation

- Amend ADR-030 with the `sending` marker, the tombstone, and D4; state plainly
  why the marker does not weaken ADR-019's exactly-once reasoning.
- `docs/architecture/architecture.md` Offline Strategy and
  `docs/testing/testing-strategy.md`.
- `docs/architecture/repository-review-2026-06-22.md`: extend the PR #64
  remediation status block.
