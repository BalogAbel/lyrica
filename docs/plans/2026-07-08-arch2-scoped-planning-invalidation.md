# ARCH-2 Scoped Planning Invalidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a mutation-scoped planning revision so within-plan session/item edits stop bumping the global counter and no longer rebuild other plans' details or by-slug summaries.

**Architecture:** Two `StateProvider<int>` signals: `planningDataRevisionProvider` (aggregate, watched by all six planning readers) and a new `planningMutationRevisionProvider` (watched only by the two mutation-facing readers). Within-plan edit sites drop their aggregate bump and rely on the write service's single sync-scheduler choke point (which every write awaits) bumping the mutation signal; aggregate sites (plan edit, sync completion, discard/retry) are unchanged.

**Tech Stack:** Dart / Flutter, Riverpod, `flutter_test`.

**Spec:** `docs/specs/2026-07-08-arch2-scoped-planning-invalidation.md`

**No ADR** (the effort scopes ADRs to ARCH-1/ARCH-5; this is a client-side invalidation change, no auth/schema impact). **No RLS/RPC/schema change.**

---

## File Structure

- Modify: `apps/lyron_app/lib/src/application/planning/planning_data_revision.dart` — add the second provider.
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart` — #5/#6 watch the mutation signal.
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart` — line 159 bumps the mutation signal.
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart` — remove the aggregate bump at the 8 within-plan edit sites (keep `_editPlan`).
- Test (create): `apps/lyron_app/test/application/planning/planning_invalidation_scope_test.dart`.
- Test (adjust as needed): `providers_test.dart`, `plan_detail_screen_test.dart`, `plan_list_screen_test.dart`, `app_router_test.dart`.
- Docs: `architecture.md`, `repository-review-2026-06-22.md`.

---

## Task 1: Characterize the two-signal contract (failing first)

**Files:**
- Test: `apps/lyron_app/test/application/planning/planning_invalidation_scope_test.dart`
- (Read first) `apps/lyron_app/test/application/providers_test.dart` for the
  `_MutablePlanningRepository` / `_MutablePlanningMutationStore` fakes and the
  override style; reuse the same construction. If those fakes are private to
  `providers_test.dart`, copy the minimal fake shape into the new test file (a
  planning repository whose `getPlanDetail`/`listPlans` count calls, and a
  mutation store whose `readAllMutations`/`hasUnsyncedMutations` count calls).

- [ ] **Step 1: Write the failing characterization test**

The test pins WHICH revision each reader depends on, using recompute counts.
Because the planning read providers are `autoDispose`, each provider is kept
alive with a no-op `container.listen(..., fireImmediately: true)` so recomputation
happens only on invalidation, not on disposal/re-read. Structure:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/providers.dart';
// + the imports the fakes/overrides need, mirroring providers_test.dart
// (auth controller signed-in fake, activePlanningContextProvider override,
//  planningRepositoryProvider + planningMutationStoreProvider overrides).

void main() {
  test('mutation revision invalidates only the mutation-facing readers',
      () async {
    // Build a container with the same signed-in overrides providers_test uses,
    // plus counting fakes for the planning repository and mutation store.
    // (See providers_test.dart for the exact override set: appAuthController,
    //  activePlanningContextProvider, planningRepositoryProvider,
    //  planningMutationStoreProvider, planningSyncStateProvider as needed.)
    final container = /* ProviderContainer(overrides: [...]) */;
    addTearDown(container.dispose);

    // Keep each reader alive so it only recomputes on invalidation.
    container.listen(planningPlanDetailProvider('plan-1'), (_, __) {},
        fireImmediately: true);
    container.listen(hasUnsyncedPlanningMutationsProvider, (_, __) {},
        fireImmediately: true);
    container.listen(planningMutationEntriesProvider, (_, __) {},
        fireImmediately: true);
    container.listen(planningPlanListProvider, (_, __) {},
        fireImmediately: true);

    // Settle initial async reads.
    await container.read(planningPlanDetailProvider('plan-1').future);
    await container.read(hasUnsyncedPlanningMutationsProvider.future);
    await container.read(planningMutationEntriesProvider.future);
    await container.read(planningPlanListProvider.future);

    final detailCallsBefore = repository.getPlanDetailCalls;
    final listCallsBefore = repository.listPlansCalls;
    final mutationCallsBefore = mutationStore.readAllCalls;
    final hasUnsyncedCallsBefore = mutationStore.hasUnsyncedCalls;

    // Bump the MUTATION signal.
    container.read(planningMutationRevisionProvider.notifier).state += 1;
    await container.read(planningMutationEntriesProvider.future);
    await container.read(hasUnsyncedPlanningMutationsProvider.future);
    await container.read(planningPlanDetailProvider('plan-1').future);
    await container.read(planningPlanListProvider.future);

    // #5 and #6 recompute; #4 and #1 do NOT.
    expect(mutationStore.readAllCalls, greaterThan(mutationCallsBefore));
    expect(mutationStore.hasUnsyncedCalls, greaterThan(hasUnsyncedCallsBefore));
    expect(repository.getPlanDetailCalls, detailCallsBefore);
    expect(repository.listPlansCalls, listCallsBefore);
  });

  test('aggregate revision invalidates the plan detail and list readers',
      () async {
    final container = /* same setup */;
    addTearDown(container.dispose);

    container.listen(planningPlanDetailProvider('plan-1'), (_, __) {},
        fireImmediately: true);
    container.listen(planningPlanListProvider, (_, __) {},
        fireImmediately: true);
    await container.read(planningPlanDetailProvider('plan-1').future);
    await container.read(planningPlanListProvider.future);

    final detailCallsBefore = repository.getPlanDetailCalls;
    final listCallsBefore = repository.listPlansCalls;

    container.read(planningDataRevisionProvider.notifier).state += 1;
    await container.read(planningPlanDetailProvider('plan-1').future);
    await container.read(planningPlanListProvider.future);

    expect(repository.getPlanDetailCalls, greaterThan(detailCallsBefore));
    expect(repository.listPlansCalls, greaterThan(listCallsBefore));
  });
}
```

