# S3 — ARCH-2: Scope planning invalidation (drop the global-counter over-rebuild)

**Date:** 2026-07-08
**Slice:** S3 (Phase 1)
**Finding:** ARCH-2 (`docs/architecture/repository-review-2026-06-22.md`)
**Branch:** `refactor/arch-spine-phase0-1`

## Problem

Every planning write bumps one global `planningDataRevisionProvider` counter.
Six read providers watch it, so a small within-plan edit (e.g. reordering an item
in plan X) invalidates and rebuilds **every** open plan detail, every plan summary
by slug, and the plan list — including plan Y's full detail, which did not change
(ARCH-2, Medium: "forcing broad rebuilds for small edits").

The waste is concentrated in `planningPlanDetailProvider` (the expensive
`getPlanDetail(planId)` read: sessions + items), rebuilt for **all** open plans on
any edit.

## Current wiring (post-S1)

Readers in `presentation/planning/planning_providers.dart`, all watching
`planningDataRevisionProvider`:

| # | Provider | Scope |
|---|----------|-------|
| 1 | `planningPlanListProvider` | plan list |
| 2 | `planningPlanBySlugProvider` (family, slug) | plan summary |
| 3 | `planningPlanDetailBySlugProvider` (family, slug) | plan detail |
| 4 | `planningPlanDetailProvider` (family, **planId**) | plan detail (expensive) |
| 5 | `planningMutationEntriesProvider` | pending mutation list |
| 6 | `hasUnsyncedPlanningMutationsProvider` | unsynced badge (bool) |

Writers already **directly invalidate** the specific providers they need — each
within-plan edit site in `plan_detail_screen.dart` runs, e.g.:

```dart
ref.read(planningDataRevisionProvider.notifier).state += 1; // global — the waste
ref.invalidate(planningMutationEntriesProvider);            // #5
ref.invalidate(planningPlanListProvider);                   // #1
ref.invalidate(planningPlanDetailProvider(planId));         // #4 THIS plan
```

The global bump is redundant for #1/#4(this plan)/#5 (already invalidated
directly); its only unique effects are refreshing #6 (badge) and the **waste**:
#2/#3 (by-slug) and #4 for **other** plans. `PlanSummary` has no session/item
count, so session/item edits do not change any plan summary.

Every write also funnels through `PlanningWriteService`, whose `syncScheduler`
bumps the same global counter at `application/planning_providers.dart:159`. Each
write method ends with `await _scheduleSync(context)`, so the write **awaits** the
sync attempt (and this bump) before returning; the screen's post-await
`ref.invalidate(planningPlanDetailProvider(planId))` therefore already captures
any reconciled state for the active plan.

## Goal

Introduce a second, mutation-scoped revision so within-plan session/item edits
stop bumping the global counter, eliminating the cross-plan / by-slug rebuilds,
while preserving every currently-correct refresh of the active view, the plan
list, and the unsynced badge.

## Design — two revision signals

Keep `planningDataRevisionProvider` as the **aggregate** signal and add
`planningMutationRevisionProvider` as the **mutation-state** signal.

`apps/lyron_app/lib/src/application/planning/planning_data_revision.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aggregate planning invalidation: the set of plans or a plan summary changed,
/// or a full sync / discard reconciled potentially many plans. Watched by all
/// planning read providers.
final planningDataRevisionProvider = StateProvider<int>((ref) => 0);

/// Pending-mutation invalidation: a local write changed mutation state (a
/// mutation was recorded, synced, discarded, or retried) without necessarily
/// changing the plan set. Watched only by the mutation-facing read providers so
/// a within-plan edit does not rebuild unrelated plan details. See ARCH-2.
final planningMutationRevisionProvider = StateProvider<int>((ref) => 0);
```

### Watchers (in `presentation/planning/planning_providers.dart`)

- #1, #2, #3, #4 — **unchanged**: keep watching `planningDataRevisionProvider`
  only. (So an aggregate bump still rebuilds them; a mutation-only bump does not.)
- #5 `planningMutationEntriesProvider` — additionally `ref.watch(planningMutationRevisionProvider)`.
- #6 `hasUnsyncedPlanningMutationsProvider` — additionally `ref.watch(planningMutationRevisionProvider)`.

### Writers (bump classification)

**Bump `planningMutationRevisionProvider` (mutation state changed):**
- `application/planning_providers.dart:159` — the `PlanningWriteService`
  `syncScheduler`, the choke point every write awaits. This is the single,
  always-correct source of the badge/mutation-list refresh for every write.

