# Server-Clock Anchor for Reconcile Ordering (LF-T6)

**Slice:** local-first-validation
**Finding:** `LF-T6` (`docs/architecture/repository-review-2026-06-22.md`)
**Files:**
- `apps/lyron_app/lib/src/application/planning/planning_mutation_reconciler.dart` (injectable clock seam, default unchanged)
- `apps/lyron_app/test/offline/adversarial/clock_skew_probe_test.dart` (probe)

## Problem

`PlanningMutationReconciler` stamps reconciled records using the device clock
(`DateTime.now().toUtc()`). Over a long offline span, device clock skew (manual change,
drift, timezone/DST edge cases) can distort ordering and freshness comparisons that assume
a roughly-correct wall clock. The reconciler had no seam to even observe this: the call was
inlined, making the skew behavior impossible to test or correct.

## Deferred Because

A real fix is a **server-clock anchor**: on reconnect, capture a trusted server timestamp
(e.g. from the RPC response or a dedicated time-sync call) and use it — or a calculated
offset against it — instead of the raw device clock for reconciliation ordering. That is a
new subsystem (a clock-offset provider, a backend timestamp contract, and changes to how
every accepted-mutation reconcile path sources "now"), not an in-seam fix. It was out of
scope for a slice focused on closing existing correctness gaps without introducing new
sync-protocol surface.

## What This Slice Did Instead

Added an injectable `now` clock seam to `PlanningMutationReconciler`
(`now: DateTime Function()`, defaulting to the previous `DateTime.now().toUtc()` behavior
via `_wallClockNow`), so device-clock skew is no longer hardcoded and unobservable. The new
`clock_skew_probe_test.dart` injects a skewed clock and characterizes that skew flows
straight through into reconciled timestamps with no correction — confirming the gap remains
exactly as described in `LF-T6`, now with a seam ready for a real fix to attach to.

## Trigger Condition

Address when offline duration grows long enough that ordering/freshness bugs from clock
skew are observed in practice, or when any slice introduces a trusted server-time source
(e.g. a heartbeat/ping RPC, or a timestamp already present in existing RPC responses) that
the reconciler could anchor to.
