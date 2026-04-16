# Governance Repair

> Status: Implemented

## Goal

Bring the repository back into alignment with the already shipped product state so the repository remains the source of truth for current slice status, app behavior, and workflow guidance.

## Scope

- update stale or invalid spec and plan status notes for shipped slices
- add the missing formal status note to the song-reader UI implementation plan
- bring `apps/lyron_app/README.md` into sync with the currently shipped app behavior
- keep the change documentation-only and repository-owned

## Non-Goals

- no feature behavior changes
- no backend or Flutter implementation changes
- no reprioritization roadmap
- no attempt to redesign historical specs or plans beyond status-note correction

## Product And Workflow Rules

- shipped repository artifacts must not remain marked as merely proposed
- status notes under `docs/specs/` and `docs/plans/` must use the canonical workflow vocabulary
- app-level README content must describe the current shipped slices closely enough that future work does not start from outdated assumptions

## Success Criteria

- the relevant shipped specs and plans use correct status-note vocabulary
- the song-reader UI implementation plan has a formal status note
- `apps/lyron_app/README.md` no longer understates shipped planning, song CRUD, and reader behavior
