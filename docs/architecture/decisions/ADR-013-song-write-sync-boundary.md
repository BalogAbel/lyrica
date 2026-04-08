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
- song deletion is rejected while any `session_item` still references the song
- accepted song deletion cascades to song-owned attachments
- `pending_delete` rows are hidden from normal local reads and route resolution immediately, while remaining available in dedicated sync/conflict recovery surfaces
- offline-created slugs must be unique within the active local organization before sync succeeds, and the client must reconcile to the canonical server slug returned after sync

## Consequences

- Authorization remains backend-enforced even when the app is offline-first.
- Conflict resolution stays explicit and auditable instead of degenerating into last-write-wins retries.
- Song deletion remains safe against stale local knowledge about dependent planning data.
- Local routing and lookup behavior stays deterministic even when multiple songs are created offline with similar titles.
- The implementation must update the song CRUD spec, plan, domain model, architecture overview, and testing strategy in lockstep with this decision.
