# Planning reorder optimistic overlay cleanup

Related:
- `docs/plans/2026-04-28-planning-workspace-ui.md`
- `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`

The plan detail screen keeps optimistic session and session-item reorder overlays in widget state so the UI stays stable while the local write and provider invalidation settle. A later slice may want a stricter clear-on-refetch boundary or a small user-facing failure surface if stale optimistic order ever outlives the refreshed projection.

This was consciously left out of the current slice because the write path already invalidates the relevant planning providers and rolls back on failure; the remaining concern is cleanup semantics, not write correctness.
