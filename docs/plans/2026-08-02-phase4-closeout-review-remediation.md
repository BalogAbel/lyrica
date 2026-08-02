# Phase 4 Closeout Review Remediation — Implementation Plan

> Status: Approved

> **For agentic workers:** REQUIRED SUB-SKILL: use
> `superpowers:subagent-driven-development` to execute this plan task by task.
> Use `superpowers:test-driven-development` for every behavior change,
> `superpowers:systematic-debugging` for every unexpected result, and
> `superpowers:verification-before-completion` before any pass or completion
> claim. One implementer at a time; read-only reviewers may run in parallel.

**Goal:** Remove the verified auth data-loss hazards, song sync/discard race,
stale storage-pressure measurement, and pg_cron contract-test gap found during
the final Phase 4 review, then reconcile the durable Phase 4 documents without
widening into Phase 5.

**Approved specification:**
`docs/specs/2026-08-02-phase4-closeout-review-remediation.md`

**Architecture:** Add a narrow user-wide Drift reader for destructive-work
counting; make auth generations and prompt request identities invalidate stale
side effects synchronously; add controller-owned song-context operation
ownership; drive a mounted footprint provider from callbacks emitted at the
concrete storage commit boundaries; execute the command stored in `cron.job`;
and align ADR/spec prose with the already implemented failure-driven eviction
policy.

**Branch and scope guard:** Execute only on
`feat/offline-durability-phase4`. Never switch to, commit on, merge into, or
delete `main`. Do not start Riverpod 3, web offline E2E, or any Phase 5 item.

## Execution Rules

- Before each task, query the relevant symbols through `graphify-out/` using
  `graphify explain` or `graphify path`; use manual reads only after that.
- Resolve third-party APIs through Context7 before use. Riverpod 2.6.x
  `listenManual(..., fireImmediately: true)` and pg_cron's `cron.job.command`
  have already been resolved, but re-query if the planned API changes.
- For every RED task, run the named focused command and paste its actual failing
  output into the task report. If a new typed API first produces an intentional
  compile failure, add only the minimum signature/seam needed to compile, rerun,
  and observe an assertion-level behavioral failure before the RED commit. A
  setup failure or a compiler error alone is not accepted evidence.
- Stop and report if an assertion fails for an unexpected reason. Do not weaken
  it or adjust the contract to match current behavior.
- After GREEN, deliberately falsify each concurrency/lifecycle test where the
  plan says to do so, observe failure, restore the implementation, and rerun
  green before committing.
- Use `dart format` on touched Dart files before every green commit.
- Each task below is one commit unless the task explicitly defines separate RED
  and GREEN commits. Keep documentation with the behavior it explains only
  where stated; otherwise use the dedicated documentation commits.

## Task 1 — Pin user-wide destructive-work counting (RED)

**Files**

- Modify:
  `apps/lyron_app/test/application/auth/pending_local_work_counter_test.dart`
- Create:
  `apps/lyron_app/test/offline/auth/drift_pending_local_work_reader_test.dart`
- Modify:
  `apps/lyron_app/test/application/auth/identity_persistence_wiring_test.dart`
- Create the minimum compiling seam only, if required:
  `apps/lyron_app/lib/src/offline/auth/drift_pending_local_work_reader.dart`
- Modify the minimum reader typedef/constructor signatures only, if required:
  `apps/lyron_app/lib/src/application/auth/pending_local_work_counter.dart`

**Tests to add**

1. The counter sums two injected user-wide integer readers and propagates either
   reader's failure rather than converting it to zero.
2. The Drift reader counts all six planning statuses (`pending`, `accepted`,
   `failedAuthorization`, `failedDependency`, `failedRemoteDelete`, `conflict`)
   for one user across multiple organizations.
3. The reader counts song `pendingCreate`, `pendingUpdate`, `pendingDelete`, and
   `conflict` rows across organizations, excludes `synced`, and excludes another
   user's rows.