**Remove the `planningDataRevisionProvider` bump (rely on #159 for #5/#6; keep the
direct `#1` / `#4(planId)` / `#5` invalidates already present at each site):**
- `plan_detail_screen.dart` within-plan session/item edits:
  `_createSession` (:239), `_performSessionReorder` (:338 and :376),
  `_renameSession` (:609), `_addSong` (:699), `_deleteSession` (:813),
  `_performItemReorder` (:904), `_deleteItem` (:1211).

**Keep bumping `planningDataRevisionProvider` (aggregate — plan set / summary /
full-sync change):**
- `plan_detail_screen.dart` `_editPlan` (:201) — edits plan name / description /
  scheduledFor → changes `PlanSummary` → #1/#2/#3 must refresh.
- `unified_sync_providers.dart` (:127, :224) — unified/explicit sync completion.
- `unified_sync_status_popup.dart` (:353) — discard / retry (reverts a plan
  detail the popup cannot scope).

### Why this is behavior-preserving for the active view

- The user's own edit shows immediately: each within-plan site keeps its direct
  `ref.invalidate(planningPlanDetailProvider(planId))`, and the write awaits the
  sync scheduler, so reconciled state is captured by that invalidate.
- The badge / mutation list refresh via `planningMutationRevisionProvider` (bumped
  at #159, which every write awaits).
- The plan list keeps its direct `#1` invalidate at each within-plan site.
- Aggregate events (plan edit, sync, discard) still bump the aggregate signal →
  full refresh, unchanged.

### Accepted trade-off (documented)

`#159` bumps only the mutation signal, not the aggregate one. If several plans
hold pending mutations and an online per-write sync reconciles them all, an
**other** open plan's `#4` will not auto-refresh its reconciled fields until the
next interaction with that plan or the next unified sync (which bumps aggregate).
This is precisely the cross-plan rebuild ARCH-2 targets; refreshing plan Y on
every edit to plan X is the waste being removed. No data is lost; the active plan
and the badge are always current. This trade-off is recorded in `architecture.md`
and a code comment on `planningMutationRevisionProvider`.

## Scope

**In scope:** the second revision provider, the watcher rewiring (#5/#6), the
writer reclassification (8 within-plan sites + #159 → mutation; aggregate sites
unchanged), characterization tests, `architecture.md`, ARCH-2 marked fixed.

**Out of scope:** per-plan revision family + sync-affected-plan enumeration (the
fuller model, deliberately declined — disproportionate to a Medium finding). No
ADR (the effort's ADRs are scoped to ARCH-1/ARCH-5 per the definition of done);
this is a client-side invalidation change with no auth/schema impact.

## Testing (TDD, characterization-first)

New `test/application/planning/planning_data_revision_test.dart` (or extend
`providers_test.dart`) pinning the **wiring contract** at the provider layer
(deterministic, no widgets):

1. Bumping `planningMutationRevisionProvider` invalidates #5 and #6 but **not** #4
   (`planningPlanDetailProvider`) and **not** #1 (`planningPlanListProvider`).
2. Bumping `planningDataRevisionProvider` invalidates #1, #4, #5, #6.
3. Assert both by observing recomputation: read the provider, bump, read again,
   and check whether the underlying read function ran again (use a counting fake
   repository / override, mirroring the override style already in
   `providers_test.dart`).

Write these first; they fail against the current single-signal wiring (a mutation
bump currently does nothing, and #4 currently rebuilds on the global bump only).
Then implement the two-signal wiring to make them pass.

Also update the existing tests that manually bump the revision to reflect the new
split where they assert refresh of #5/#6 vs #1/#4:
`providers_test.dart` (:663), `plan_detail_screen_test.dart` (:299),
`plan_list_screen_test.dart` (:226), `app_router_test.dart` (:632) — adjust each
to bump the signal appropriate to what it asserts (mutation vs aggregate). Keep
the full suite green.

## Commits

1. `test(planning): pin two-signal planning invalidation contract` — failing
   characterization tests first.
2. `refactor(planning): scope within-plan edits to a mutation revision signal`
   — add the provider, rewire #5/#6, reclassify the writers; suite green.
3. `docs(review): mark ARCH-2 fixed (scoped planning invalidation)` — review doc +
   `architecture.md` invalidation note.

## Done when

- `planningMutationRevisionProvider` exists; #5/#6 watch it; within-plan edit
  sites no longer bump the aggregate signal; aggregate sites unchanged.
- Characterization tests pin: mutation bump ⇒ #5/#6 only; aggregate bump ⇒
  #1/#4/#5/#6. Green.
- `flutter analyze` clean; full `flutter test` green (existing revision tests
  updated).
- `architecture.md` records the two-signal invalidation + trade-off; ARCH-2 marked
  fixed in the review doc.
