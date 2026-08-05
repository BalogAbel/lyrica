# In-Flight Create Cancellation

> Status: Draft

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