4. At the live auth boundary, a non-pending planning row, a planning row in a
   second organization, and a song row in a second organization each prevent
   the zero-work silent wipe. No deletion occurs before confirmation.

Run and observe RED:

```bash
cd apps/lyron_app
flutter test test/application/auth/pending_local_work_counter_test.dart \
  test/offline/auth/drift_pending_local_work_reader_test.dart \
  test/application/auth/identity_persistence_wiring_test.dart
```

Expected red after the minimum seam compiles: the reader returns the wrong
counts and/or the live boundary still scopes by the prior identity's single
organization. Do not accept unrelated failures.

**Commit**

```text
test(auth): pin user-wide reauth work detection
```

## Task 2 — Implement user-wide destructive-work counting (GREEN)

**Files**

- Modify:
  `apps/lyron_app/lib/src/application/auth/pending_local_work_counter.dart`
- Modify the RED seam created in Task 1:
  `apps/lyron_app/lib/src/offline/auth/drift_pending_local_work_reader.dart`
- Modify:
  `apps/lyron_app/lib/src/application/auth_providers.dart`

**Implementation**

1. Replace the organization-scoped list-reader typedefs with two injected
   `Future<int>` user-wide count readers.
2. Add a read-only Drift adapter over `PlanningLocalDatabase` and
   `SongCatalogDatabase`. Filter only by `userId`; planning includes every
   actionable status and songs include every unsynced/conflict status but not
   `synced`.
3. Wire the adapter from `planningLocalDatabaseProvider` and
   `songCatalogDatabaseProvider`. Do not add count methods to the broad planning
   or song mutation-store interfaces.
4. Remove the cached-organization prerequisite from `countPriorPendingWork`.
   Only a storage read failure yields unknown (`null`) and forces confirmation.

Run GREEN:

```bash
cd apps/lyron_app
dart format lib/src/application/auth/pending_local_work_counter.dart \
  lib/src/offline/auth/drift_pending_local_work_reader.dart \
  lib/src/application/auth_providers.dart \
  test/application/auth/pending_local_work_counter_test.dart \
  test/offline/auth/drift_pending_local_work_reader_test.dart \
  test/application/auth/identity_persistence_wiring_test.dart
flutter test test/application/auth/pending_local_work_counter_test.dart \
  test/offline/auth/drift_pending_local_work_reader_test.dart \
  test/application/auth/identity_persistence_wiring_test.dart
```

Falsify the cross-organization contract by temporarily restoring an
`organizationId` predicate in the reader; observe the second-organization tests
fail, restore the implementation, and rerun GREEN.

**Commit**

```text
fix(auth): count all work affected by reauth cleanup
```

## Task 3 — Pin prompt identity and auth supersession (RED)

**Files**

- Modify:
  `apps/lyron_app/test/application/auth/reauth_prompt_controller_test.dart`
- Modify:
  `apps/lyron_app/test/application/auth/reauth_resolution_test.dart`
- Modify:
  `apps/lyron_app/test/application/auth/identity_persistence_wiring_test.dart`
- Modify:
  `apps/lyron_app/test/presentation/auth/reauth_prompt_host_test.dart`
- Modify only as needed to make the new typed test API compile, without
  implementing its behavior:
  `apps/lyron_app/lib/src/application/auth/reauth_prompt_controller.dart`,
  `apps/lyron_app/lib/src/application/auth/reauth_resolution.dart`

**Tests to add or replace**

1. Prompt requests have stable request identities and typed outcomes:
   `confirmed`, `cancelled`, and `superseded`.
2. `supersedePending` synchronously clears and completes the old request.
   Answering an obsolete request cannot answer a newer prompt.
3. `resolveReauth` performs neither wipe nor cancel for a superseded outcome.
4. Replace the test that currently expects user1 to be persisted after user2
   arrives: user0 → user1 prompt, then user2 must complete the stale future
   without user input, delete nothing, write no user1 identity, and let the
   latest edge resolve against durable user0.
