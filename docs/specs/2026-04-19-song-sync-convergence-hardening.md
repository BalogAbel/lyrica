# Specification: Song Sync Convergence Hardening

> Status: Proposed

> This spec closes the high-priority deferred correctness gap recorded in [docs/deferred/2026-04-08-offline-song-crud.md](docs/deferred/2026-04-08-offline-song-crud.md). It extends the shipped song CRUD slice in [docs/specs/2026-04-05-song-crud.md](docs/specs/2026-04-05-song-crud.md) and preserves the backend-owned write boundary established by [docs/architecture/decisions/ADR-013-song-write-sync-boundary.md](docs/architecture/decisions/ADR-013-song-write-sync-boundary.md).

## Goal

Close the remaining song-mutation convergence gap by defining deterministic behavior when the server-side song has already been deleted while a local song mutation still exists, and by preserving understandable planning and reader references instead of degrading to a bare not-found failure.

## Problem

The current local-first song write slice already handles:

- offline create, update, and delete
- explicit conflict handling for stale `base_version`
- explicit keep/discard resolution for version conflicts
- backend-owned authorization and delete dependency checks

One important correctness gap remains open:

- the backend write contract can return `song_not_found` for update or delete
- the client does not classify that outcome into a durable convergence rule
- `discard mine` currently assumes the latest server row can always be fetched
- reader flows can still degrade to a plain not-found failure when a planning reference outlives the canonical song row

That gap is high priority because it directly affects the local-first truthfulness of the song write model and any future planning or workflow features that depend on stable song references.

## Scope

- Define explicit convergence behavior for `song_not_found` during song mutation sync.
- Distinguish update-sourced remote deletion from delete-sourced remote deletion.
- Define `keep mine` and `discard mine` semantics when the server row is already gone.
- Keep backend authorization and canonical acceptance backend-owned.
- Preserve human-readable planning and session-scoped reader references when a referenced song no longer exists in the canonical song catalog.
- Add backend-backed integration coverage for the new convergence rules.

## Non-Goals

- No general-purpose multi-field merge UI.
- No real-time collaborative editing model.
- No broad song editor redesign.
- No change to normal direct song-list browsing rules for deleted songs.
- No attempt to preserve deleted songs as ordinary active catalog rows.

## Product Slice Summary

This slice proves the following claim:

1. a signed-in user has a local pending song mutation or conflict
2. the canonical server song disappears before that local intent converges
3. the client classifies that remote disappearance explicitly instead of falling back to generic unknown or not-found behavior
4. the user can still converge deterministically
5. planning and session-scoped reader references remain understandable to humans even when the canonical song row is gone

## Current Architectural Context

This slice must preserve the repository boundaries already established in the repository:

- `sync_status` remains the local mutation-queue state, not a general song-read availability model
- backend authorization remains enforced in Supabase/Postgres rather than in Flutter
- explicit overwrite-style user choices remain separate backend mutations rather than silent stale-write retries
- normal song-list and slug-based catalog reads continue to hide locally pending deletes and remotely deleted songs
- planning reads remain projection-backed and already preserve song title data on session items independently of the active song catalog

This slice extends those rules. It must not replace them with a second song-sync architecture.

## Convergence Model

### Mutation Queue State

The existing `sync_status` values remain:

- `pending_create`
- `pending_update`
- `pending_delete`
- `synced`
- `conflict`

This slice does not introduce a new queue state for remote deletion. Instead, it introduces an explicit remote-deletion convergence classification so the existing queue and conflict model can behave deterministically.

That classification must live in persisted mutation metadata rather than only in transient controller flow. At minimum, the persisted mutation record must retain:

- `sync_status = conflict` while explicit user recovery is still required
- original intent through existing conflict-source metadata
- explicit persisted remote-deletion classification through mutation error metadata so restart, retry, and recovery UI keep the same semantics

### Remote-Deletion Classification

When the backend reports `song_not_found` for a mutation that expected an existing canonical song row, the client must classify that outcome as **remote deletion** rather than as a generic unknown error.

This classification applies only to local intents that depended on an already existing canonical song row:

- ordinary `pending_update`
- ordinary `pending_delete`
- `conflict` rows whose original intent came from `pending_update` or `pending_delete`

It does not apply to `pending_create`.

### Update-Sourced Remote Deletion

If the local intent is an update and the server song is already gone:

- the local row must move into an explicit conflict-like recovery path with durable remote-deletion classification
- the user must be able to choose `keep mine` or `discard mine`
- the client must not silently drop the local edit

#### `keep mine` for update-sourced remote deletion

`keep mine` means:

- recreate the canonical song on the backend using the same `song.id`
- use the local title, chord source, and current local slug as the requested canonical state
- require the same backend-owned `canEditSongs` authorization as ordinary writes
- allow the backend to canonicalize the recreated slug if another row claimed the requested local slug after the original song disappeared
- return the canonical recreated server row
- reconcile the local row back to `synced`

