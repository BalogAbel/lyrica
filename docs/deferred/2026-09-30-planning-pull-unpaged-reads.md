# Planning Pull Reads Are Unpaged

**Slice:** feat/plan-delete-session-cascade (found by review gate 2 on
2026-09-30; the unpaged reads predate that slice)
**Related:** `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`
(invariants I2, I7)
**Files:**
- `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_repository.dart`
  (`listPlanRows`, `listSessionRows`, `fetchPlanningSyncPayload`)
- `supabase/config.toml` (`max_rows = 1000`; hosted projects default to the
  same cap)

## Problem

`fetchPlanningSyncPayload` reads the plans with one request, then each
plan's sessions, with their items embedded, with one request per plan.
Neither top-level request is paged or count-checked. PostgREST applies
`max_rows` to top-level rows, so it silently truncates a result that is over
the cap.

- **Sessions (I7).** For a plan with more than 1000 sessions, the refresh
  stores the plan's full `content_version` next to a truncated session list.
  The projection's `contentVersion` is then ahead of the content it reflects.
  A plan delete based on it is accepted and also removes the sessions the
  client never loaded.
  - The deleting member asked to delete that whole plan, so the practical
    harm is small.
  - It still breaks the invariant as stated.
- **Plans.** An organization with more than 1000 plans loses the extra plans
  from the offline projection. This does not affect I7, because whole plans
  are dropped, but it is a silent projection gap.

Reaching either limit needs more than 1000 sessions in one plan, or more
than 1000 plans in one organization. Neither is plausible in current use.

## Why it was deferred

Review gate 2 rated it minor: it depends on data volume, and no current
organization is anywhere near the cap. A correct fix pages the reads or
detects truncation, and is best done for the whole planning pull at once.
Other pulls may share the same shape; the fix slice should check them.

## Requirements for the slice that picks this up

- Detect truncation independently of the server's cap. For example, request
  `count=exact` and fail the refresh when fewer rows arrive than counted, or
  page with `.range()` until the count is reached. A failed refresh is the
  fail-safe outcome for I7.
- If the reads are paged, order them by a unique key so pages cannot overlap
  or skip rows. A write that moves rows between page reads bumps the plan's
  `content_version` past the stored value, so the result stays behind (safe).
  Deduplicate by id anyway.
- Add a red test that feeds the payload builder a truncated page and expects
  a failed refresh, or a complete paged result.
- Remove the "Known limit" notes in the spec (I7) and in
  `supabase_planning_repository.dart` when this is fixed.

## Update (2026-10-01, delivery roadmap)

**The song catalog pull has the same shape.** `listSongsRows` in
`apps/lyron_app/lib/src/infrastructure/song_library/supabase_song_repository.dart`
selects every song with `.order('title')` and no `.range()`. Above
`max_rows = 1000`, PostgREST silently truncates the result, so songs late in
the alphabet drop out of the song list and the offline catalog. A library of
more than 1000 songs is far more plausible than a plan with more than 1000
sessions.

Consequences for the slice that picks this up:

- **The catalog must page.** Failing the refresh on truncation is not an
  acceptable fail-safe there, because a large library would never refresh
  again.
- **The planning reads may page or fail the refresh.** The requirements above
  still hold. One shared paging helper for both domains is preferred.
- **Paging must keep the catalog's existing guarantees:** ADR-037 local-first
  visibility and the rejected-empty-snapshot guard.

**Scheduling:** slice **S5a** (`fix/paged-remote-pulls`) in
`docs/plans/2026-10-01-delivery-roadmap.md`, second in order. It is not
urgent: the user confirmed on 2026-10-01 that no organization is close to 1000
songs. The personal-layer pull planned in S3 reuses the helper.