5. Supersession while membership/count is blocked prevents zero-count wipe;
   supersession immediately before cancel prevents sign-out; supersession before
   same-user or post-wipe persistence prevents stale writes.
6. A prompt published before host attachment appears once. Rebuilds do not
   duplicate it. Completing an obsolete dialog does not complete a newer
   request.

Run and observe RED:

```bash
cd apps/lyron_app
flutter test test/application/auth/reauth_prompt_controller_test.dart \
  test/application/auth/reauth_resolution_test.dart \
  test/application/auth/identity_persistence_wiring_test.dart \
  test/presentation/auth/reauth_prompt_host_test.dart
```

**Commit**

```text
test(auth): pin superseded reauth safety
```

## Task 4 — Implement prompt identity and auth supersession (GREEN)

**Files**

- Modify:
  `apps/lyron_app/lib/src/application/auth/reauth_prompt_controller.dart`
- Modify:
  `apps/lyron_app/lib/src/application/auth/reauth_resolution.dart`
- Modify:
  `apps/lyron_app/lib/src/application/auth_providers.dart`
- Modify:
  `apps/lyron_app/lib/src/presentation/auth/reauth_prompt_host.dart`

**Implementation**

1. Give `ReauthPrompt` a stable request token and make answers identify their
   request. Add a typed prompt result and synchronous `supersedePending` that
   completes the old future non-confirmingly.
2. Add `ReauthSuperseded` to the pure resolution outcome. A superseded prompt
   invokes neither destructive callback nor cancel callback. Side-effect
   callbacks report whether they actually executed so the coordinator cannot
   claim `wiped` or `cancelled` after a last-moment currentness failure.
3. In the auth listener, synchronously advance the generation and supersede the
   open prompt before queuing each signed-in edge. Pass the captured generation
   and session into the queued work; do not first invalidate when the queued
   callback eventually begins.
4. Centralize a predicate that checks both generation and the live signed-in
   session's `userId`/`email`. Recheck after each user-controlled wait and
   immediately before song/planning deletion, backend sign-out, identity clear,
   and every identity write. Do not insert an `await` between a destructive
   currentness check and obtaining its deletion future.
5. Convert the host to `ConsumerStatefulWidget`; subscribe once with Riverpod
   2.6.x `ref.listenManual(..., fireImmediately: true)`. Track the active request
   token and answer by token so stale dialog completion cannot affect a newer
   request.

Run GREEN:

```bash
cd apps/lyron_app
dart format lib/src/application/auth/reauth_prompt_controller.dart \
  lib/src/application/auth/reauth_resolution.dart \
  lib/src/application/auth_providers.dart \
  lib/src/presentation/auth/reauth_prompt_host.dart \
  test/application/auth/reauth_prompt_controller_test.dart \
  test/application/auth/reauth_resolution_test.dart \
  test/application/auth/identity_persistence_wiring_test.dart \
  test/presentation/auth/reauth_prompt_host_test.dart
flutter test test/application/auth/reauth_prompt_controller_test.dart \
  test/application/auth/reauth_resolution_test.dart \
  test/application/auth/identity_persistence_wiring_test.dart \
  test/application/auth/app_auth_controller_test.dart \
  test/presentation/auth/reauth_prompt_host_test.dart
```

Falsify twice: temporarily delay generation invalidation until queued execution
and observe the overlapping-edge test fail; temporarily remove immediate prompt
delivery and observe the pre-existing-prompt test fail. Restore and rerun GREEN.

**Commit**

```text
fix(auth): supersede stale reauth resolutions
```

## Task 5 — Document the auth remediation

**Files**

- Modify:
  `docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`

Record user-wide destructive-work scope, synchronous generation/prompt
supersession, side-effect currentness checks, typed superseded outcomes,
request-token-safe answers, and current-value prompt delivery. Remove prose that
declares stale-edge serialization intentional. Do not mark the whole remediation
implemented yet.

