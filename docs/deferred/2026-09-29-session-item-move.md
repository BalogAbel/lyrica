# Move a Session Item to Another Session

**Slice:** feat/plan-delete-session-cascade (scoped out on 2026-09-29)
**Related:** `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`
(introduces `plans.content_version`, invariants I2–I5, and the contiguity rule
D7 that a move must also honor)
**Files:**
- `supabase/migrations/202604110001_planning_session_item_write_contract.sql`
  and `supabase/migrations/202606290002_session_item_unique_song_index.sql`
  (current item write RPCs and the one-song-per-session unique index)
- `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
  (per-aggregate mutation rows, fold/collapse rules)
- `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart`
  (overlay merge)

## Problem

A song cannot be moved from one session to another. The only way today is to
delete the item and add the song again in the target session. The workaround
has three drawbacks:

- The item's position is lost.
- The two writes sync as independent mutations, so either one can conflict or
  fail without the other.
- Offline, the user sees both halves as separate pending changes.

## Why it was deferred

A move touches two session aggregates at once. The planning mutation store
keeps one row per `(aggregateType, aggregateId)`, and every fold, collapse,
tombstone, and rebase rule (ADR-028, ADR-030, in-flight create cancellation)
assumes a mutation targets one aggregate. A two-aggregate mutation needs its
own design for:

- **Overlay:** the item is removed from the source and inserted into the
  target in one step.
- **Interaction with other writes:**
  - a cascade delete of either session, or of the plan
  - a concurrent reorder in either session
  - a pending create of the target session
- **Backend RPC:** it has to be atomic. It checks both session
  `base_version`s, enforces the target's unique-song rule, bumps both session
  versions, and bumps `plans.content_version` exactly once (I4). It locks the
  plan row first (I5), then both sessions in a deterministic order (for
  example by id), to avoid deadlocks between two opposite moves.

## Requirements for the slice that picks this up

- The move is one RPC and one mutation. It must not be sequenced as a client
  delete followed by an add.
- If the target session is deleted while a move into it is pending, the move
  must resolve deterministically. Either the move is dropped with the
  session's child rows, or it is surfaced as a dependency failure. A silent
  item loss is not acceptable.
- The D7 contiguity rebase must cover a move's response for any pending
  cascade delete of either session or of the plan.

## Roadmap (2026-10-01)

Scheduled in slice **S7** of `docs/plans/2026-10-01-delivery-roadmap.md`,
after plan duplicate. The S7 spec confirms or overrides these recommended
defaults:

- **A server-side move RPC** that meets every backend requirement above.
- **Online-only in v1**, recorded in an ADR. v1 creates no mutation row.
- **Disabled while pending changes exist.** While pending local mutations
  touch either session, the move is unavailable.
- **Offline support stays deferred.** The mutation-store and D7 requirements
  above apply to a later, offline-capable version.
- **No effect on the personal layer.** It keys plan-scoped data by
  `(plan_id, song_id)`, which a move does not change.
