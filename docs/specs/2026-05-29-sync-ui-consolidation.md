# Spec: Sync UI Consolidation

**Date:** 2026-05-29  
**Status:** Approved

## Problem

The unified sync header control (`UnifiedSyncHeaderControl`) plus its popup
(`UnifiedSyncStatusPopup`) were introduced as the single ambient sync surface
for authenticated non-reader workspaces. Several per-screen sync surfaces still
linger and duplicate what the header already shows:

- **Song list** (`song_list_screen.dart`):
  - `_CatalogStatusSurface` — online / offline / refreshing / refresh-failed banner.
  - `_MutationStatusSurface` — per-song pending/conflict cards with Keep mine / Discard mine.
  - `SegmentedButton` filter — `All / Pending sync / Conflicts` selector.
  - mutation-status loading/failed text line.
- **Plan list** (`plan_list_screen.dart`) and **plan detail** (`plan_detail_screen.dart`):
  - `PlanningWorkspaceStatusSurface` — per-mutation Retry / Keep mine / Discard mine cards.

These surfaces add visual noise and imply that scattered per-screen widgets are
the place to discover and recover sync state. Per
[sync-ux-contract.md](../product/sync-ux-contract.md), the header answers "is
this workspace synced?", the popup answers "what is not synced?", and recovery
belongs in the popup.

This spec finishes the migration started by
[2026-05-15-pending-changes-cleanup.md](2026-05-15-pending-changes-cleanup.md),
which removed inline badges but left `PlanningWorkspaceStatusSurface` and the
song-list surfaces as the action homes. The blocker: the popup currently shows
state/reason chips only — it has **no recovery actions**. Deleting the
per-screen surfaces without first moving recovery into the popup would strip
conflict resolution from the UI entirely.

## Decision

1. Move recovery actions into `UnifiedSyncStatusPopup` rows.
2. Add a global "Discard mine" action to the popup, beside "Sync now", that
   discards all local changes for the active organization after a confirmation.
3. Delete the per-screen sync surfaces and the song-library browse filter.
4. Update the sync UX contract and the predecessor spec status to match.

The header sync control remains on every surface where it is shown today.

## Scope

### 1. Popup recovery actions (new)

`UnifiedSyncStatusPopup` (`apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`)
rows gain action buttons, gated by row severity. Behavior mirrors the
per-screen surfaces being removed:

| Row | severity | Actions |
|---|---|---|
| Song | `conflict` | Keep mine / Discard mine |
| Song | `pending` / `retryableFailure` | none (global Sync now covers) |
| Plan (group) | `conflict` | Keep mine / Discard mine — applied to all conflicted mutations in the plan group |
| Plan (group) | `retryableFailure` | Retry — applied to all retryable mutations in the plan group |
| Plan (group) | `pending` | none |

Plan-level recovery is **group-scoped**: one button cluster per plan row acts on
every pending/conflicted mutation belonging to that plan group. This matches the
popup's existing per-plan grouping.

**Wiring** (the popup is already a `ConsumerWidget`):

- Song actions → `songMutationSyncControllerProvider`
  (`keepMine` / `discardMine`), with `SongMutationContext` read from
  `activeCatalogContextProvider`.
- Plan actions → `planningMutationSyncControllerProvider`
  (`retryMutation` / `discardMutation`), iterated over the group's mutations,
  with `ActivePlanningReadContext` from `activePlanningContextProvider`.
- After each action: invalidate the relevant entry/list providers and bump
  `planningDataRevisionProvider` for planning, matching current screen logic.

**Data model change:** `UnifiedSyncPlanRow` must carry the underlying group
mutation references (aggregate type + aggregate id per entry) so plan-level
actions can reach them. `UnifiedSyncSongRow` already carries `songId`, which is
sufficient. `computeUnifiedSyncOverview` populates the new field.

**Error handling:** `SongMutationSyncException` / planning failures surface
through an in-popup dialog or inline message (reuse the existing song-list
`_showSyncIssueDialog` pattern); the popup must not collapse specific reasons
into a generic message — the per-row reason chip stays.

### 2. Global "Discard mine" (new)

A `Discard mine` action sits beside `Sync now` in the popup header row.

- **Visual emphasis:** low-emphasis / destructive styling (text or outlined
  button using `colorScheme.error`), explicitly *not* a `FilledButton` like
  `Sync now`, to reduce mis-tap risk.