Verify:

```bash
rg -n "user-wide|supersed|generation|fireImmediately|exactly once" \
  docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md \
  docs/architecture/architecture.md docs/testing/testing-strategy.md
git diff --check
```

**Commit**

```text
docs(auth): record superseded reauth safeguards
```

## Task 6 — Pin song sync/discard ownership (RED)

**Files**

- Modify:
  `apps/lyron_app/test/offline/adversarial/song_single_flight_test.dart`
- Modify:
  `apps/lyron_app/test/application/sync/unified_discard_controller_test.dart`
- Modify:
  `apps/lyron_app/test/application/sync/unified_row_recovery_controller_test.dart`
- Modify:
  `apps/lyron_app/test/presentation/sync/unified_sync_status_popup_test.dart`
- Modify only as needed to make the typed result/lease test API compile, without
  implementing ownership behavior:
  `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart`,
  `apps/lyron_app/lib/src/application/sync/unified_discard_controller.dart`

**Tests to add**

1. Hold the remote after `syncSong` entry; per-row discard returns a typed
   sync-in-progress outcome and leaves the mutation unchanged.
2. Pause a two-song same-context sync on song one; discarding song two is also
   rejected because the context snapshot owns both records.
3. Let discard acquire ownership first; a later sync waits, snapshots only after
   discard completes, and sends no discarded mutation.
4. Unified Discard All rejects before either song or planning removal when song
   sync owns the context.
5. The row and popup layers surface specific retry-after-sync guidance instead
   of swallowing the result or reporting success.

Run and observe RED:

```bash
cd apps/lyron_app
flutter test test/offline/adversarial/song_single_flight_test.dart \
  test/application/sync/unified_discard_controller_test.dart \
  test/application/sync/unified_row_recovery_controller_test.dart \
  test/presentation/sync/unified_sync_status_popup_test.dart
```

**Commit**

```text
test(sync): pin discard ownership during song sync
```

## Task 7 — Implement song-context operation ownership (GREEN)

**Files**

- Modify:
  `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart`
- Modify:
  `apps/lyron_app/lib/src/application/sync/unified_discard_controller.dart`
- Modify:
  `apps/lyron_app/lib/src/application/sync/unified_row_recovery_controller.dart`
- Modify:
  `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart`
- Modify:
  `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`

**Implementation**

1. Replace sync-only `_inFlight` coordination with owner-identified,
   context-keyed operation state. Same-context sync still coalesces. Discard
   encountering sync ownership returns a typed value; sync arriving behind
   discard waits for discard completion before reading candidates. Cleanup must
   remove an entry only when the completing operation still owns it.
2. Separate ownership acquisition from the owned local discard operation so
   Unified Discard All can hold one song-context lease across every song and the
   planning phase without nested acquisition.
3. Acquire batch ownership before either subsystem changes. If unavailable,
   return the typed rejection atomically. Preserve per-entry best effort only
   after ownership is held.
4. Propagate the typed value through unified and row controllers to a dedicated
   popup message. Do not use generic exceptions as the expected control path.
5. Preserve LF-7: no remote compensating write, no wait-then-success discard.

Run GREEN using the Task 6 command. Format every touched Dart file first.

Falsify both orderings: temporarily bypass the sync-owner rejection and observe
the held-RPC test fail; temporarily let sync snapshot before a discard-owned
operation completes and observe the discard-first test fail. Restore and rerun
GREEN.

**Commit**

```text
fix(sync): serialize song sync and discard ownership
```

## Task 8 — Document the sync/discard contract

**Files**

- Modify:
  `docs/architecture/decisions/ADR-013-song-write-sync-boundary.md`
- Modify:
  `docs/specs/2026-07-30-lf7-offline-discard-and-lf9-slug-read.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/product/sync-ux-contract.md`
- Modify: `docs/testing/testing-strategy.md`

