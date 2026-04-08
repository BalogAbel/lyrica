# Offline-First Song CRUD Deferred Work

Originating slice:
- `docs/specs/2026-04-05-song-crud.md`
- `docs/plans/2026-04-08-offline-first-song-crud.md`

## Priority

High. This deferred work should be closed in the next slice that touches song mutation sync or conflict resolution.

## Deferred Item

### Handle songs that disappear on the server while a local mutation still exists

The current song mutation sync flow does not model the case where the server-side song is deleted after the client created a local pending update, pending delete, or conflict row.

Today:

- ordinary update/delete can receive `song_not_found` from the backend write contract
- the Supabase mutation repository does not map that outcome into an explicit domain-level sync state
- `discard mine` cannot cleanly converge when the server no longer has a row to fetch

This leaves an avoidable sync-consistency gap. The client can keep a local record whose server counterpart no longer exists, without a clean discard or convergence path.

## Expected Follow-up Scope

- Define the domain behavior for "server deleted the song" during sync.
- Decide whether this becomes a dedicated sync error state, a conflict subtype, or a convergence path that removes the local row.
- Define explicit `discard mine` semantics when the server row is already gone.
- Add application tests and backend-backed integration coverage for this case.

## Planning Note

Any future slice that changes song mutation sync, conflict handling, overwrite/discard flows, or delete semantics must review this deferred item first and treat it as priority work rather than optional cleanup.
