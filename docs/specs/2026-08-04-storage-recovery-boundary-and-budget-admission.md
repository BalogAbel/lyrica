# Storage Recovery Boundary and Budget Admission

> Status: Implemented (commits `a400461`, `2a09116`, `6f7cf93`, `2e55d70`,
> `8dd556f`, `72c8fe4`, `96a74a4` on `feat/offline-durability-phase4`, PR #64)

## Goal

Close the three findings from the PR #64 review. Two of them mean the guarantees
ADR-028 states are not the guarantees the code delivers.

1. **P1a** — storage recovery exists only on the planning mutation path.
2. **P1b** — the budget check is not serialised, so the bounded-store guarantee
   does not hold under concurrency.
3. **P2** — the budget refuses writes that would *shrink* the store.

## Problem

### P1a — recovery covers one write path out of four

`SongCatalogEvictor.evictDroppable()` is called from exactly one place:
`BudgetedPlanningMutationStore._guardedWrite`. Song mutation writes, catalog
snapshot replacement and planning projection writes go straight to Drift.

If the storage quota runs out on any of those, there is no eviction, no retry,
and no `LocalStorageWriteFailure` — the raw Drift exception escapes to whatever
called it. ADR-028 describes the recovery in general terms ("a write that reaches
the delegate and fails at the storage layer is treated as storage pressure"),
which is broader than what is implemented. LF-T4 is marked fixed in the register
on the strength of that broader claim.

### P1b — the budget check races itself

`_guardedWrite` measures the mutation footprint, `await`s, checks the threshold,
then `await`s the write. Nothing serialises that sequence. Two concurrent
`record*` calls for different aggregates both read the same pre-write size, both
pass the check, and both write.

That breaks the documented "the store can overshoot the budget by at most one
mutation" and, with enough concurrency, the bounded-store guarantee itself.

### P2 — a full store cannot be drained through the normal surface

The guard runs before delegating, for all nine `record*` methods. Two of those
*shrink* the store when they collapse a still-pending create:

- `recordSessionItemDelete` deletes the pending `sessionItemCreateSong` row;
- `recordSessionDelete` deletes the pending `sessionCreate` row **and** that
  session's pending item and item-order rows.

At an exhausted budget both are refused before the delegate ever runs, so the
user cannot shrink the pending set through the ordinary delete affordance. The
documented escape hatch — `clearMutation` via discard — still works, so this is
not a trap, but refusing a write that would free space is wrong on its own terms.

## Decisions

### D1 — One recovery boundary, shared by every growing local write

A single `LocalStorageWriteRecovery` provides
`Future<T> guard<T>(Future<T> Function() write)` implementing the policy ADR-028
already describes:

1. run the write;
2. on a domain rejection (`LocalPlanningSlugConflictException` and any other
   typed domain exception a caller declares), rethrow untouched — retrying would
   fail identically and evicting would destroy cached data for nothing;
3. on an `Error`, rethrow untouched — a programming defect must never be
   misreported as storage pressure;
4. on any other `Exception`, evict droppable catalog sources once, retry once,
   and wrap a second failure as `LocalStorageWriteFailure`. If eviction itself
   throws, surface the **original** write error as the cause.

It is injected the same way `onStorageFootprintChanged` already is: an optional,
nullable constructor parameter on the Drift stores, always supplied by the
production providers, omitted in direct test construction.

**Which writes it guards:** every local write that can increase stored bytes —
planning mutation `record*`, planning projection replacement and upserts, catalog
snapshot replacement, and catalog song-mutation saves. Writes that only delete or
shrink are not guarded: there is nothing to recover from, and guarding them would
add an eviction attempt to the very operations that free space.

`BudgetedPlanningMutationStore` stops implementing this policy inline and uses
the shared boundary, so there is one implementation and one place to change it.

### D2 — Serialise measure, check and write per context

The budget admission runs inside a per-`(userId, organizationId)` critical
section: the footprint measurement, the threshold check and the delegated write
are one serialised unit, so a concurrent write cannot slip in between the
measurement and the write it authorised.

Serialising per context rather than globally keeps a write for one
user/organization from blocking another, matching how the song sync/discard lease
and the planning sync single-flight are already keyed.

The overshoot bound then holds as documented: at most one mutation past the
threshold, because only one admission can be in flight per context.

### D3 — Admit writes that provably shrink the store

Before refusing, the guard determines whether this specific write is a
collapse — a delete whose target aggregate currently holds a still-pending create
that the delete will remove. Those are admitted regardless of the budget, because
they reduce the pending set.

Concretely: for `recordSessionDelete` and `recordSessionItemDelete`, read the
existing mutation for the target aggregate. If it is a pending create, the write
collapses rather than grows, so skip the budget check. Any other delete adds a
delete mutation row and stays subject to the budget.

This is decided from the store's own state, not from the method name alone: a
`sessionDelete` against a synced session genuinely grows the store and must still
be refused.

## Non-Goals

- Changing the protection order, the thresholds, or the accounting basis.
- Guarding pure deletes with eviction and retry.
- Any change to what the backend authorises.
- Riverpod 3, web offline E2E, or any Phase 5 item.

## Testing

1. **Recovery reaches every guarded path.** For each of the song mutation store,
   the catalog snapshot write and the planning projection write: an injected
   storage failure evicts droppable sources, retries once, and surfaces
   `LocalStorageWriteFailure`. Each must fail if that path's guard is removed.
2. **Domain rejections and `Error`s still pass through untouched** on the shared
   boundary — no eviction, no retry.
3. **Concurrency: the budget is not overshot.** Several `record*` writes for
   *different* aggregates issued together with `Future.wait` against a budget
   that admits only one: exactly one succeeds and the rest are refused. This test
   must fail against an unserialised guard.
4. **Serialisation is per context, not global.** Concurrent writes for two
   different `(userId, organizationId)` pairs do not block each other.
5. **A collapse is admitted at an exhausted budget.** With the budget exhausted:
   `recordSessionDelete` against a pending `sessionCreate` succeeds and removes
   the session plus its pending item and item-order rows;
   `recordSessionItemDelete` against a pending `sessionItemCreateSong` succeeds
   and removes it.
6. **A growing delete is still refused.** `recordSessionDelete` against a session
   that is not a pending create is refused at an exhausted budget — the admission
   is decided from store state, not from the method name.

## Documentation

- ADR-028: replace the single-path description with the shared boundary, record
  the per-context serialisation and the overshoot bound it restores, and record
  the collapse admission. State which writes are guarded and which are not.
- `docs/architecture/architecture.md` and `docs/testing/testing-strategy.md`
  updated to match.
- The LF-T4 entry in `docs/architecture/repository-review-2026-06-22.md` stays
  fixed, but now on an accurate basis; note the widening.

## Implemented

Landed as commits `a400461`, `2a09116`, `6f7cf93`, `2e55d70`, `8dd556f`,
`72c8fe4`, `96a74a4`. D1 (widened to every guarded write, not only the
planning-mutation path — see below), D2, and D3 are all implemented as
specified.

**Evidence:**

- `apps/lyron_app/lib/src/application/storage/local_storage_write_recovery.dart`
  — the shared `LocalStorageWriteRecovery.guard` boundary (D1).
- `apps/lyron_app/lib/src/application/storage/local_storage_domain_rejection.dart`
  — the `LocalStorageDomainRejection` marker interface.
- `apps/lyron_app/lib/src/application/planning/budgeted_planning_mutation_store.dart`
  — delegates to the shared boundary (D1); per-context `_writeQueue` (D2);
  `_collapsesPendingCreate`/`isCollapse` admission (D3).
- `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart` and
  `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart` — the
  optional `writeRecovery` constructor parameter wired into every write that
  can grow stored bytes (D1's widening — see "What implementation found" below).
- `apps/lyron_app/lib/src/application/core_providers.dart`,
  `planning_providers.dart`, `song_catalog_providers.dart` — production wiring
  of `localStorageWriteRecoveryProvider` into both stores.
- Tests: `test/application/storage/local_storage_write_recovery_test.dart`
  (the boundary itself); the `DriftPlanningLocalStore storage recovery (D1)`
  group in `test/offline/planning/planning_local_store_test.dart`; the
  `DriftSongCatalogStore storage recovery (D1)` group in
  `test/offline/song_catalog/song_catalog_store_test.dart`; and the D2/D3
  additions to `test/application/planning/budgeted_planning_mutation_store_test.dart`
  (concurrent-write admission, per-context non-blocking, collapse admission,
  and a non-collapsing delete still refused).
- Verified: `./scripts/verify.sh --skip-migrations --skip-backend-write-contracts`
  green (see the branch's CI / the closing commit).

**What implementation found that this spec did not anticipate:**

1. **`LocalSongSlugConflictException` also needed the `LocalStorageDomainRejection`
   marker.** This spec's D1 named `LocalPlanningSlugConflictException` as the
   example domain rejection. Widening the guard to `DriftSongCatalogStore.saveSongMutation`
   (commit `96a74a4`) surfaced that `saveSongMutation` throws its own slug-conflict
   exception mid-write, on the song side, and it needed the same marker for the
   same reason — without it, the shared guard would misread a duplicate-slug
   rejection as storage pressure and evict/retry into the identical rejection.
2. **`PlanningProjectionAbortedException` is a cooperative-cancellation signal,
   not a failure, and needed the same marker for a different reason than a
   domain rejection.** Widening the guard to `DriftPlanningLocalStore.replaceActiveProjection`
   surfaced that `_ensureProjectionCurrent` throws this exception when a newer
   refresh has superseded the current one — an expected control-flow signal
   `PlanningSyncController` already catches, not a rejected write. This spec's
   D1 described the marker only for domain rejections (a write refused by
   business rule); a superseded-refresh cancellation is a different reason to
   need the identical "pass through untouched" treatment, and the marker
   interface covers both without the guard needing to know which case it is
   looking at.

Also widened past what this spec's own D1 prose named: `reconcileSyncedSong`
(commit `96a74a4`) needed guarding too, since it inserts a new summary/source
row pair on a song's first sync — the same growth case D1 exists to protect,
even though this spec's Problem/Decisions sections named only "catalog
snapshot replacement and catalog song-mutation saves."