Record context ownership, typed rejection, Discard All atomicity, UI guidance,
and the no-compensating-write LF-7 boundary. State again that LF-9 has no live
caller and is not a measured performance win.

Verify with `rg` for `sync in progress`, `mutually exclusive`, and
`Discard All`, then run `git diff --check`.

**Commit**

```text
docs(sync): record discard ownership contract
```

## Task 9 — Pin committed-storage revision behavior (RED)

**Files**

- Modify:
  `apps/lyron_app/test/application/sync/unified_sync_providers_test.dart`
- Modify:
  `apps/lyron_app/test/offline/planning/planning_mutation_store_test.dart`
- Modify:
  `apps/lyron_app/test/offline/planning/planning_local_store_test.dart`
- Modify:
  `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
- Modify:
  `apps/lyron_app/test/application/storage/song_catalog_evictor_test.dart`
- Modify:
  `apps/lyron_app/test/offline/adversarial/storage_pressure_contract_test.dart`
- Create/modify only the minimum compiling revision seam, without wiring commit
  behavior:
  `apps/lyron_app/lib/src/application/storage/local_storage_footprint_revision.dart`,
  `apps/lyron_app/lib/src/application/core_providers.dart`,
  `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`,
  `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`,
  `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`,
  `apps/lyron_app/lib/src/application/storage/song_catalog_evictor.dart`

For the four concrete storage classes, add only optional nullable callback
constructor parameters during RED. Do not emit the callbacks until Task 10.

**Tests to add**

1. Keep `localStorageFootprintProvider` mounted, advance the revision, change a
   fake measurement, and observe a second measurement plus pressure transition.
2. Each concrete storage boundary calls its injected change callback after a
   committed footprint change, not before it, and not after a throw or true
   no-op.
3. An idempotent upsert whose persisted payload is already identical does not
   emit a revision.
4. Eviction advances revision even when the guarded write retry later fails.
5. Earlier committed rows advance revision when a later outer batch operation
   fails.

Run and observe RED:

```bash
cd apps/lyron_app
flutter test test/application/sync/unified_sync_providers_test.dart \
  test/offline/planning/planning_mutation_store_test.dart \
  test/offline/planning/planning_local_store_test.dart \
  test/offline/song_catalog/song_catalog_store_test.dart \
  test/application/storage/song_catalog_evictor_test.dart \
  test/offline/adversarial/storage_pressure_contract_test.dart
```

**Commit**

```text
test(storage): pin footprint revision at commit boundaries
```

## Task 10 — Implement the storage-layer revision seam (GREEN)

**Files**

- Modify the RED seam created in Task 9:
  `apps/lyron_app/lib/src/application/storage/local_storage_footprint_revision.dart`
- Modify: `apps/lyron_app/lib/src/application/core_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/application/song_catalog_providers.dart`
- Modify:
  `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
- Modify:
  `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`
- Modify:
  `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`
- Modify:
  `apps/lyron_app/lib/src/application/storage/song_catalog_evictor.dart`
- Modify:
  `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart`

**Implementation**

1. Add a monotonic Riverpod revision provider and a framework-neutral
   `void Function()` storage-changed callback type.
2. Inject the same callback into production planning mutation, planning
   projection, catalog, and evictor instances. Emit after successful concrete
   commits: all planning mutation record/retry/result/clear paths; projection
   replacement/upsert/delete/order/cleanup; catalog snapshot replacement,
   mutation save, delete/reconcile/clear/cleanup; and successful droppable-source
   eviction.
3. Make callback constructor parameters optional and nullable for direct/test
   construction so unrelated callers do not require mechanical edits;
   production providers must always inject the shared callback.
4. Use affected-row counts for delete/clear methods. For idempotent upserts,
   compare the persisted footprint-relevant payload inside the storage boundary
   or use a conditional write so an identical payload emits no callback. Do not
   duplicate callbacks in controllers or screens.
