# Spec: Pending Changes Cleanup

**Date:** 2026-05-15  
**Status:** Approved

> **Superseded in part:** `PlanningWorkspaceStatusSurface` was retained as the action home by this spec. It has since been removed by [2026-05-29-sync-ui-consolidation.md](2026-05-29-sync-ui-consolidation.md), which relocates recovery actions into the unified popup.

## Problem

After the unified sync header landed, inline mutation status chips appear in three places on planning screens (plan list row trailing, plan detail plan title area, plan detail session card header). These chips duplicate information already available through two dedicated sync surfaces:

- **`UnifiedSyncHeaderControl`** — ambient status (synced / unsynced / conflict) with tappable popup grouped by plan/session
- **`PlanningWorkspaceStatusSurface`** — per-mutation action surface (retry / keep mine / discard mine) rendered at screen top

Keeping the inline chips creates visual noise and implies that scattered badges are the right place to discover errors. They are not. Error recovery belongs on the action surface; ambient status belongs on the header.

## Decision

Remove `PlanningInlineMutationStatusBadge`, `planningInlineMutationStatusFor`, and `PlanningInlineMutationStatus` entirely. All mutation status and error visibility is delegated to:

1. `UnifiedSyncHeaderControl` — for ambient/overview state
2. `PlanningWorkspaceStatusSurface` — for actionable error recovery
3. `UnifiedSyncStatusPopup` — for per-plan/session detail listing

## Scope

### Code removed

- `PlanningInlineMutationStatus` enum
- `planningInlineMutationStatusFor` function
- `PlanningInlineMutationStatusBadge` widget

All defined in `apps/lyron_app/lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart`.

### Call sites removed

| File | Location | Widget key removed |
|---|---|---|
| `plan_list_screen.dart` | Plan row `ListTile.trailing` | `plan-row-status-<id>` |
| `plan_detail_screen.dart` | Plan header `Wrap` | `plan-local-status-<id>` |
| `plan_detail_screen.dart` | `_SessionCard` header `Wrap` | `session-local-status-<id>` |

### Tests updated

Remove inline badge finder/assertion lines from:

- `test/presentation/planning/plan_list_screen_test.dart`
- `test/presentation/planning/plan_detail_screen_test.dart`

No new tests required — the action surface and header already have test coverage.

### Docs updated

- `docs/specs/2026-04-24-planning-workspace-ui.md` — remove reference to inline badges representing sync conditions on plan rows
- `docs/plans/2026-04-28-planning-workspace-ui.md` — remove/update lines describing inline pending badges on plan rows and session cards

## What does NOT change

- `PlanningWorkspaceStatusSurface` — retained as the sole action surface for mutation error recovery
- `UnifiedSyncHeaderControl` usage on all three screens
- `_MutationStatusSurface` on `song_list_screen.dart` — outside scope (song domain)
- `planning_workspace_status_surface.dart` file itself — only the badge-related symbols are deleted; `PlanningWorkspaceStatusSurface` and its supporting widgets remain

## Success criteria

- No `PlanningInlineMutationStatusBadge` reference in production code
- `planningInlineMutationStatusFor` and `PlanningInlineMutationStatus` deleted
- Tests pass
- Docs updated
- Planning screens render without inline chips; errors still surface via action surface and header popup
