# Governance Repair Implementation Plan

> Status: Implemented

**Goal:** Repair repository-owned source-of-truth drift by correcting shipped slice status notes and synchronizing the app-level README with the current product state.

**Architecture:** Keep this slice documentation-only. The change updates repository metadata and guidance rather than altering Flutter, Supabase, or workflow behavior.

**Tech Stack:** Markdown

---

### Task 1: Correct Shipped Slice Status Notes

**Files:**
- Modify: `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`
- Modify: `docs/plans/2026-04-01-session-scoped-plan-reader-navigation.md`
- Modify: `docs/specs/2026-04-03-slug-based-routing-for-songs-plans-sessions.md`
- Modify: `docs/plans/2026-04-03-slug-based-routing-for-songs-plans-sessions.md`
- Modify: `docs/specs/2026-04-05-song-crud.md`
- Modify: `docs/plans/2026-04-08-offline-first-song-crud.md`
- Modify: `docs/plans/2026-04-10-local-first-planning-create-edit.md`
- Modify: `docs/specs/2026-04-11-offline-first-planning-session-and-session-item-edit.md`
- Modify: `docs/plans/2026-04-11-local-first-planning-session-and-session-item-edit.md`
- Modify: `docs/specs/2026-04-13-song-reader-ui-discovery.md`
- Modify: `docs/plans/2026-04-14-song-reader-ui-implementation.md`

- [x] Replace stale or non-canonical status notes with workflow-compliant `Implemented` or `Implemented; partially superseded by ...` lines.
- [x] Remove non-canonical wording such as branch references, em-dash supersession text, and `Completed`.

### Task 2: Synchronize App README

**Files:**
- Modify: `apps/lyron_app/README.md`

- [x] Update the current-purpose section so it reflects shipped song CRUD, planning write, and reader-shell behavior.
- [x] Remove outdated statements that claim the app still lacks song editing, sync execution, or writable planning behavior.

### Task 3: Verify Repository Consistency

**Files:**
- Verify only

- [x] Re-scan `docs/specs/` and `docs/plans/` for status-note drift.
- [x] Run doc-focused consistency checks on the modified files.
