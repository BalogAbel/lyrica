# Live-Stack Verification of New Integration Suites — RESOLVED (with residual contract questions)

**Slice:** local-first-validation
**Files:**
- `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart` (LF-T1 scenario)
- `apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart` (scenario 2)

## Status: resolved

Both suites have now been **run against a live local Supabase stack** and pass (relaunch 1/1,
two-device matrix 5/5). They are wired into `scripts/verify.sh`'s online section (alongside the
existing authenticated integration suites), so CI/`verify.sh` exercises them with the
`SUPABASE_URL`/`SUPABASE_ANON_KEY` dart-defines rather than skipping them.

Live verification exposed and fixed real test-wiring gaps (each device must seed its own local
projection before its offline edit; the scratch-session id generator must produce UUIDs) and
corrected one assertion (see below). It also surfaced a genuine backend product bug, tracked
separately in `2026-06-29-slug-suffix-integer-overflow.md`.

## Residual open questions (not blocking; worth a follow-up ticket)

These two pairs pass live but their exact backend error-code contract was not pinned down — the
tests assert on the observed shape, which should be confirmed as the intended contract:

- **edit vs remote-delete** — the surviving device converges on the delete, but the precise RPC
  error code for a delete-vs-edit race (`remoteMissing` vs `conflict`) is asserted loosely.
- **partial edit (name only) vs full edit** — passes, but the backend's field-level
  no-op/merge semantics for `update_plan_fields` (LF-5) were not independently confirmed.

Additionally, the **add-same-song twice** pair documents that a truly-concurrent double-insert
sharing one stale `base_version` is unreachable from a sequential awaited test (the version
check fires before the app-level duplicate check; there is no DB-level
`unique(session_id, song_id)` constraint). A real concurrency stress test (parallel un-awaited
transactions) would be a separate effort if that invariant needs backend-level proof.

## Trigger Condition

Open a follow-up ticket to pin the RPC error-code contract for the two residual pairs, and
decide whether the add-same-song concurrency invariant needs a DB constraint
(cf. review SEC-5: `unique(session_id, song_id) where item_type='song'`) plus a true-concurrency
test. Fold the residuals into `docs/testing/testing-strategy.md` when addressed.
