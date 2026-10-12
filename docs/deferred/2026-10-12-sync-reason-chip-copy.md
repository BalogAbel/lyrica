# Sync Popup Reason Chips Show Code-Shaped Text

**Found:** 2026-10-12, while implementing SG7 of S0 PR 2.
**Related:** `docs/specs/2026-10-05-offline-first-startup-gate.md` (SG7),
ADR-040.

**Files:**
- `apps/lyron_app/lib/src/shared/app_strings.dart`
  (`unifiedSyncReason*` constants)
- `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`
  (renders the reason chips)

**Status:** pre-existing; not changed by SG7. Not implemented.

## Problem

The sync popup's reason chips still show identifiers instead of sentences:
`pending_local`, `sync_failed`, `conflict`, `dependency_blocked`,
`remote_missing` and `unknown`. SG7 replaced only the freshness identifiers
(`offline_cached`, `stale`) with readable copy.

The chips were deliberately code-shaped (a comment in `app_strings.dart` says
so), so this is a copy decision, not a bug in the SG7 work.

## Fix sketch

A copy pass over the six reason chips: short, user-facing wording, kept in
`AppStrings`, with the popup tests updated to the new text. No behaviour or
data change.

## Trigger

The next change to the unified sync status popup, or a copy pass over the sync
surface.

Roadmap (2026-10-12): scheduled in S6a.
