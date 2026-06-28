# Storage Quota / Eviction Policy (LF-T4)

**Slice:** local-first-validation
**Finding:** `LF-T4` (`docs/architecture/repository-review-2026-06-22.md`)
**Files:**
- `apps/lyron_app/test/offline/adversarial/storage_pressure_probe_test.dart` (probe)
- `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart` (probed, unchanged)

## Problem

There is no storage quota monitor or eviction policy. A full catalog snapshot, planning
projection, and an unbounded mutation store can in principle exceed available storage —
most acutely on web, where IndexedDB is subject to **silent browser eviction** under
quota pressure. The repository review flagged this as a real risk for "indefinite" offline
use but left the actual failure behavior uncharacterized: does a storage write failure get
swallowed, or does it surface?

## Deferred Because

A real fix is a new subsystem: a size monitor (tracking mutation-store and projection
footprint), an eviction policy (mutations protected, snapshot pieces droppable first), and
likely a user-facing warning when approaching quota. That is multi-week strategic work
(per the repository review's roadmap), not something to bolt onto a validation slice whose
job was characterizing existing behavior and closing in-seam correctness gaps.

## What This Slice Did Instead

Added `storage_pressure_probe_test.dart`, a characterization probe that forces a storage
write failure in `DriftPlanningMutationStore.recordPlanCreate` and confirms the failure
**propagates as an exception** rather than being silently swallowed (no silent data loss
on a failed write). This narrows the risk: today, a storage-pressure failure is at least
visible to the caller instead of vanishing. It does not add quota monitoring, eviction, or
any user-facing handling of that propagated failure — that remains the deferred work.

## Trigger Condition

Address before shipping web as a primary offline target, or when any slice needs to reason
about long-offline storage growth (mutation-store size budgeting per `LF-T3`). A future
slice should also decide what the caller does with the now-confirmed propagated failure
(retry, warn the user, drop the write) rather than leaving that to whatever currently calls
the mutation store.