5. Watch the revision in `localStorageFootprintProvider` before measuring. SQL
   accounting remains the only source of byte/count values.

Run GREEN using the Task 9 command after formatting all touched Dart files.

Falsify the partial-failure contract by temporarily moving the evictor callback
after the guarded retry; observe the eviction-plus-failed-retry test fail,
restore, and rerun GREEN.

**Commit**

```text
fix(storage): refresh footprint after committed changes
```

## Task 11 — Align storage policy documentation

**Files**

- Modify:
  `docs/architecture/decisions/ADR-028-local-storage-budget-and-eviction-policy.md`
- Modify:
  `docs/specs/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`

Replace proactive threshold-eviction claims with the approved contract:
critical measurement affects monitoring/warning; a qualifying write failure is
the only production eviction trigger and receives one retry. Record committed
storage revision behavior. Preserve the native-only verification statement and
the open web offline E2E prerequisite.

Verify:

```bash
rg -n "critical threshold.*evict|triggers automatic catalog eviction" \
  docs/architecture/decisions/ADR-028-local-storage-budget-and-eviction-policy.md \
  docs/specs/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md \
  docs/architecture/architecture.md docs/testing/testing-strategy.md
git diff --check
```

The first command must return no proactive-trigger matches.

**Commit**

```text
docs(storage): align eviction policy with failure recovery
```

## Task 12 — Bind the pg_cron test to the registered command

**Files**

- Modify: `scripts/tests/pg-cron-orphan-cleanup-contract-test.sh`

**Implementation and falsification**

1. Remove the copied `ORPHAN_CLEANUP_SQL` literal.
2. Query exactly one `cleanup-orphan-auth-users` row from `cron.job` as JSON.
   Assert its schedule and active state, extract its multiline `command` safely,
   and execute that command through the existing `run_psql` helper against the
   fixtures. Preserve the full job-name allowlist assertion.
3. Run the updated test. Because the registered command is currently correct,
   this hardening is expected to be GREEN immediately rather than red.
4. Falsify it by temporarily substituting a no-op for the fetched command after
   registration; observe fixture assertions fail, restore the real registered
   command execution, and rerun GREEN. Do not commit the deliberate break.

Verify:

```bash
bash -n scripts/tests/pg-cron-orphan-cleanup-contract-test.sh
bash scripts/tests/pg-cron-orphan-cleanup-contract-test.sh
```

The behavioral command requires the local Supabase stack. If the environment
cannot start it, report the gate as unexecuted; do not claim a pass.

**Commit**

```text
test(cron): execute the registered orphan cleanup job
```

## Task 13 — Focused remediation review and verification

Run every focused suite from Tasks 1–12 together, then:

```bash
cd apps/lyron_app
flutter analyze
dart format --output=none --set-exit-if-changed lib test
```

Dispatch a high-capability read-only semantic review over the remediation range.
It must query graphify first and validate auth deletion/currentness, operation
ownership cleanup, storage callbacks/no-ops/partial failures, cron command
binding, and test quality. Resolve verified findings test-first. Do not proceed
with an unresolved Blocker or Major.

No commit is expected unless review finds an issue. Any fix follows its own
RED/GREEN/docs commits and is re-reviewed.

## Task 14 — Refresh the committed code graph before verification

Run:

```bash
graphify . --update
git status --short
git diff --check
```

Review `graphify-out/GRAPH_REPORT.md`, manifest changes, and the diff summary.
Only graph artifacts caused by this branch may be committed.

**Commit**

```text
chore(graph): refresh after phase 4 remediation
```

## Task 15 — Establish full closeout evidence

Run from repository root and preserve actual output:

```bash
./scripts/verify.sh
./scripts/backend-write-contracts.sh
./scripts/check-migrations.sh
(cd apps/lyron_app && flutter build web --release)
git diff --check main...HEAD
git status --short --branch
```

The full verify must include the local Supabase stack, database reset, demo-user
provisioning, and skip-gated integration suites. If Docker/Supabase cannot run,
name the exact unexecuted gates. Do not mark any source document `Implemented`
without this evidence.

