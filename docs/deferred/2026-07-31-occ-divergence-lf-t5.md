# OCC Divergence Grows With Offline Duration (LF-T5)

**Slice:** offline-durability-phase4 (S15)
**Finding:** `LF-T5` (`docs/architecture/repository-review-2026-06-22.md`)
**Files:**
- `supabase/migrations/202604100001_planning_write_contract.sql` (`base_version` optimistic
  concurrency check on every planning write RPC)
- `apps/lyron_app/lib/src/application/storage/local_storage_budget.dart`
  (`mutationWarnBytes`/`mutationRefuseBytes`, the S12 mutation budget)
- `apps/lyron_app/lib/src/application/storage/local_storage_footprint.dart`
  (`mutationCount`, `LocalStoragePressure`)
- `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart`
  (`pendingMutationCount` surfaced in `UnifiedSyncOverview`)
- `apps/lyron_app/test/offline/adversarial/planning_squash_contract_test.dart`
  (exactly-once + OCC base-version fold contract)

## Problem

Every pending planning mutation carries the `base_version` it was created against
(`p_base_version` in `202604100001_planning_write_contract.sql`), and the backend
rejects a write whose base version no longer matches the row's current version. The
longer a device stays offline, the more the backend can move on without it — other
devices' syncs, other users' edits — so the probability that a given pending mutation's
base version is stale by the time it reaches the backend grows with offline duration.
A larger fraction of stale base versions means a larger conflict surface at reconnect.
The mitigation the original review named is incremental or partial sync with finer
merge granularity, so a long offline span accumulates less divergence per unit of
elapsed time.

## Deferred Because

Finer merge granularity is a change to the sync protocol itself — smaller sync units,
partial/field-level merge, or an incremental reconciliation model — not a fix that fits
inside the existing mutation-store/reconcile seam. Phase 4's remit was making offline
**durable and bounded**: giving unsynced local intent a hard ceiling and making its
growth observable, not reducing how much two diverging copies can disagree by the time
they reconnect. Changing merge granularity was out of scope for a slice that did not
otherwise touch the sync protocol.

## What Covers It Instead

Phase 4 did not reduce divergence, but it made it **observable and bounded** for the
first time, which it was not before this phase:

- The S12 mutation budget (`LocalStorageBudget.mutationWarnBytes` /
  `mutationRefuseBytes`, `BudgetedPlanningMutationStore`) caps how much unsynced local
  intent a device can accumulate before new writes are refused. Divergence is a function
  of how much unsynced intent exists at reconnect; that quantity can no longer grow
  without limit.
- The footprint monitor (`LocalStorageFootprint.mutationCount`,
  `LocalStoragePressure`) surfaces the pending mutation count and a storage-pressure
  level (`ok`/`warning`/`critical`) through `unifiedSyncOverviewProvider` into the
  unified sync UI. A long offline span with a growing conflict surface is now visible
  to the user before reconnect turns it into a pile of conflicts, rather than being
  silent until sync runs.
- The S12 squash contract suite (`planning_squash_contract_test.dart`) pinned that
  folding repeated local intent into one pending mutation preserves exactly-once sync
  semantics and OCC base-version semantics together. Closing that work fixed a real
  defect, not just a characterization: four fold paths (`sessionRename`,
  `sessionDelete`, `sessionItemDelete`, and one `planEdit` path) were letting a later
  local edit's base version overwrite the first-captured one on fold, which could
  silently suppress a real OCC conflict — the backend would compare against a base
  version newer than what the original edit actually saw, and a conflict that should
  have surfaced could pass unnoticed. The fix keeps the first-captured base version
  through every fold path, matching the reorder paths, which already did this
  correctly.

Net effect: divergence itself is unchanged, but it is now correctly **detected** where
before this phase some of it could be silently lost, and it is now **bounded and
visible** where before this phase it was neither.

## Trigger Condition

Address when either of these holds:

- The S12 mutation warn threshold (`mutationWarnBytes`, currently 1 MiB of pending
  planning mutations) actually fires for real users. That would be the first concrete
  evidence that offline spans are long enough, and pending intent large enough, for
  divergence to matter in practice rather than in theory.
- A future slice introduces field-level merge or partial/incremental sync for an
  independent reason (e.g. bandwidth, latency). At that point finer conflict
  granularity for LF-T5 comes nearly for free as a side effect, rather than justifying
  its own protocol change.
