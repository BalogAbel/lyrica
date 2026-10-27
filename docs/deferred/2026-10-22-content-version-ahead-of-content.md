# Plan Content Version Can Run Ahead of Its Content (F1)

**Found:** 2026-10-22, by the whole-diff adversarial review of S5b PR 1 (#97).
**Slice:** `fix/planning-mutation-gaps` (S5b PR 1). The race predates it.
**Related:** `docs/specs/2026-10-21-planning-mutation-gaps.md` (I7, MG4),
`docs/architecture/decisions/ADR-038-plan-content-version.md` (D7, 2026-10-21
amendment), `docs/deferred/2026-10-22-other-organization-pending-work.md`.

**Status:** pre-existing race, not fixed by PR 1. Low probability. The tests
that state the intended behavior are committed and skipped:
`apps/lyron_app/test/offline/adversarial/planning_content_version_ahead_test.dart`.

**Scheduled: S5b PR 2 (fix/planning-unresolved-rows)**. Design approved on
2026-10-27 as decision F1 of `docs/specs/2026-10-21-planning-mutation-gaps.md`
(this sketch plus a versioned-row check that also covers records without a
returned content version); plan `docs/plans/2026-10-27-planning-unresolved-rows.md`.
This entry is removed when PR 2 lands.

## What MG4 guarantees, and what it does not

MG4 (PR 1) guarantees that a context switch, a failed reconcile or a skipped
reconcile never leaves the projection at the write's content version R
without the write W itself: rule 1a runs only right after the same record's
reconcile completed without throwing.

MG4 does not close this race: a pull for the **same** context that is stored
between C5 and the reconcile, and then the older W written over it. I7 ("the
projection's `contentVersion` never runs ahead of the content it reflects")
therefore holds **except for this race (F1)**.

## Problem

Interleaving, refresh-failed branch of `PlanningMutationSyncController._run`:

1. The projection is at plan content version 3, with session-1 `S` at v2.
2. The user's own rename W is accepted: session v3, content version 4. The
   after-write refresh returns `false`.
3. A foreign rename F of the same session is committed: session v4, content
   version 5.
4. Another pull for the same context, started after W, stores content
   version 5 with F in the projection. It lands between the C5 check and the
   record's reconcile.
5. The reconcile writes W over F. The session upsert in
   `planning_mutation_reconciler.dart` (`upsertSyncedSession`) has no version
   gate, and `_upsertSessionRow` in `planning_local_store.dart` is an
   `insertOnConflictUpdate` that skips only an equal row.
6. Rule 1a, `advanceAcceptedPlanContentVersion` with 4, is a no-op because
   the projection is already at 5.

Result: the projection claims content version 5 but shows W (session v3), not
F (session v4).

The race is pre-existing: on `d73e9071` (the commit before S5b PR 1) the
the bug reproduces (the interleaving yields the same wrong state there). PR 1 adds
one extra way to reach it: a context that moves A to B across one await and is
back in A at C5. C3 skips the refresh because the context was B, C5 holds
again, and the reconcile then runs against whatever a pull stored meanwhile.

## Impact

- **I3 (fail-open).** The next `planDelete` takes its base content version, 5,
  from the projection, and the server accepts it. F is absorbed without the
  user ever seeing it. A stale base would have conflicted (fail-safe); an
  over-advanced base does not.
- **Probability: low.** It needs a whole pull to finish inside the batch-end
  window (between C5 and the reconcile) and a foreign write on the same
  aggregate.

## Fix sketch

- Do the reconcile and the rule-1a advance in **one** local-store
  transaction, applied only when the projection's plan content version is
  exactly R - 1.
- At R or above, skip **both** the reconcile and the advance (not only the
  advance): a projection already at R or later holds the pull's content, and
  W is already in it or has been superseded.
- Gate the kinds that do not bump content version (`planEdit`, `planCreate`)
  on the plan's own `version` instead.
- The two skipped tests become the acceptance tests: remove their `skip:`.

## Trigger

Scheduled: S5b PR 2 (fix/planning-unresolved-rows)