Fill the container setup and counting fakes by mirroring `providers_test.dart`.
The counting fakes add an `int` counter incremented in each read method.

- [ ] **Step 2: Run it — CONFIRM IT FAILS**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_invalidation_scope_test.dart`
Expected: FAIL — `planningMutationRevisionProvider` does not exist yet (compile
error), and once stubbed, the first test fails because #5/#6 do not yet watch it.

---

## Task 2: Implement the two-signal wiring

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_data_revision.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`

- [ ] **Step 1: Add the mutation revision provider**

Replace the contents of
`apps/lyron_app/lib/src/application/planning/planning_data_revision.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aggregate planning invalidation: the set of plans or a plan summary changed,
/// or a full sync / discard reconciled potentially many plans. Watched by all
/// planning read providers.
final planningDataRevisionProvider = StateProvider<int>((ref) => 0);

/// Pending-mutation invalidation: a local write changed mutation state (a
/// mutation was recorded, synced, discarded, or retried) without necessarily
/// changing the plan set. Watched only by the mutation-facing read providers so
/// a within-plan edit does not rebuild unrelated plan details (ARCH-2). An open
/// OTHER plan's reconciled fields may lag until its next interaction or the next
/// aggregate refresh; this is the intended scoping trade-off.
final planningMutationRevisionProvider = StateProvider<int>((ref) => 0);
```

- [ ] **Step 2: Rewire #5 and #6 to watch the mutation signal**

In `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`:

In `planningMutationEntriesProvider`, immediately after the existing
`ref.watch(planningDataRevisionProvider);` line, add:

```dart
      ref.watch(planningMutationRevisionProvider);
```

In `hasUnsyncedPlanningMutationsProvider`, immediately after its existing
`ref.watch(planningDataRevisionProvider);` line, add:

```dart
  ref.watch(planningMutationRevisionProvider);
```

Leave #1 (`planningPlanListProvider`), #2 (`planningPlanBySlugProvider`), #3
(`planningPlanDetailBySlugProvider`), and #4 (`planningPlanDetailProvider`)
watching only `planningDataRevisionProvider`.

- [ ] **Step 3: Point the write-service sync scheduler at the mutation signal**

In `apps/lyron_app/lib/src/application/planning_providers.dart`, in the
`planningWriteServiceProvider`'s `syncScheduler` `finally` block (currently
`ref.read(planningDataRevisionProvider.notifier).state += 1;`), change it to:

```dart
      } finally {
        ref.read(planningMutationRevisionProvider.notifier).state += 1;
      }
```

- [ ] **Step 4: Remove the aggregate bump at the 8 within-plan edit sites**

In `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`, delete
the single line `ref.read(planningDataRevisionProvider.notifier).state += 1;`
from each of these handlers, leaving their `ref.invalidate(...)` calls intact:
`_createSession`, `_performSessionReorder` (two occurrences), `_renameSession`,
`_addSong`, `_deleteSession`, `_performItemReorder`, `_deleteItem`.

**Keep** the bump in `_editPlan` (it changes the plan summary → aggregate).

After deleting, run `cd apps/lyron_app && flutter analyze` and remove the
`planning_data_revision.dart` import from `plan_detail_screen.dart` only if it is
now unused (it is still used by `_editPlan`, so it should remain — the analyzer
will confirm). Do not use `// ignore:`.

- [ ] **Step 5: Run the characterization test — CONFIRM IT PASSES**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_invalidation_scope_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Update existing revision tests, then run the full suite**

Some existing tests bump `planningDataRevisionProvider` to force a refresh of #5
/#6. Those still pass (aggregate is still watched by #5/#6). But any test that
asserts #5/#6 refresh specifically via a *mutation* path, or that relied on the
removed screen bumps, may need to bump `planningMutationRevisionProvider`
instead. Run the suite and fix per failure:

