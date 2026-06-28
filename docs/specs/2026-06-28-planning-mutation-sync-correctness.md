# Planning Mutation Sync Correctness Hardening

- Status: Proposed
- Date: 2026-06-28
- Scope: Mobile (`apps/lyron_app`) application layer — planning mutation sync loop, accepted-mutation reconciliation, local read merge.
- Findings: `LF-1`, `LF-2`, `LF-3`, `LF-4`, `LF-7`, and `ARCH-1` (reconciler extraction, in service of the above). Source: `docs/architecture/repository-review-2026-06-22.md`.

## Goal

Make the planning mutation sync loop **exactly-once-safe, single-flight, and offline-honest**: a crash mid-sync must not re-send and surface false conflicts; the loop must not concurrently double-send; per-mutation full refreshes must collapse to one; failed/conflicted local edits must stay visible in the main UI; and dropping local intent must not require connectivity. The inline reconcile logic is extracted into a testable unit first, so each fix lands on a covered surface rather than a closure.

## Current State (the bugs)

All evidence in `application/planning/planning_mutation_sync_controller.dart` unless noted.

- **`LF-1` — at-least-once, no dedup.** Per mutation the order is `syncMutation` (accepted) → `_refreshPlanning()` → reconcile → `clearMutation` (`:43-56`). A crash between accept and clear re-sends the same write on next run; non-idempotent ops (rename/reorder with `base_version`) then return a **false conflict** for an already-applied write.
- **`LF-2` — per-mutation full refresh.** `_refreshPlanning()` runs **inside** the per-mutation loop (`:47`) → N full Supabase refreshes for N mutations; slow and widens the divergence window between mutations (worse after long offline).
- **`LF-3` — no single-flight.** `syncPendingMutations` (`:35`) has no internal guard and is callable concurrently (write-service scheduler + retry + discard + unified trigger, `providers.dart:343-356`). Concurrent runs → double-send / `clearMutation` race.
- **`LF-4` — failed edits vanish from the main UI.** The read merge consumes only `pending` mutations (`planning_local_read_repository.dart:53`; filter `drift_planning_mutation_store.dart:423`). When an edit becomes `failed`/`conflict` it disappears from the plan view (reverts to server state), surfaced only in the sync popup — the user's offline edit appears lost.
- **`LF-7` — discard/retry need the network.** `discardMutation` and `retryMutation` call `_refreshPlanning()` first and **return on failure** (`:92,109`) → a stuck mutation cannot be dropped offline. Dropping local intent should never require connectivity.
- **`ARCH-1` — reconcile logic is an inline closure.** The accepted-mutation reconciler is injected as a `PlanningAcceptedMutationReconciler` closure (`:8-12,21,32`), defined as a ~110-line inline `switch` inside a provider closure (`providers.dart:387-504`). It cannot be unit-tested in isolation, which blocks clean fixes for `LF-1` and the reconcile-adjacent paths.

## Design

### Step 0 — extract `PlanningMutationReconciler` (`ARCH-1`, behavior-preserving)
Move the inline reconcile `switch` (`providers.dart:387-504`) into a standalone `PlanningMutationReconciler` class with one public method per the current closure signature. No behavior change; lock it with characterization tests over every aggregate kind (plan create/edit, session create/rename/delete/reorder, session-item create/delete/reorder). The provider wires the class instead of the closure. This is the enabling refactor — it earns its place by making Steps 1–4 testable, not as standalone cleanup.