- **Enablement:** enabled only when `overview.hasUnsyncedWork` is true.
- **Confirmation:** tapping opens a confirmation dialog that names what will be
  discarded, including counts, e.g. "12 local changes (8 songs, 4 plans) will be
  permanently discarded." The confirm button uses destructive styling.
- **Scope:** active organization only — all local song and planning mutations
  for the active authenticated organization. Consistent with `Sync now` scope.
- **Implementation:** a new discard-all entry point following the
  `UnifiedManualSyncController` pattern (context reader + per-domain steps), or a
  dedicated controller. It discards each pending/conflicted song
  (`discardMine`) and each planning mutation (`discardMutation`), then
  invalidates/refreshes. Built test-first.

### 3. Per-screen surfaces removed

**Song list** (`song_list_screen.dart`):

- `_CatalogStatusSurface` widget and its build-site.
- `_MutationStatusSurface` widget and its build-site (incl. the
  `mutationEntriesAsync.when(...)` block).
- `SegmentedButton<SongLibraryBrowseFilter>` filter control.
- mutation-status loading/failed text line and its `mutationStatusMessage`.
- supporting state now unused: `_cachedMutationEntries`,
  `_cachedMutationEntriesOrganizationId`, `_resolveMutationEntries`, the
  `songMutationEntriesProvider` `ref.listen`, and the `mutationRowsReady`
  gating branch.

**Plan list / plan detail:**

- `PlanningWorkspaceStatusSurface` widget
  (`planning_workspace_status_surface.dart`) and the `statusSurface` parameter
  on `PlanningWorkspaceShell`, plus its build-sites in `plan_list_screen.dart`
  and `plan_detail_screen.dart`.
- The now-unused `planningMutationEntriesProvider` watch / mutation recovery
  helpers in those screens that only fed the status surface
  (`_retryMutation` / `_keepMine` / `_discardMine` move into the popup wiring;
  remove the screen copies if no other caller remains).

Retained everywhere it exists today: `UnifiedSyncHeaderControl`.

### 4. Browse filter removed entirely

The `All / Pending sync / Conflicts` filter is the only consumer of mutation
data inside the song-library browse path. Remove it fully:

- `SongLibraryBrowseFilter` enum (`song_library_browse_state.dart`).
- `SongLibraryBrowseState.filter`, its `copyWith` parameter, and
  `equals`/`hashCode` participation.
- `SongLibraryBrowseController.setFilter`.
- `SongLibraryBrowseRow.mutationRecord` and `matchesFilter`.
- `mutationEntries` parameter of `buildSongLibraryBrowseRows`.
- `filter` parameter of `filterSongLibraryBrowseRows`.
- `songLibraryBrowseRowsProvider` no longer watches `songMutationEntriesProvider`.

`SongLibraryBrowseSort` (title ascending) and query filtering are retained.
`songMutationEntriesProvider` itself stays — `unifiedSyncOverviewProvider`
consumes it.

### Documentation

- [sync-ux-contract.md](../product/sync-ux-contract.md):
  - "Header Status Popup": state that the popup **hosts** the recovery actions
    (song Keep/Discard, plan-group Retry/Keep/Discard) and a global
    `Discard mine` action scoped to the active organization.
  - "Inline Status Responsibility" (the inline-badges section): rewrite — the
    screen-level status surfaces and the pending/conflict browse filter are
    removed; the header control plus popup are the single source of sync truth.
- [2026-05-15-pending-changes-cleanup.md](2026-05-15-pending-changes-cleanup.md):
  note that `PlanningWorkspaceStatusSurface` (kept by that spec) is now
  superseded and removed by this spec.

## Out of Scope

- Reader surfaces (the song reader does not show the header control and is
  untouched).
- Changing the header chip's color/freshness semantics.
- Per-mutation (sub-plan) recovery granularity — plan recovery is group-scoped
  by decision.

## Testing

Test-first per repository discipline:

- Popup song-row recovery: Keep mine / Discard mine invoke the song controller
  with the right context and refresh.
- Popup plan-row recovery: Retry / Keep / Discard apply across all mutations in
  the plan group.
- Global Discard mine: disabled when clean; shows confirmation with counts;
  discards active-org song + planning mutations on confirm; no-op on cancel.
- Reason chips still render the specific blocking reason alongside actions.
- Song-list and planning-screen widget tests updated/removed for the deleted
  surfaces and filter; assert the surfaces and the filter control are gone.
- Browse-row tests updated for filter removal.
