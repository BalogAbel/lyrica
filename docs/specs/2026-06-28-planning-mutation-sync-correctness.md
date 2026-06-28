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
Move the inline reconcile `switch` (`providers.dart:387-504`) into a standalone `PlanningMutationReconciler` class with one public method per the current closure signature. The class takes its dependencies via **injected readers/parameters** (mutation store, context) and must **not** capture the provider `ref` — the current closure captures `ref` (`providers.dart:387`), so the migration must thread those dependencies explicitly to preserve behavior. No behavior change; lock it with characterization tests over every aggregate kind (plan create/edit, session create/rename/delete/reorder, session-item create/delete/reorder) asserting byte-identical reconcile output before any later step. The provider wires the class instead of the closure. This is the enabling refactor — it earns its place by making Steps 1–4 testable, not as standalone cleanup.

### Step 1 — `LF-2` hoist refresh out of the loop
Sync all pending mutations first, accumulating the accepted-but-uncleared set, then `_refreshPlanning()` **once**. Error handling within the batch is per-mutation and unchanged in kind: auth/dependency/conflict failures are still recorded individually against their mutation; a connectivity failure still **breaks** the loop early (no point hammering an offline backend). After the single refresh: on success, clear the accepted set; on refresh failure, reconcile **all** accepted-but-uncleared mutations via the extracted reconciler (today's per-mutation fallback, now applied to the whole accepted batch) and then clear them. This keeps the accepted→reconcile→clear invariant while collapsing N refreshes to one.

### Step 2 — `LF-1` exactly-once marker
No `accepted` state exists today: `PlanningMutationSyncStatus` is `{pending, failedAuthorization, failedDependency, failedRemoteDelete, conflict}` (`planning_mutation_sync_types.dart`), and the Drift schema has no marker column. This step therefore **adds** a durable accepted marker — a new `PlanningMutationSyncStatus.accepted` value persisted via an **additive Drift migration** on `planning_local_database` (no destructive schema change; additive only, per `LF-T7` guidance). The marker is written the moment `syncMutation` returns accepted, before `clearMutation`. On a subsequent run, a mutation already marked `accepted` is reconciled/cleared rather than re-sent, so a crash between accept and clear no longer produces a false conflict. The merge (Step 5) treats `accepted` as still-applied-locally so the edit does not flicker.

### Step 3 — `LF-3` single-flight guard
`PlanningMutationSyncController` is currently a `const`/stateless class (`planning_mutation_sync_controller.dart:17`), so it cannot hold a guard field. Convert it to a stateful instance (drop `const`) holding a `Future<void>? _inFlight`: `syncPendingMutations` returns the in-flight future when a run is already active (coalescing concurrent callers — write-service scheduler, retry, discard, unified trigger) instead of starting a second pass. Removes the double-send / `clearMutation` race. (Alternative considered: a provider-level wrapper guard; rejected because retry/discard call `syncPendingMutations` re-entrantly and a controller-owned guard is the single choke point.)

### Step 4 — `LF-7` offline discard/retry
Drop the leading `_refreshPlanning()` gate from `discardMutation`/`retryMutation`. Discard clears local intent unconditionally (offline-safe). Retry re-queues locally and attempts sync; if offline, the mutation simply stays pending. The post-op refresh becomes best-effort, not a precondition.

### Step 5 — `LF-4` keep failed edits visible
Surface `failed`/`conflict` mutations in the main plan view, not only the sync popup. The read merge consumes non-`pending` actionable statuses (`failed*`, `conflict`, and the new `accepted` from Step 2) so the user's edit stays on screen with a clear state indicator, instead of silently reverting to server state. (Recovery actions themselves remain in the sync surface.)

**Interaction risk with `LF-5` (out of scope but exposed here):** making non-`pending` edits visible can surface the latent `planEdit` field-blanking — the merge sets `description`/`scheduledFor` directly from the mutation with no `?? existing` fallback (`planning_local_read_repository.dart:143-147`), unlike `name`. A partial edit that didn't re-snapshot those fields would now render blanked instead of silently disappearing. Add a regression test asserting a visible failed/conflict `planEdit` does not blank unset fields; if it does, apply the minimal `?? existing` guard for the visible-edit path only (full `LF-5` fix remains a separate slice).

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
- **No** full `LF-5`/`LF-6` merge-completeness/dedup fixes, `LF-9` N+1 read, or `ARCH-2` invalidation — not in this bouquet. Exception: a minimal `?? existing` guard on the visible-edit path may be applied if Step 5's regression test proves blanking (full `LF-5` fix still deferred).
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
- Unit (`LF-1`): simulated crash between accept and clear → next run does not re-send and does not surface a false conflict; the `accepted` marker survives an additive Drift migration (open-with-pending-data migration test).
- Unit (`LF-3`): concurrent `syncPendingMutations` calls → single in-flight run; no duplicate `syncMutation`/`clearMutation`.
- Unit (`LF-7`): `discardMutation`/`retryMutation` with refresh unavailable → discard clears intent; retry re-queues and stays pending.
- Provider/widget (`LF-4`): an edit transitioning to `failed`/`conflict`/`accepted` stays rendered in the plan view with a state indicator; a visible `planEdit` does not blank unset `description`/`scheduledFor` (LF-5 interaction guard).

## Acceptance Criteria

- Implementation follows `docs/plans/2026-06-28-planning-mutation-sync-correctness.md`.
- Step 0 lands behavior-preserving with characterization tests green before Steps 1–5.
- All behaviour-matrix rows covered by tests and pass.
- No backend or authorization changes; focused validation commands in the plan pass.