### Step 1 — `LF-2` hoist refresh out of the loop
Sync all pending mutations first, then `_refreshPlanning()` **once**. On refresh failure, reconcile the accepted-but-unrefreshed mutations via the extracted reconciler (preserving today's fallback semantics, now applied to the batch).

### Step 2 — `LF-1` exactly-once marker
Persist an **accepted-but-uncleared** marker (or idempotency key) the moment `syncMutation` returns accepted, before `clearMutation`. On a subsequent run, a mutation already marked accepted is reconciled/cleared rather than re-sent, so a crash between accept and clear no longer produces a false conflict.

### Step 3 — `LF-3` single-flight guard
Add an internal single-flight guard to `syncPendingMutations`: a concurrent call awaits the in-flight run (or is coalesced) instead of starting a second pass. Removes the double-send / `clearMutation` race.

### Step 4 — `LF-7` offline discard/retry
Drop the leading `_refreshPlanning()` gate from `discardMutation`/`retryMutation`. Discard clears local intent unconditionally (offline-safe). Retry re-queues locally and attempts sync; if offline, the mutation simply stays pending. The post-op refresh becomes best-effort, not a precondition.

### Step 5 — `LF-4` keep failed edits visible
Surface `failed`/`conflict` mutations in the main plan view, not only the sync popup. The read merge consumes non-`pending` actionable statuses so the user's edit stays on screen with a clear state indicator, instead of silently reverting to server state. (Recovery actions themselves remain in the sync surface.)

## Behaviour Matrix

| Scenario | Now | New |
| --- | --- | --- |
| Crash between accept and clear | re-send → false conflict | accepted marker → reconcile/clear, no re-send |
| N pending mutations | N full refreshes | sync all, 1 refresh |
| Concurrent sync triggers | double-send / clear race | single-flight: second call awaits/coalesces |
| Discard a stuck mutation offline | blocked (returns) | clears local intent immediately |
| Retry offline | blocked (returns) | re-queues, stays pending until online |
| Edit becomes failed/conflict | disappears from plan view | stays visible with state indicator |

## Non-Goals

- **No** session/auth-lifecycle changes — covered by `docs/specs/2026-06-28-non-destructive-session-and-offline-relaunch.md`.
- **No** `LF-8` reconcile null-coercion hardening in this slice (the extraction makes it a cheap follow-up; tracked separately).
- **No** `LF-5`/`LF-6` merge-completeness/dedup fixes, `LF-9` N+1 read, or `ARCH-2` invalidation — not in this bouquet.
- **No** broad `providers.dart` domain-file split beyond the reconciler extraction (`ARCH-1` wide part stays out).
- **No** backend RPC, schema, RLS, or authorization changes (AGENTS.md rule 5).
- **No** change to the song-side mutation controller (shares `LF-1`/`LF-2`/`LF-3` but out of scope here; note parity as future work).

## Documentation Requirements

- Update `docs/architecture/architecture.md` sync section to describe single-flight, batch-then-refresh, the accepted marker, and offline discard/retry.
- Update `docs/testing/testing-strategy.md` to name the new sync-correctness regression coverage.
- If the accepted-marker model is a durable decision, add or extend an ADR (relates to `ADR-015-online-preferred-local-first-sync.md`, `ADR-014-planning-write-projection-mutation-boundary.md`).

## Testing

- Characterization (Step 0): `PlanningMutationReconciler` reproduces current reconcile output for every aggregate kind before any behavior change.
- Unit (`LF-2`): N pending mutations → exactly one `_refreshPlanning()`; refresh-failure path reconciles the batch.
- Unit (`LF-1`): simulated crash between accept and clear → next run does not re-send and does not surface a false conflict.
- Unit (`LF-3`): concurrent `syncPendingMutations` calls → single in-flight run; no duplicate `syncMutation`/`clearMutation`.
- Unit (`LF-7`): `discardMutation`/`retryMutation` with refresh unavailable → discard clears intent; retry re-queues and stays pending.
- Provider/widget (`LF-4`): an edit transitioning to `failed`/`conflict` stays rendered in the plan view with a state indicator.

## Acceptance Criteria

- Implementation follows `docs/plans/2026-06-28-planning-mutation-sync-correctness.md`.
- Step 0 lands behavior-preserving with characterization tests green before Steps 1–5.
- All behaviour-matrix rows covered by tests and pass.
- No backend or authorization changes; focused validation commands in the plan pass.
