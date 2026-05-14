# Unified Manual Sync Deferred Work

Originating slice:
- `docs/specs/2026-04-24-planning-workspace-ui.md`
- `docs/plans/2026-04-28-planning-workspace-ui.md`

## Status

Status: Pulled into planned follow-up scope; partially superseded by docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md

## Deferred Item

### Make manual sync global across song and planning queues

The planning workspace slice keeps planning writes local-first and attempts
automatic planning mutation sync after writes. The current visible manual sync
entry point lives in the song-library surface and is song-queue oriented. That
means a user can reasonably expect "sync" to flush all pending local work, but
planning mutations are not clearly covered by that action.

The online-preferred local-first sync contract decides the product direction for unified manual sync. Follow-up implementation should:

- expose sync affordances consistently across relevant app surfaces
- make one manual sync action flush all pending local mutation queues, including
  songs and planning
- present combined pending, syncing, failed, conflict, and authorization-denied
  status without hiding domain-specific recovery actions
- keep backend authorization as the source of truth
- avoid creating separate, contradictory sync state machines for each screen
- verify offline-to-online retry for mixed song and planning queues

## Planning Note

Do not treat the current song-list sync button as the app-wide manual sync
contract until the follow-up unified sync/freshness implementation replaces or
wraps it. The follow-up should use one active-organization manual sync command
for song and planning queues while leaving domain-specific conflict,
authorization-denied, and dependency-blocked recovery actions visible.
