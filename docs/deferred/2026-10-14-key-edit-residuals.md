# Key Edit Residuals

**Slice:** feat/song-key-planning-client (S3 PR 2; found by the final
adversarial review on 2026-10-14)
**Related:** `docs/specs/2026-10-13-personal-song-settings.md` (PS14-PS16),
ADR-038 (key-edit amendment), ADR-041,
`docs/specs/2026-10-21-planning-mutation-gaps.md` (MG4, MG5)
**Files:**
- `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
- `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart`
- `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`

The review found no silent loss and no absorbed foreign write after its two
fixes. These are the residuals it rated non-blocking. Each ends in a visible
state (a failed row or one visible conflict), never in a wrong silent write.

**Triage (2026-10-27):** R1 (discarding a failed item create orphaned its
key-edit and order rows) was fixed by S5b PR 2 (MG9) and R3 by S5b PR 1
(#97, MG5); both are removed. R2 and R4 stay here, unscheduled.

## R2. The create overlay builds a v1 item over an already-versioned one

**What.** The create overlay arm in `planning_local_read_repository.dart`
(~line 386) builds a fresh `SessionItemSummary` at version 1 with a null key
even when the projection already holds that item at a higher version. It
needs a crash-left `accepted` create, a refresh, and a foreign key write.

**Why deferred.** Rare. The next key edit shows one visible conflict, which
Keep mine resolves.

**Where.** The same arm: prefer the projected item's version and key when the
item is already present.

## R4. The key write reads and records in two steps

**What.** `setSessionItemKey` reads the merged item and then records the edit
in a second step (one queue hop). A refresh between the two can change the
base the draft was built from. Inherited shape of the other planning writes.

**Why deferred.** The window is one queue hop and a stale base is fail-safe
(a visible conflict).

**Where.** `PlanningWriteService.setSessionItemKey`: resolve the base inside
the mutation store's record transaction.

S5b spec (2026-10-21): R1 was fixed as MG9 (S5b PR 2) and R3 as MG5 (S5b PR 1, #97) of `docs/specs/2026-10-21-planning-mutation-gaps.md`; R2 and R4 stay here.
