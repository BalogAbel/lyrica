# Header Consistency and Sync Presentation Implementation Plan

**Goal:** Converge authenticated non-reader headers on one compact icon-based
pattern, render sync status as a dot, promote `Plans` to a primary action,
demote `Import` to the overflow menu, fix the planning header to a single row,
and remove the sync control from the song editor.

**Architecture:** No new layers. `UnifiedSyncHeaderControl` becomes a dot +
tooltip wrapping the existing popup tap. `PlanningWorkspaceShell._WorkspaceHeader`
collapses to a single `Row`. Song-library header actions move into icon buttons
plus a `PopupMenuButton`; the overflow `Import` item is gated by a synchronous
capability lookup that mirrors `IfCapability` fail-open semantics.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Repo runs from
`apps/lyron_app`; tests via `flutter test`.

---

## Working directory

All paths relative to `apps/lyron_app`. Run `flutter` commands from there.

## File Structure

- Modify `lib/src/presentation/sync/unified_sync_header_control.dart` — dot-only
  render, status label moved to tooltip.
- Modify `lib/src/presentation/song_library/song_list_screen.dart` — icon
  actions; `Plans` primary icon; `Import`/`Sign out` overflow menu; add
  `_canEditSongs` helper for menu gating; `_SongListMenuAction` enum.
- Modify `lib/src/presentation/planning/widgets/planning_workspace_shell.dart` —
  single-row header; remove the `< 640px` stacking branch.
- Modify `lib/src/presentation/planning/plan_list_screen.dart`,
  `plan_detail_screen.dart` — `Create plan` / `Edit plan` / `Add session`
  become icon buttons.
- Modify `lib/src/presentation/song_editor/song_editor_screen.dart` — remove
  `UnifiedSyncHeaderControl` and its now-dead import.
- Modify `lib/src/shared/app_strings.dart` — remove dead `unifiedSyncTooltip`.
- Docs: `docs/product/sync-ux-contract.md` (editor exclusion + dot
  presentation), this spec/plan pair, forward pointers in the two superseded
  specs.

## Tasks

- [x] Sync control → dot + tooltip.
- [x] Song-library header: dot, `Plans` icon, `Add song` icon, overflow menu
      (`Import` gated, `Sign out`).
- [x] Planning shell header → single row.
- [x] Planning action buttons → icons.
- [x] Remove sync control from song editor; drop dead import.
- [x] Remove dead `unifiedSyncTooltip` string.
- [x] Update widget tests to locate actions by tooltip / overflow menu.
- [x] Update `sync-ux-contract.md`; add forward pointers to superseded specs.
- [x] `flutter analyze` clean; `flutter test` green.

## Verification

```bash
flutter analyze
flutter test
```
