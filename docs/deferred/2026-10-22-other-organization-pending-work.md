# Other Organization's Pending Planning Work Is Invisible

**Found:** 2026-10-21, by the S5b organization-switch verification.
**Slice:** `fix/planning-mutation-gaps` (S5b PR 1, #97).
**Related:** `docs/specs/2026-10-21-planning-mutation-gaps.md` (MG1),
ADR-035 (amendment: an organization switch is not a purge reason),
`docs/deferred/2026-10-05-gate-cross-user-leaks.md`.

**Status:** accepted gap (user decision, 2026-10-21). Not implemented.

## Problem

An organization switch keeps the previous organization's planning projection
and pending mutation rows on the device (MG1). While another organization is
active, nothing shows that work: the header sync indicator and the sync
popup read the active `(userId, organizationId)` only, and the write
scheduler, manual sync and retry act on the active context only. The rows
sync when their organization is the active context again.

The work is not hidden from the destructive paths. `countPlanningPendingWork`
(`apps/lyron_app/lib/src/offline/auth/drift_pending_local_work_reader.dart`)
counts by `userId` only, so the sign-out warning, the different-user reauth
wipe and the D5 purge dialog all include it.

## Why deferred

The switch happens automatically (the active organization is the smallest
organization id of the user's memberships, `active_organization_resolution.dart`),
and no organization switcher exists yet. A user with pending work in an
organization they cannot reach in the UI is rare; the kept rows lose nothing
and are protected by every purge path's count.

## Options

- A read-only line in the sync popup, "unsynced changes in another
  organization", fed by a per-user count minus the active context's count.
  It explains the sign-out warning's number and needs no sync behavior.
- Syncing a kept outbox in the background: a run per kept `(user,
  organization)` pair. It needs a read path for the kept organization's
  context that does not make it the active one, and a rule for what an
  organization the user can no longer access does to its rows.

## Trigger

The first organization switcher, or a field report of a sign-out warning
count the user cannot find in the UI.