## Task 16 — Reconcile Phase 4 source documents

**Files**

- Modify the three Phase 4 specs:
  - `docs/specs/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`
  - `docs/specs/2026-07-30-lf7-offline-discard-and-lf9-slug-read.md`
  - `docs/specs/2026-07-30-recovery-actions-that-outlive-their-widget.md`
- Modify the three matching plans:
  - `docs/plans/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md`
  - `docs/plans/2026-07-30-lf7-offline-discard-and-lf9-slug-read.md`
  - `docs/plans/2026-07-30-recovery-actions-that-outlive-their-widget.md`
- Modify:
  `docs/specs/2026-08-02-phase4-closeout-review-remediation.md`
- Modify this plan.

Use `git log --follow`, current files, focused output, Task 15's full verification
output, and commit SHAs as evidence. Set specs/plans to `Implemented` only now,
after that full verification. Check only steps evidenced by commits/files/output;
leave a genuinely deferred or unexecuted item unchecked with an explicit
explanation.

Verify:

```bash
rg -n "^> Status: Draft" docs/specs/2026-07-30-*.md
rg -n "^- \[ \]" \
  docs/plans/2026-07-30-lft3-mutation-budget-and-lft4-storage-eviction.md \
  docs/plans/2026-07-30-lf7-offline-discard-and-lf9-slug-read.md \
  docs/plans/2026-07-30-recovery-actions-that-outlive-their-widget.md
git diff --check
```

Any remaining unchecked step must carry an evidence/deferred annotation.

**Commit**

```text
docs(phase4): reconcile closeout evidence
```

## Task 17 — Refresh the graph after evidence reconciliation

Run:

```bash
graphify . --update
git status --short
git diff --check
```

Review `graphify-out/GRAPH_REPORT.md`, manifest changes, and the diff summary.
Only graph artifacts caused by this branch may be committed.

**Commit**

```text
chore(graph): refresh phase 4 closeout evidence
```

## Task 18 — Repeat verification at the actual final HEAD

Run from repository root and preserve actual output:

```bash
./scripts/verify.sh
./scripts/backend-write-contracts.sh
./scripts/check-migrations.sh
(cd apps/lyron_app && flutter build web --release)
git diff --check main...HEAD
git status --short --branch
```

The full verify must again include the local Supabase stack, database reset,
demo-user provisioning, and skip-gated integration suites. If Docker/Supabase
cannot run, name the exact unexecuted gates. Task 15 establishes evidence for
status reconciliation; it does not substitute for this post-documentation,
post-graph final-HEAD run.

## Task 19 — Push, open one PR, and watch CI

1. Re-check `.github/PULL_REQUEST_TEMPLATE*`; follow a template if one now
   exists.
2. Push `feat/offline-durability-phase4` without force.
3. Create one PR with base `main` using `gh pr create --base main --head
   feat/offline-durability-phase4 --body-file <file>`.
4. The English body must include every slice/register/ADR/deferred/exclusion and
   caveat required by the user, including native-only LF-T4, unverified web
   IndexedDB assumptions, LF-9's lack of a live caller, and the exact Claude
   Code footer.
5. Watch checks with `gh pr checks --watch`. Diagnose failures before changes;
   never weaken a gate. Any fix repeats focused RED/GREEN, docs, review, final
   verification, push, and CI watch.
6. When CI is green, report the URL and result in Hungarian and stop. Do not
   merge or delete the branch without the user's explicit approval.

## Rollback Boundaries

- Auth count, auth supersession, sync ownership, storage revision, cron test,
  and document reconciliation are independently revertible commits.
- The typed prompt result/request token and auth generation scheduling form one
  coherent unit and must not be partially retained.
- The song lease/result/provider/UI changes form one coherent unit and must not
  be partially retained.
- No task adds a schema migration or changes backend authorization.
