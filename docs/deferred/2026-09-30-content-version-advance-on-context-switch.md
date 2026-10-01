# Content-Version Advance Survives a Mid-Run Context Switch Without the Write

**Slice:** feat/plan-delete-session-cascade (found by review gate 4 on
2026-09-30, F6; the defect is narrow and only reachable through this slice's
D7 rule 1a)
**Related:**
- `docs/specs/2026-09-29-plan-delete-and-session-cascade.md` (I3, I7, D7
  rule 1a, D8)
- `docs/architecture/decisions/ADR-038-plan-content-version.md` (the
  contiguity rule, and the "narrow crash windows" consequence)
- `docs/deferred/2026-09-30-stranded-create-tombstones.md` (another gap
  where a sync run ends before its local follow-up)

**Files:**
- `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
  (`_run`: the `_applyAcceptedEffects` call right after `syncMutation`, and
  the `refreshed` / refresh-failed branches at batch end)
- `apps/lyron_app/lib/src/application/planning_providers.dart`
  (`planningMutationSyncControllerProvider`: `refreshPlanning` and
  `shouldReconcileAcceptedMutation`, which compares the active context with
  the run's context)
- `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
  (`applyAcceptedWriteEffects`)

## Problem

D7 rule 1a advances the projection's plan `content_version` from R - 1 to R
as soon as the backend accepts the client's own child write W (R is the value
the RPC returned). The advance is applied immediately after `syncMutation`
returns, before the `accepted` marker is written. It is sound because W
itself is then reconciled into the projection, or brought in by the refresh.
That keeps I7: the projection's `contentVersion` never runs ahead of the
content it reflects.

If the active organization or user switches while the run is in flight:

1. Rule 1a has already advanced the old context's projection to R.
2. The batch-end refresh (`refreshPlanning`) refreshes the planning sync
   controller's current context, which is now the new one.
3. In the refresh-failed branch, `_shouldReconcileAcceptedMutation` is false
   for the old context, so W is never reconciled into the old projection. The
   accepted row is then cleared anyway.
4. The old context's projection now sits at content version R without W, and
   no overlay row stands in for W.

I7 is broken for that context until its next successful refresh.

The visible consequence is a dialog that under-counts. A plan delete recorded
offline in that window shows a confirmation that omits W's rows (for example
a session the user just added). The delete's base is R, which equals the
backend's content version, so the backend accepts it and removes W's rows
too (absent foreign writes). Nothing foreign is absorbed: W is the user's
own write. But the delete removes something its confirmation did not list,
which is what gate 4's F1 closed for the other path (spec D11).

## Why it was deferred

The window is narrow. It needs a context switch (organization or user) to
land inside one sync run, followed by an offline plan delete in the old
context before that context refreshes again. The next successful refresh of
the old context repairs the projection, and no foreign write is ever
absorbed (I3 holds). A fix changes where rule 1a may run, which touches the
call-site ordering that D7 and its review gates settled, so it deserves its
own tests and review instead of a late change in the plan-delete PR.

## Options

### (a) Apply rule 1a only when the same context will refresh or reconcile

- Split the projection advance (rule 1a) from the delete-row rebases (rules
  1b, 2, 3). Only 1a is at fault: it raises a projection value, while the
  others adjust a pending delete's own base.
- Run 1a only when the run's context is still the active one, using the same
  predicate as `shouldReconcileAcceptedMutation`, at both call sites.
- If the context has moved on, leave the projection at R - 1. That lags the
  content instead of leading it, so the worst case is a visible false
  conflict on a later delete, resolved by retry after the next refresh.
- Rules 1b, 2, and 3 stay unconditional: they act on rows of the run's own
  context and are what lets a delete recorded mid-flight avoid a
  self-conflict.

### (b) Keep such rows `accepted` for the next run

- At batch end, when the run's context is no longer active, skip the clear
  for child rows whose rule-1a advance was applied. The row stays `accepted`.
- The next run in the old context resumes it like a crash-resumed marker: it
  reconciles W into the projection (the context is active then) and clears
  the row. The projection is already at R, so it ends consistent.
- Costs: the old context's overlay keeps showing W meanwhile (correct), and
  the accepted row is visible in the sync popup until the context is
  revisited. A user who never returns to that context keeps an `accepted`
  row indefinitely, so this option needs the same stranded-row scrutiny as
  `docs/deferred/2026-09-30-stranded-create-tombstones.md`.

## Requirements for the slice that picks this up

- Pick (a) or (b) and record it as an amendment to ADR-038's contiguity
  consequences.
- Red tests first, for both the refresh-failed and the refreshed branch:
  a child write accepted in context A, a switch to context B before the
  batch ends, then assert the projection of A is either still at R - 1 (a)
  or has W applied with the row kept `accepted` (b). Never at R without W.
- Check whether the `refreshed` branch has the same gap. It clears accepted
  rows without a reconcile because it relies on the refresh having replaced
  the projection, and with a context switch that refresh belongs to the new
  context. Only the refresh-failed branch was exercised by the review.
- Keep the same-context behavior unchanged: a `planCreate` reconciled at
  content version 1 followed by its accepted child must still reach 2 when
  the refresh fails (spec D7, call sites).

## Roadmap (2026-10-01)

Scheduled in slice **S5b** (`fix/planning-mutation-gaps`) of
`docs/plans/2026-10-01-delivery-roadmap.md`.

**Recommended default: option (a).** Rule 1a is gated by the same
same-context predicate that `shouldReconcileAcceptedMutation` uses.

- With (a), a lagging projection costs at most one visible false conflict.
- Option (b) would create more stranded `accepted` rows.

The S5b spec confirms or overrides this default.
