# ADR-013: Song Write Sync Boundary

## Status

Accepted

## Context

The repository already established backend-owned authorization through Supabase Auth, RLS, and capability helpers, but the planned song CRUD slice needed a durable write-side decision record before implementation.

That slice introduces local-first song creation, update, and deletion, conflict handling, and a sync path that writes back to the backend. Without an explicit architectural record, the implementation could drift into Flutter-owned authorization, ambiguous overwrite behavior, or inconsistent local routing behavior for offline-created slugs and pending deletions.

## Decision

Use a backend-authorized song write sync boundary for the planned song CRUD slice.

For that slice:

- song create, update, delete, and explicit conflict-overwrite actions require backend-owned `canEditSongs`
- the Flutter client may expose edit affordances, but it is never the source of truth for write authorization
- ordinary update and delete mutations use optimistic concurrency by comparing `base_version` with the current server `version`
- stale ordinary writes fail as explicit conflicts rather than silently overwriting the server state
- "keep mine" conflict resolution uses a second explicit overwrite mutation path instead of retrying the stale ordinary write
- if a song disappears on the server while a local update still exists, the client persists explicit remote-deletion metadata and keeps the row in conflict recovery instead of silently dropping the local edit
- update-sourced remote deletion resolves through a backend-owned same-id recreation path when the user chooses "keep mine"
- update-sourced remote deletion resolves through accepted deletion when the user chooses "discard mine", without fetching a non-existent canonical row
- delete-sourced remote deletion auto-converges as accepted deletion because both sides already agree on the outcome
- song deletion is rejected while any `session_item` still references the song
- accepted song deletion cascades to song-owned attachments
- `pending_delete` rows are hidden from normal local reads and route resolution immediately, while remaining available in dedicated sync/conflict recovery surfaces
- offline-created slugs must be unique within the active local organization before sync succeeds, and the client must reconcile to the canonical server slug returned after sync
- planning/session-scoped reader routes keep using planning-owned preserved song titles when the canonical song row is gone, and show a tombstone-style deleted-song surface rather than a generic song-not-found placeholder
- song sync and discard ownership is keyed by both authenticated user and organization because a sync snapshots every pending song in that context; sync and discard are mutually exclusive within that context, while different contexts remain independent
- concurrent sync requests for the same user-and-organization context coalesce into one owned run; if sync is requested while discard owns the context, all such requests coalesce behind the same discard completion and only then take their pending-song snapshot
- a per-row discard requested while sync owns the context is rejected immediately with the typed `SongDiscardResult.syncInProgress` outcome and makes no local change; this expected contention path is not represented by a generic exception
- discard acquires context ownership before reading the mutation record or changing local storage, and holds ownership through its best-effort refresh; a waiting sync therefore cannot snapshot the discarded mutation between the local clear/delete and lease release
- unified **Discard All** acquires the song-context discard lease before starting either the song or planning domain; if sync already owns that context, it returns typed `UnifiedDiscardResult.syncInProgress` before either domain changes. Once admitted, song and planning discards remain best-effort concurrent domain operations, not a cross-database transaction and not a promise of rollback across domains
- discard success is the completed local clear or delete. It performs no compensating remote write and does not depend on a post-discard refresh succeeding; refresh is freshness-only and cannot undo the local outcome
- context-wide ownership covers sync and discard only. "Keep mine" (the explicit overwrite path, above) is not admitted into the same context lease: it can run concurrently with an owned sync or discard on the same user-and-organization context. This is a pre-existing gap, not a guarantee the client makes; closing it is out of scope for the discard-ownership work that introduced the lease

## Consequences

- Authorization remains backend-enforced even when the app is offline-first.
- Conflict resolution stays explicit and auditable instead of degenerating into last-write-wins retries.
- Remote deletion converges deterministically without introducing a second song-sync architecture or a Flutter-owned acceptance shortcut.
- Song deletion remains safe against stale local knowledge about dependent planning data.
- Local routing and lookup behavior stays deterministic even when multiple songs are created offline with similar titles.
- Same-context sync and discard cannot race a pending-song snapshot against a local discard, and normal repeated sync triggers still share one run.
- Contended discard has a dedicated typed outcome that presentation code can turn into guidance to wait for the current sync, while unexpected failures retain separate failure handling.
- **Discard All** provides atomic admission rejection before either domain starts, but deliberately does not claim transactional rollback across the separate song and planning stores.
- The implementation must update the song CRUD spec, plan, domain model, architecture overview, and testing strategy in lockstep with this decision.