Run: `cd apps/lyron_app && dart format lib test && flutter analyze && flutter test`
Expected: analyze clean; full suite green. For each failing test in
`providers_test.dart` (:663 area), `plan_detail_screen_test.dart` (:299),
`plan_list_screen_test.dart` (:226), `app_router_test.dart` (:632), decide from
what it asserts: if it checks the badge / mutation list, bump
`planningMutationRevisionProvider`; if it checks the plan list / detail, keep
`planningDataRevisionProvider`. Do NOT weaken assertions — adjust the signal to
match the real wiring. If a widget test edits a session and asserts the plan
detail updated, it still passes (the screen's direct `ref.invalidate` remains).
If any failure reveals a genuine behavior gap, STOP and apply systematic
debugging.

- [ ] **Step 7: Commit (test first, then impl)**

```bash
git add apps/lyron_app/test/application/planning/planning_invalidation_scope_test.dart
git commit -m "test(planning): pin two-signal planning invalidation contract"
git add apps/lyron_app/lib/src/application/planning/planning_data_revision.dart apps/lyron_app/lib/src/presentation/planning/planning_providers.dart apps/lyron_app/lib/src/application/planning_providers.dart apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart
# plus any existing tests you had to adjust in Step 6:
git add apps/lyron_app/test/
git commit -m "refactor(planning): scope within-plan edits to a mutation revision signal"
```

---

## Task 3: architecture.md + mark ARCH-2 fixed

**Files:**
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/architecture/repository-review-2026-06-22.md`

- [ ] **Step 1: Record the invalidation model in architecture.md**

In `docs/architecture/architecture.md`, near the planning / state-management
description, add a short note: planning invalidation uses two signals —
`planningDataRevisionProvider` (aggregate: plan set / summary / full sync) and
`planningMutationRevisionProvider` (pending-mutation state, watched only by the
mutation-facing readers) — so within-plan edits do not rebuild unrelated plan
details; note the documented cross-plan post-sync staleness trade-off. Keep the
edit scoped.

- [ ] **Step 2: Mark ARCH-2 fixed in the review doc (match the convention)**

Read the surrounding lines first (numbers drift). Three edits:

**a) `**Fixed**` digest** — add after the ARCH-5 bullet:

```markdown
- **ARCH-2** (arch-spine-phase0-1 slice) — planning invalidation is split into an
  aggregate signal (`planningDataRevisionProvider`) and a mutation signal
  (`planningMutationRevisionProvider`) watched only by the mutation-facing
  readers, so within-plan session/item edits no longer rebuild other plans'
  details or by-slug summaries. The accepted cross-plan post-sync staleness
  trade-off is documented in `architecture.md`.
```

**b) §4 ARCH-2 detail block** (the paragraph `**ARCH-2 — coarse invalidation.**`).
Append a status sentence:

```markdown
**Fixed (arch-spine-phase0-1)**: within-plan edits now bump a mutation-scoped
revision; only aggregate events (plan edit, sync completion, discard/retry) bump
the global signal.
```

**c) Remediation list** — the current line reads exactly:

```markdown
- ARCH-2: aggregate-scoped invalidation.
```

Replace it with:

```markdown
- ~~ARCH-2: aggregate-scoped invalidation.~~ **Done (arch-spine-phase0-1).**
```

Leave the summary-table row (line ~75) untouched.

- [ ] **Step 3: Commit**

```bash
git add docs/architecture/architecture.md docs/architecture/repository-review-2026-06-22.md
git commit -m "docs(review): mark ARCH-2 fixed (scoped planning invalidation)"
```

---

## Self-Review

- **Spec coverage:** second provider (Task 2 Step 1), #5/#6 rewiring (Step 2),
  #159 → mutation (Step 3), 8 within-plan sites de-bumped + `_editPlan` kept
  (Step 4), aggregate sites unchanged (untouched by design), characterization
  tests (Task 1), existing-test updates (Step 6), architecture.md + ARCH-2 doc
  status (Task 3). All spec sections covered. No ADR (per DoD).
- **Placeholders:** the characterization test leaves the container/fake
  construction to be mirrored from `providers_test.dart` — this is a deliberate
  "reuse the existing fixture" instruction, not a vague requirement; the assertion
  logic and provider names are fully specified.
- **Consistency:** provider names (`planningMutationRevisionProvider`,
  `planningDataRevisionProvider`) and the reader/writer classification match the
  spec's table exactly; the eight de-bumped handler names match the site
  inventory.

---

## Done when

- `planningMutationRevisionProvider` exists; #5/#6 watch it; the 8 within-plan
  edit sites and #159 no longer bump the aggregate signal; `_editPlan` and the
  sync/discard sites still do.
- Characterization tests pin mutation-bump ⇒ #5/#6 only and aggregate-bump ⇒
  #1/#4 (+#5/#6). Green.
- `flutter analyze` clean; full `flutter test` green.
- `architecture.md` records the two-signal model; ARCH-2 marked fixed.
