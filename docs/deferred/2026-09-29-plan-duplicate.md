# Duplicate a Plan (Plan as Template)

**Slice:** feat/plan-delete-session-cascade (scoped out on 2026-09-29)
**Related:** `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`
(introduces `plans.content_version`; a duplicate reads a consistent source
subtree by the same rule); `docs/deferred/2026-07-31-occ-divergence-lf-t5.md`
and ADR-028 (mutation budget)
**Files:**
- `supabase/migrations/202604100001_planning_write_contract.sql`
  (`create_plan`, `plan_next_slug`, `session_next_slug`)
- `apps/lyron_app/lib/src/application/planning/planning_write_service.dart`
- `apps/lyron_app/lib/src/application/planning/budgeted_planning_mutation_store.dart`

## Problem

Worship planning often repeats a structure from week to week: the same
sessions, and often a similar song set. There is no way to copy an existing
plan as the starting point for a new one. The user has to recreate every
session and add every song by hand.

## Why it was deferred

The design choice is non-trivial, and the two candidate approaches have
opposite trade-offs.

- **Server-side copy RPC** (`duplicate_plan`):
  - Atomic, and cheap on the client.
  - Offline, it can only duplicate as one pending mutation. The overlay would
    then have to synthesize a whole plan subtree from one row, and slug
    allocation for the new plan and its sessions has to stay backend-owned.
- **Client-side fan-out** (one `planCreate`, plus N `sessionCreate`, plus M
  `sessionItemCreateSong` mutations):
  - Reuses every existing write path offline.
  - A large plan produces many mutation rows at once, which the LF-T3
    mutation budget (ADR-028) may refuse partway through. Partial admission
    needs an explicit all-or-nothing rule.
  - Any of the N+M+1 creates can fail independently during sync.

## Requirements for the slice that picks this up

- Pick one approach in an ADR and state its offline behavior explicitly.
- The copy is all-or-nothing from the user's point of view. A half-created
  duplicate must never appear as a finished plan.
- The source is read from one consistent snapshot. Plan rows are read before
  children (I7 of the plan-delete spec), or the copy is done server-side in
  one transaction.
- Songs are referenced, never copied. The one-song-per-session rule still
  holds for each copied session.
