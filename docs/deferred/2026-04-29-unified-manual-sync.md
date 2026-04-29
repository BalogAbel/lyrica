# Unified Manual Sync Deferred Work

Originating slice:
- `docs/specs/2026-04-24-planning-workspace-ui.md`
- `docs/plans/2026-04-28-planning-workspace-ui.md`

## Status

Deferred.

## Deferred Item

### Make manual sync global across song and planning queues

The planning workspace slice keeps planning writes local-first and attempts
automatic planning mutation sync after writes. The current visible manual sync
entry point lives in the song-library surface and is song-queue oriented. That
means a user can reasonably expect "sync" to flush all pending local work, but
planning mutations are not clearly covered by that action.

Future work should decide and implement a unified manual sync contract:

- expose sync affordances consistently across relevant app surfaces
- make one manual sync action flush all pending local mutation queues, including
  songs and planning
- present combined pending, syncing, failed, conflict, and authorization-denied
  status without hiding domain-specific recovery actions
- keep backend authorization as the source of truth
- avoid creating separate, contradictory sync state machines for each screen
- verify offline-to-online retry for mixed song and planning queues

## Planning Note

Do not treat the song-list sync button as the app-wide manual sync contract
until this deferred item is resolved. Any future slice that changes sync
controls, sync status presentation, or local mutation queue orchestration should
pull this item into scope or explicitly supersede it.