This slice intentionally chooses same-id recreation instead of introducing a new recovery aggregate. That keeps convergence simple and preserves the identity already referenced by planning data.

#### `discard mine` for update-sourced remote deletion

`discard mine` means:

- accept the remote deletion as canonical truth
- clear the local song mutation and remove the local song row from the active song catalog
- do not attempt to fetch a latest canonical song row that no longer exists

### Delete-Sourced Remote Deletion

If the local intent is a delete and the server song is already gone:

- the local and remote states have already converged on deletion
- ordinary sync must treat that outcome as accepted convergence
- the client must clear the local pending delete instead of surfacing a new conflict

If a previously conflicting delete later resolves into remote disappearance before the user acts, both explicit user choices converge to the same accepted deletion outcome:

- `keep mine` converges by accepting the deletion
- `discard mine` also converges by accepting the deletion because there is no canonical song row left to restore

The implementation should auto-resolve that state when detected rather than forcing the user through two choices that now produce the same outcome.

### Error Persistence

Authorization, dependency, connectivity, and unknown failures must remain durable local state even inside the new remote-deletion paths.

Examples:

- recreating a remotely deleted song can still fail with authorization loss
- recreating a remotely deleted song can still fail because the song became referenced in an invalid way for a later delete path
- discard resolution can still fail for connectivity or local persistence reasons

Those failures must remain inspectable and retryable through the existing explicit recovery surfaces.

## Planning And Reader Reference Behavior

The song catalog and planning projection serve different purposes. This slice must keep them separated.

### Normal Song Catalog Behavior

- remotely deleted songs must not remain visible as ordinary active songs in the normal catalog list
- direct song lookup by catalog slug may continue to resolve as not found once the canonical song is gone
- this slice does not require deleted songs to remain routable as ordinary catalog entries

### Planning Projection Behavior

Planning session items already preserve song identity plus human-readable title data. That data must remain the durable reference source when the canonical song row disappears.

Required behavior:

- plan detail must continue to render the preserved planning title for session items whose canonical song row is gone
- the planning surface must not collapse those items to a raw missing-id or generic not-found placeholder
- if the UI adds explicit deleted-state styling in this slice, it must remain informational rather than pretending the song is still editable

Title precedence must remain deterministic:

- planning-owned preserved title is source of truth for planning and tombstone copy
- discarded local draft title must not replace preserved planning title after `discard mine`
- recreated canonical title may appear later through normal planning refresh, but until then the preserved planning title remains displayed

### Session-Scoped Reader Behavior

If a session-scoped reader route still points at a session item whose canonical song row is gone:

- route validation must continue to use the planning/session-item context
- if update-sourced remote deletion is still unresolved, the reader must show a read-only deleted-song conflict state using preserved planning reference data rather than local draft song content
- after accepted deletion convergence, the reader must show a read-only deleted-song or tombstone-style state using preserved planning reference data
- that state must preserve at least the last known title
- that state must not degrade to an unhandled `SongNotFoundException`

This slice does not require rendering the deleted song body, because the canonical ChordPro source no longer exists after accepted remote deletion.

Minimum tombstone contract:

- visible preserved title
- visible deleted or unavailable label explaining canonical song was removed
- no bare `songId`
- no generic `Song not found` as primary user-facing copy
- no edit affordance from tombstone state

## Authorization And Backend Contract Rules

- all recreate, overwrite, update, and delete acceptance decisions remain backend-enforced
- Flutter may expose recovery actions, but it is not the source of truth for canonical acceptance
- same-id recreation for update-sourced remote deletion must be a deliberate backend contract, not a client-side table write shortcut
- backend delete-dependency checks remain in force where they already apply

## Testing Requirements

- Unit tests must cover remote-deletion classification for update-sourced and delete-sourced local mutations.
- Application tests must cover `keep mine` same-id recreation, delete-sourced auto-convergence, and discard behavior when no canonical row remains to fetch.
- Widget tests must cover human-readable reader and planning behavior for deleted song references.
- Integration tests must cover backend-backed end-to-end convergence for remote delete versus local update and remote delete versus local delete.
- Backend verification must prove same-id recreation authorization, canonical recreation output, and accepted delete convergence when the song is already gone.

## Documentation Impact

Implementation of this slice must update:

- `docs/domain/domain-model.md` for song remote-deletion convergence and reference-preservation rules
- `docs/architecture/architecture.md` for explicit song-sync convergence behavior and reader/reference boundaries
- `docs/architecture/decisions/ADR-013-song-write-sync-boundary.md` or a follow-up ADR if the remote-deletion recovery contract is treated as a durable architectural decision distinct from the original CRUD slice
- `docs/testing/testing-strategy.md` for standing remote-delete convergence expectations
- `docs/deferred/2026-04-08-offline-song-crud.md` to close or supersede the deferred gap in the same implementation change
