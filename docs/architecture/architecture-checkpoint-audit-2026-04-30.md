# Architecture Checkpoint Audit - 2026-04-30

> Status: Audit checkpoint

## Scope

This document records the read-only architecture checkpoint audit performed on
2026-04-30. It preserves the audit findings in the repository so the repository
remains the source of truth for architectural, workflow, testing, and
authorization conclusions.

No files were modified during the audit itself. The audit was static: commands
inspected repository files, but verification scripts and test suites were not
run.

Primary sources inspected:

- `AGENTS.md`
- `README.md`
- `docs/product/vision.md`
- `docs/domain/domain-model.md`
- `docs/architecture/architecture.md`
- `docs/architecture/decisions/`
- `docs/testing/testing-strategy.md`
- `docs/workflows/`
- `docs/specs/`
- `docs/plans/`
- `docs/deferred/`
- `.github/workflows/ci.yml`
- `supabase/`
- `apps/lyron_app/`
- `scripts/`

## Final Verdict

No proven P0 issue was found by static inspection. The repository is not safe
for unrestricted mini-worker execution, but it is safe for constrained
mini-worker work on UI-only changes, documentation cleanup, simple widget/unit
tests, and small isolated app changes.

The following subsystems must not be handled by mini workers without stronger
model review:

- RLS policies and SQL helper functions
- Supabase migrations
- backend write RPCs
- sync/retry/idempotency logic
- optimistic concurrency logic
- auth/session lifecycle
- active-organization scoping
- cross-organization isolation
- data-loss or local-cache cleanup behavior
- durable architecture decisions

Strong guardrails already present:

- Supabase CLI is repository-local under `tooling/supabase`.
- Repository scripts broadly use `./scripts/supabase.sh`.
- No root-level Node setup was found.
- CI runs `./scripts/verify.sh` and a separate migration lint job.
- Core Drift data is scoped by user and organization.
- Planning sign-out and session-expiry cleanup delete local planning projection
  and mutations for the user.
- Supabase write RPCs re-check authorization, organization scope, duplicate
  constraints, empty-session delete rules, permutations, and optimistic
  concurrency versions.
- ChordPro parsing/rendering stays in Flutter.
- Backend remains the canonical write-acceptance boundary.

Guardrails that must be added or tightened before more agentic work:

- SQL write contract scripts must be part of the main verify or CI gate.
- Active-organization behavior must be explicitly modeled or documented as a
  temporary first-organization fallback.
- Song cache session-expiry policy must be aligned with planning cleanup policy
  or documented as intentionally different.
- Spec and plan status labels must follow the workflow vocabulary.

After remediation, review again:

- backend write contract CI coverage
- RLS/OCC regressions
- active-organization switching and stale active-org behavior
- sign-out/session-expiry cache cleanup
- mixed song and planning mutation sync behavior

## Phase 1 - Repository Rule Compliance

Evidence inspected:

- `AGENTS.md`
- `README.md`
- `.github/workflows/ci.yml`
- `scripts/verify.sh`
- `scripts/check-migrations.sh`
- `scripts/run-ci-locally.sh`
- `docs/**`
- `supabase/**`
- `apps/lyron_app/**`

Findings:

- The repository has required vendor-neutral `docs/specs/`, `docs/plans/`,
  and `docs/deferred/` paths.
- Supabase CLI is versioned under `tooling/supabase`.
- Common scripts expose wrapper-based Supabase entrypoints.
- Current checkout during audit was `main`; read-only audit is acceptable, but
  implementation work on `main` would violate `AGENTS.md`.
- CI runs `./scripts/verify.sh` for the verify job and
  `./scripts/check-migrations.sh` for the migrations job.
- The main verification gate does not visibly invoke the backend SQL write
  contract scripts, even though docs and plans treat those contracts as critical
  verification artifacts.

## Phase 2 - System Model

### Textual Architecture Map

Flutter client boundary:

- Riverpod owns dependency wiring.
- go_router owns route entry.
- UI reads from local Drift-backed repositories.
- Flutter owns ChordPro parsing, transposition, reader projection, and reader UI.
- Flutter may use capability state for UX affordances only.

Supabase backend boundary:

- Supabase Auth owns identity.
- Postgres owns canonical data.
- RLS and SQL helper functions own authorization.
- SQL RPCs own canonical write acceptance.
- SQL version checks own optimistic concurrency.
- Migrations and local backend flow go through repository scripts.

Drift local persistence boundary:

- Song catalog cache stores one active authenticated song snapshot per user and
  active organization.
- Song mutation rows store local song create/update/delete state.
- Planning projection stores normalized plan/session/session-item read data per
  user and active organization.
- Planning mutation rows store local planning write intent separately from the
  synchronized projection.

Sync queue and mutation persistence:

- Song writes use `cachedCatalogSongMutations`.
- Planning writes use `cachedPlanningMutations`.
- Planning mutation order is persisted via `orderKey`.
- Accepted planning writes can reconcile directly into local projection if the
  immediate full refresh fails and the same active planning boundary still owns
  the projection.

Authorization boundary:

- SQL `has_capability` is the authority.
- Flutter capability names must remain aligned with SQL helper names.
- Flutter prechecks are UX/local-first affordances only.

Optimistic concurrency boundary:

- Song update/delete RPCs require song `base_version`.
- Plan edits and session reorder use plan version.
- Session rename/delete and session-item add/delete/reorder use session version.
- Conflicts must surface explicitly; silent last-write-wins is not the MVP
  model.

Active-organization boundary:

- Current implementation calls `current_organization_ids` and picks the sorted
  first organization id.
- Planning can use the latest cached organization only as a cold-start fallback
  when no current boundary exists yet.
- Local data is scoped by user and organization, but active-org selection is not
  yet a first-class user choice.

ChordPro boundary:

- Backend stores raw `chordpro_source`.
- Flutter parses and renders ChordPro locally.
- Backend does not store rendered song projections.

Planning/session/session-item boundary:

- The current planning hierarchy is `plan -> session -> session_items`.
- Sessions belong directly to plans.
- Current session items are song-backed.
- A song may appear at most once within a session.

### Sources Of Truth

- Product and architecture: `README.md`, `docs/product/vision.md`,
  `docs/architecture/architecture.md`, ADRs.
- Domain: `docs/domain/domain-model.md`.
- Testing: `docs/testing/testing-strategy.md`.
- Workflow: `AGENTS.md`, `docs/workflows/development-workflow.md`,
  `docs/workflows/ai-development.md`.
- Slice history: `docs/specs/`, `docs/plans/`.
- Deferred correctness work: `docs/deferred/`.
- Backend behavior: `supabase/migrations/`, `supabase/seed/seed.sql`.
- Client behavior: `apps/lyron_app/lib/`.
- Verification entrypoints: `scripts/`, `.github/workflows/ci.yml`.

### Key Invariants

- Authorization is backend-enforced, not delegated to Flutter.
- Every local song and planning read is scoped by authenticated user and active
  organization.
- Local-first refresh failure must preserve usable local data.
- A completed full song summary-plus-source refresh replaces the active catalog
  snapshot.
- Planning projection and planning mutation store remain separate.
- Explicit sign-out removes authenticated local planning data and song catalog
  data.
- Planning session-expiry removes local planning data.
- Song session-expiry currently clears state but does not delete cached song
  catalog rows.
- Capability names in Flutter must match SQL capability names.
- Supabase CLI usage must go through repository wrapper scripts.

### Cross-System Contracts

- Flutter `Capability` enum codes mirror SQL `has_capability` strings:
  `canViewSongs`, `canEditSongs`, `canManageOrganizationMembers`,
  `canManageGroupMembers`, `canEditSessions`, `canManagePlans`.
- Flutter planning write mutations map to SQL RPCs:
  `create_plan`, `update_plan_fields`, `create_session`, `rename_session`,
  `delete_empty_session`, `reorder_plan_sessions`,
  `create_song_session_item`, `delete_session_item`,
  `reorder_session_items`.
- Flutter song mutations map to SQL RPCs:
  `create_song`, `update_song`, `overwrite_song_update`, `delete_song`,
  `overwrite_song_delete`.
- Supabase RLS and SQL functions are the canonical membership and capability
  boundary.
- Drift projections are local read models, not authorization sources.

## Phase 3 - Subsystem Trace Analysis

### 1. Auth/session Handling

Responsibility:

- Restore Supabase session.
- Watch auth state changes.
- Sign in and sign out.
- Classify null session after signed-in state as session expiration.

Entry points:

- `AppAuthController.restoreSession`
- `AppAuthController.signIn`
- `AppAuthController.signOut`
- `SupabaseAuthRepository`

Normal trace:

- `AppAuthController` subscribes to `watchSession`.
- `SupabaseAuthRepository` maps Supabase `Session` to `AppAuthSession`.
- Signed-in session updates app auth state.
- Providers react to signed-in state by refreshing song catalog and planning
  context.

Failure/offline trace:

- Null session from stream after signed-in state becomes `sessionExpired`.
- Planning controller deletes local planning data for the user.
- Song catalog controller clears state but does not delete local song cache on
  session expiry.

Invariants:

- Explicit sign-out should clear authenticated local access.
- Session-expiry policy should be intentional and documented.

Risk:

- Song and planning session-expiry cleanup are inconsistent.

Existing tests:

- Auth controller tests.
- App-level sign-out cache tests.

Missing tests:

- Song session-expiry cache clearing or intentional preservation.

### 2. Organization Membership And Active-Organization Scoping

Responsibility:

- Resolve active organization.
- Scope local reads/writes to authenticated user and organization.
- Use backend membership as source of truth.

Entry points:

- SQL `current_organization_ids`
- `activeOrganizationReaderProvider`
- `selectActiveOrganizationId`
- `ActivePlanningContextController`

Normal trace:

- Flutter calls `current_organization_ids`.
- Response ids are sorted.
- First id is selected.
- Song and planning contexts use that organization id.

Failure/offline trace:

- Song controller can fall back to latest cached organization on connectivity
  failure.
- Planning controller allows cached fallback only when no current planning
  boundary exists yet.
- Existing planning boundary is preserved during transient org-resolution
  failure.

Invariants:

- Local data must not leak across users or organizations.
- Active organization must be stable enough for sync boundaries.

Risk:

- Active organization is not a real user-selected active organization. It is a
  deterministic first organization fallback.

Existing tests:

- Planning context controller tests.
- Hidden organization integration coverage.
- Organization-boundary invalidation tests.

Missing tests:

- Multi-organization switching with explicit user selection.
- Stale active-organization state after membership change.

### 3. Song Catalog Local-First Read Path

Responsibility:

- Read song summaries and sources from local cache.
- Refresh full visible catalog from Supabase.
- Preserve cache on failed refresh.

Entry points:

- `SongCatalogController.refreshCatalog`
- `LocalFirstSongRepository`
- `DriftSongCatalogStore`
- `SupabaseSongRepository`

Normal trace:

- Verify session.
- Resolve organization.
- Fetch Supabase summaries.
- Fetch each song source.
- Replace local snapshot only after full summary/source success.
- UI reads local summaries/sources.

Failure/offline trace:

- If connectivity prevents verification or refresh and cache exists, state
  becomes offline-cached.
- Failed full refresh preserves previous snapshot.

Invariants:

- Incomplete refresh must not corrupt cache.
- Reads stay scoped by user and organization.

Risk:

- Song session-expiry leaves cache rows on disk, though inaccessible through
  cleared context.

Existing tests:

- Local-first authenticated song reader integration.
- Song catalog controller tests.
- Song catalog store tests.

Missing tests:

- Session-expiry song cache policy.

### 4. Song CRUD/write Path

Responsibility:

- Persist local song create/update/delete mutations.
- Sync mutations to Supabase RPCs.
- Classify conflicts, authorization failures, dependency failures, remote
  deletion, and connectivity failures.

Entry points:

- `SongLibraryService`
- `DriftSongMutationStore`
- `SongMutationSyncController`
- `SupabaseSongMutationRemoteRepository`
- SQL song RPCs

Normal trace:

- Create/update/delete records local mutation.
- UI/manual sync calls sync controller.
- Controller sends RPC.
- Backend enforces capability and OCC.
- Successful sync reconciles local row or deletes accepted deletion.

Failure/offline trace:

- Connectivity failure leaves mutation pending and stops loop.
- Version conflict becomes conflict state.
- Remote deletion is classified and persisted.
- Delete-sourced remote deletion can converge as accepted deletion.

Invariants:

- Authorization belongs to SQL.
- Deletion is blocked while session items reference a song.
- Conflict overwrite is explicit.

Risk:

- Backend song write contract script exists but is not visibly part of main CI
  gate.

Existing tests:

- Flutter local-first song CRUD integration.
- Song mutation sync controller tests.
- Supabase song mutation repository tests.
- `scripts/tests/song-crud-write-contract-test.sh`.

Missing tests/gate:

- `song-crud-write-contract-test.sh` should be run by full verify or CI.

### 5. Planning Read Path

Responsibility:

- Fetch backend planning payload for active organization.
- Persist normalized Drift projection.
- Serve local-first plan summaries and details.

Entry points:

- `PlanningSyncController`
- `SupabasePlanningRepository.fetchPlanningSyncPayload`
- `DriftPlanningLocalStore.replaceActiveProjection`
- `PlanningLocalReadRepository`

Normal trace:

- Active planning context changes.
- Previous organization projection is deleted when boundary changes.
- Controller fetches full visible planning payload.
- Store validates plan/session/item graph.
- Projection is atomically replaced.
- UI reads projection plus mutation overlay.

Failure/offline trace:

- Refresh failure preserves existing projection.
- Access state records failed refresh.

Invariants:

- Projection must be graph-consistent.
- One active organization projection is retained per user.

Risk:

- Active-org selection is fallback-based, not first-class.

Existing tests:

- Planning read integration.
- Planning sync controller tests.
- Planning local store tests.

Missing tests:

- Explicit org switching after real active-org feature.

### 6. Planning Local Mutation Path

Responsibility:

- Persist plan/session/session-item local write intent separately from
  synchronized projection.
- Merge pending mutations into read model.
- Sync pending mutations in order.

Entry points:

- `PlanningWriteService`
- `DriftPlanningMutationStore`
- `PlanningLocalReadRepository`
- `PlanningMutationSyncController`

Normal trace:

- Service requires matching active context.
- It reads current local detail to capture base version and origin snapshot.
- Mutation store records pending mutation with order key.
- Read repository overlays pending mutations.
- Sync controller sends mutations to backend in order.

Failure/offline trace:

- Connectivity failure leaves mutation pending and breaks loop.
- Authorization/dependency/remote-missing/conflict statuses become explicit
  failed states.
- Retry refreshes first, rebases base version where possible, then retries.

Invariants:

- Projection rows are not directly mutated by local write intent.
- Failed authorization/conflict must not remain silently overlaid as normal
  pending state.

Risk:

- Backend planning write contract script is not part of main gate.

Existing tests:

- Planning write service tests.
- Planning mutation store tests.
- Planning mutation sync controller tests.
- Local-first planning write integration.
- `scripts/tests/planning-write-contract-test.sh`.

Missing tests/gate:

- `planning-write-contract-test.sh` should be run by full verify or CI.

### 7. Session Create/Rename/Delete/Reorder

Responsibility:

- Local-first session collection edits.
- Backend-enforced session write authorization and OCC.

Entry points:

- `PlanningWriteService.createSession`
- `PlanningWriteService.renameSession`
- `PlanningWriteService.deleteSession`
- `PlanningWriteService.reorderSessions`
- SQL `create_session`, `rename_session`, `delete_empty_session`,
  `reorder_plan_sessions`

Normal trace:

- Local mutation is recorded.
- Local read overlay updates session list immediately.
- Sync RPC re-checks capability and base version.
- Accepted write refreshes projection or reconciles canonical data.

Failure/offline trace:

- Empty-session delete is checked locally for UX.
- Backend re-checks empty-session delete before accepting.
- Reorder requires valid full permutation.
- Conflicts and invalid permutations become failed states.

Invariants:

- Session organization scope inherits from owning plan.
- Session delete only allowed for empty sessions.
- Session reorder is plan-version scoped.

Risk:

- SQL contract gate not automatic.

### 8. Session-Item Add/Delete/Reorder

Responsibility:

- Local-first song-backed session item edits.
- Backend-enforced duplicate-song, visibility, and OCC rules.

Entry points:

- `PlanningWriteService.addSongSessionItem`
- `PlanningWriteService.deleteSessionItem`
- `PlanningWriteService.reorderSessionItems`
- SQL `create_song_session_item`, `delete_session_item`,
  `reorder_session_items`

Normal trace:

- Add checks local duplicate and visible song.
- Mutation captures session base version.
- Local overlay updates plan detail.
- RPC checks `canEditSessions`, song visibility, duplicate song, session base
  version, and permutation.

Failure/offline trace:

- Connectivity leaves pending mutation.
- Duplicate/out-of-scope/dependency errors become failed states.

Invariants:

- A session contains a given song at most once.
- Song-backed session item must reference same-organization visible song.

Risk:

- SQL contract gate not automatic.

### 9. Offline Relaunch Behavior

Responsibility:

- Native offline relaunch remains acceptance path.
- Automated tests prove persistent reopen behavior.

Evidence:

- README documents native manual validation.
- Manual validation scripts cache Supabase env for offline relaunch.
- Flutter integration tests cover persistent cache reopen.

Risk:

- Browser relaunch remains best-effort and is documented as such.

Missing tests:

- Native true offline relaunch is manual, not fully automated.

### 10. Sync/Retry/Reconciliation Behavior

Responsibility:

- Keep local writes durable across refresh failure and relaunch.
- Classify failures.
- Avoid losing accepted writes when refresh fails.

Evidence:

- Planning sync controller reconciles accepted mutation when refresh fails and
  active boundary still matches.
- Song sync controller persists conflict and remote-delete classification.

Risk:

- Unified manual sync is deferred.

Deferred reference:

- `docs/deferred/2026-04-29-unified-manual-sync.md`

### 11. Drift Schema And Migrations

Responsibility:

- Persist local song catalog, song mutations, planning projection, and planning
  mutations.

Evidence:

- Song tables use user+organization scoping.
- Planning tables use user+organization scoping.
- Store validation checks projection graph uniqueness and parent references.

Risk:

- Any future table migration needs explicit migration safety tests.

### 12. Supabase Schema, SQL Functions, RLS Policies

Responsibility:

- Canonical data, authorization, RLS, write acceptance, OCC.

Evidence:

- RLS enabled on organizations, groups, memberships, songs, plans, sessions,
  session_items, attachments.
- `current_organization_ids` and `has_capability` are security definer helper
  functions.
- Write RPCs perform capability checks and version checks.
- Slug uniqueness constraints exist for songs, plans, and sessions.

Risk:

- Backend contract scripts must be CI-gated to keep this boundary safe.

### 13. Verification Scripts And CI Gates

Responsibility:

- Provide local and CI quality gates.

Evidence:

- `scripts/verify.sh` runs Dart format, Flutter analyze, Flutter tests,
  migration lint, db reset, demo provisioning, selected backend integration
  tests, and manual-validation script contract test.
- `.github/workflows/ci.yml` runs verify and migration lint jobs.

Risk:

- Explicit SQL write contract scripts are not included in the main gate.

## Phase 4 - Cross-System Risk Audit

### Flutter Assuming Authorization

No direct authorization bypass was found. Flutter performs UX/local prechecks,
but SQL RPCs and RLS remain authoritative.

### Capability-Name Drift

Flutter capability names match SQL helper cases by static inspection:

- `canViewSongs`
- `canEditSongs`
- `canManageOrganizationMembers`
- `canManageGroupMembers`
- `canEditSessions`
- `canManagePlans`

Risk remains: there is no dedicated generated contract tying Flutter enum names
to SQL helper cases.

### Drift Schema Vs Supabase Schema Mismatch

No immediate blocking mismatch found. Drift stores projections, not full
canonical schemas. Important version and slug fields are represented in local
read/mutation models.

### Local Cache Leaking Across Users Or Organizations

No direct leak found. Tables and reads include user and organization filters.

Residual risk:

- Session-expiry song cache remains on disk after context clears.

### Stale Active Organization State

Risk exists because active organization is selected by sorted first membership
id, not user intent.

### Hidden-Organization Visibility Leaks

Seed fixtures and integration tests include hidden organization data. No direct
code leak found by static inspection.

### Retry/Idempotency Bugs

Planning retry refreshes first and rebases base version where possible. Song
remote-delete handling is persisted. No proven bug found, but backend write
contract gate must be automatic.

### Optimistic Concurrency Violations

Backend RPCs enforce base version for update/delete/reorder families. No proven
violation found.

### Failed Refresh Corrupting Local State

Song refresh replaces snapshot only after complete summary/source fetch.
Planning projection replace is atomic and validates graph. No proven corruption
found.

### Sign-Out Not Clearing Sensitive Local Data

Explicit sign-out clears song catalog and planning data. Session expiry clears
planning data but not song cache rows.

### Offline Relaunch Differences Between Native And Web

Documented: native is acceptance path; web is best-effort.

### Migration Fragility

Migration lint exists. Specific contract regression scripts exist. Main gap is
gate integration for write contract scripts.

### Seed/Demo Fixture Drift

Seed includes demo and hidden organizations. Demo auth provisioning is scripted
and regression-tested.

### Scripts Bypassing Repository Wrappers

No broad direct Supabase CLI bypass found. Scripts generally call
`./scripts/supabase.sh` or `SUPABASE_SCRIPT`.

## Phase 5 - Documentation Drift Audit

Documents inspected:

- `README.md`
- `docs/product/vision.md`
- `docs/domain/domain-model.md`
- `docs/architecture/architecture.md`
- `docs/testing/testing-strategy.md`
- `docs/workflows/development-workflow.md`
- `docs/workflows/ai-development.md`
- `docs/specs/`
- `docs/plans/`
- `docs/deferred/`

Findings:

- `README.md` and `docs/testing/testing-strategy.md` describe strong backend
  verification expectations. The actual main gate does not visibly run the SQL
  write contract scripts.
- Workflow docs define status labels as `Draft`, `In progress`,
  `Implemented`, and `Abandoned`, but some docs use non-canonical labels such
  as `Delivered` and `Proposed`.
- Some implementation plans begin with agent execution instructions instead of
  a status note directly under the title.
- Deferred work is visible and useful. Notable active deferred items:
  `docs/deferred/2026-04-29-unified-manual-sync.md` and
  `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md`.

Important MD files referenced by audit:

- `docs/specs/2026-04-19-song-list-plan-song-pick-ux.md`
- `docs/plans/2026-04-19-song-list-plan-song-pick-ux.md`
- `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md`
- `docs/plans/2026-04-22-song-reader-capo-and-instrument-display.md`
- `docs/specs/2026-04-24-planning-workspace-ui.md`
- `docs/plans/2026-04-28-planning-workspace-ui.md`
- `docs/deferred/2026-04-08-offline-song-crud.md`
- `docs/deferred/2026-04-22-song-reader-chordpro-modulation.md`
- `docs/deferred/2026-04-29-unified-manual-sync.md`
- `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md`

## Phase 6 - Test And Verification Audit

Inspected:

- `./scripts/verify.sh`
- `./scripts/run-tests.sh`
- `./scripts/run-ci-locally.sh`
- `./scripts/check-migrations.sh`
- manual-validation scripts
- Flutter test inventory
- integration test inventory
- migration and backend contract scripts

Existing coverage:

- Flutter full test suite is run by `scripts/verify.sh`.
- Migration lint is run by `scripts/check-migrations.sh`.
- Backend song read and planning read integration tests run with local Supabase.
- Local-first song and planning read reopen behavior is covered.
- Local-first planning write persistence has an integration test.
- Backend write contract scripts exist for song CRUD and planning writes.

Missing or weak gate coverage:

- RLS/write contract scripts are not visibly included in `scripts/verify.sh` or
  CI.
- Organization switching needs stronger coverage once explicit active-org
  selection exists.
- Song session-expiry cache behavior needs a dedicated test.
- Unified manual sync for mixed song/planning queues is deferred.

Tests specifically called out for future hardening:

- RLS scope isolation
- organization switching
- sign-out data clearing
- session-expiry data clearing
- offline relaunch
- failed refresh cache preservation
- retry/idempotency
- optimistic concurrency conflicts
- schema migration safety
- capability mismatch
- hidden organization data isolation
- local mutation replay ordering

## Phase 7 - Findings Classification

### P0

No proven P0 issue found by static inspection.

### P1-1: Backend SQL Write Contract Tests Are Not In Main Gate

Severity:

- P1

Affected files:

- `scripts/verify.sh`
- `.github/workflows/ci.yml`
- `scripts/tests/planning-write-contract-test.sh`
- `scripts/tests/song-crud-write-contract-test.sh`
- `README.md`
- `docs/testing/testing-strategy.md`

Exact evidence:

- `scripts/verify.sh` runs selected Flutter integration tests and
  `local-first-manual-validation-scripts-test.sh`, but does not call
  `planning-write-contract-test.sh` or `song-crud-write-contract-test.sh`.
- CI verify job runs only `./scripts/verify.sh`.
- CI migration job runs only `./scripts/check-migrations.sh`.

Reasoning path:

- Backend write RPCs are the canonical authorization and OCC boundary.
- Dedicated SQL contract scripts exist and are referenced in slice plans.
- If those scripts are not part of the main merge gate, SQL/RLS/OCC regressions
  can merge despite docs claiming strong backend verification.

Reproduction or verification scenario:

- Introduce a regression in a planning write RPC that only
  `planning-write-contract-test.sh` catches.
- Run CI as currently wired.
- Regression may pass if Flutter tests do not exercise the SQL edge.

Minimal safe fix:

- Add both backend write contract scripts to `scripts/verify.sh` after local
  Supabase setup, or add a dedicated CI job that runs them.
- Update `scripts/tests/verify-test.sh`.
- Keep docs aligned with the chosen gate.

Required tests:

- `bash scripts/tests/verify-test.sh`
- `./scripts/verify.sh`
- `bash scripts/tests/planning-write-contract-test.sh`
- `bash scripts/tests/song-crud-write-contract-test.sh`

Worker suitability:

- Mini worker not recommended. This touches release gates for RLS/OCC/write
  correctness.

### P1-2: Active Organization Is A Sorted First-Organization Fallback

Severity:

- P1

Affected files:

- `apps/lyron_app/lib/src/application/providers.dart`
- `apps/lyron_app/lib/src/application/planning/active_planning_context_controller.dart`
- `docs/architecture/architecture.md`
- `docs/domain/domain-model.md`
- `README.md`

Exact evidence:

- `selectActiveOrganizationId` sorts organization ids and returns the first.
- `activeOrganizationReaderProvider` calls SQL `current_organization_ids`.

Reasoning path:

- Product docs treat active-organization scoping as critical.
- Current implementation has deterministic fallback behavior, not a user-owned
  active organization model.
- Local scoping is still user+org safe, but multi-org behavior can surprise
  sync and UX flows.

Reproduction or verification scenario:

- User has memberships in two organizations.
- Backend returns both organization ids.
- Flutter chooses lexicographically first organization, regardless of user
  intent.

Minimal safe fix:

- Either document the current first-organization behavior as the MVP fallback,
  or introduce explicit active organization selection/persistence.

Required tests:

- Multi-org active organization selection.
- Organization switching invalidates previous projection.
- Hidden organization remains inaccessible.
- Stale organization resolution does not switch boundaries unexpectedly.

Worker suitability:

- Mini worker not recommended. This is an architecture and isolation boundary.

### P1-3: Song Cache Session-Expiry Cleanup Differs From Planning

Severity:

- P1

Affected files:

- `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`
- `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`
- `README.md`
- `docs/architecture/architecture.md`
- `docs/testing/testing-strategy.md`

Exact evidence:

- `handleExplicitSignOut` in song catalog deletes catalogs for the user.
- `handleSessionExpired` in song catalog clears state but does not delete
  cached song rows.
- Planning `handleSessionExpired` deletes planning data for the user.

Reasoning path:

- Explicit sign-out cleanup is clear.
- Planning treats session expiry as a local data cleanup boundary.
- Song catalog treats session expiry as state-only cleanup.
- The difference may be intentional for offline behavior, but it is not clearly
  documented as a durable policy.

Reproduction or verification scenario:

- Populate song cache.
- Expire Supabase session through auth state stream.
- Song controller clears context but Drift rows remain for that user.

Minimal safe fix:

- Decide whether session expiry should purge song cache.
- Implement and test if purge is required.
- If preservation is required for offline UX, document exact access policy and
  threat model.

Required tests:

- Song catalog session-expiry cache cleanup or preservation test.
- Sign-in-after-expiry behavior.
- No local read without active authenticated context.

Worker suitability:

- Mini worker not recommended. This touches auth/session and sensitive local
  data policy.

### P1-4: Documentation And Verification Drift Around Planning Write Contract

Severity:

- P1

Affected files:

- `README.md`
- `docs/testing/testing-strategy.md`
- `scripts/verify.sh`
- `scripts/tests/planning-write-contract-test.sh`

Exact evidence:

- Docs describe backend-backed planning write contract expectations.
- `scripts/verify.sh` does not visibly run the planning write SQL contract
  script.

Reasoning path:

- Future agents may trust docs and skip a critical manual script.
- Repository source of truth becomes ambiguous.

Reproduction or verification scenario:

- Run only `./scripts/verify.sh` and assume planning SQL write contract passed.
- It did not run unless added elsewhere.

Minimal safe fix:

- Prefer adding the script to the gate.
- If not, update docs to say it is a separate required command for backend write
  changes.

Required tests:

- `bash scripts/tests/verify-test.sh`
- `bash scripts/tests/planning-write-contract-test.sh`

Worker suitability:

- Docs-only clarification is mini-worker safe.
- Gate change needs stronger review.

### P2-1: Spec/Plan Status Vocabulary Drift

Severity:

- P2

Affected files:

- `docs/specs/2026-04-19-song-list-plan-song-pick-ux.md`
- `docs/plans/2026-04-19-song-list-plan-song-pick-ux.md`
- `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md`
- `docs/plans/2026-04-22-song-reader-capo-and-instrument-display.md`
- possible other recent plans with missing status lines

Exact evidence:

- Workflow allows only `Draft`, `In progress`, `Implemented`, and `Abandoned`.
- Some docs use `Delivered` and `Proposed`.
- Some plans place agent instructions where status should be.

Reasoning path:

- Status labels help future agents distinguish historical records from active
  source-of-truth docs.
- Non-canonical labels reduce workflow clarity.

Minimal safe fix:

- Normalize status labels.
- Consider a lightweight status lint script.

Required tests:

- Manual `rg` check or new script if added.

Worker suitability:

- Mini worker safe.

### P2-2: Worktree Was On Main During Audit

Severity:

- P2

Affected files:

- none

Exact evidence:

- `git branch --show-current` returned `main` during read-only audit.

Reasoning path:

- Read-only audit is allowed.
- Any implementation change from `main` would violate `AGENTS.md`.

Minimal safe fix:

- Create a conventional branch before modifications.

Required tests:

- `git status --short --branch`

Worker suitability:

- Mini worker safe.

## Phase 8 - Remediation Plan

### Task 1: Add Backend Write Contract Gate

Files:

- `scripts/verify.sh`
- `scripts/tests/verify-test.sh`
- optionally `.github/workflows/ci.yml`
- optionally `docs/testing/testing-strategy.md`

Acceptance criteria:

- Full verify or CI runs:
  `bash scripts/tests/planning-write-contract-test.sh`
  and `bash scripts/tests/song-crud-write-contract-test.sh`.
- Mock verify test proves the ordered gate.
- README/testing docs match the actual command sequence.

Test commands:

- `bash scripts/tests/verify-test.sh`
- `./scripts/verify.sh`
- `bash scripts/tests/planning-write-contract-test.sh`
- `bash scripts/tests/song-crud-write-contract-test.sh`

Escalation:

- Use stronger model. This affects RLS/OCC/release gate correctness.

### Task 2: Decide Active-Organization Contract

Files:

- `docs/specs/<new-active-organization-scope>.md`
- `docs/plans/<new-active-organization-scope>.md`
- `docs/architecture/architecture.md`
- `docs/domain/domain-model.md`
- `apps/lyron_app/lib/src/application/providers.dart`
- tests under `apps/lyron_app/test/application/`

Acceptance criteria:

- Current first-org fallback is documented as MVP behavior, or explicit active
  org selection is implemented.
- Multi-org behavior has tests.
- Organization-boundary invalidation remains intact.

Test commands:

- targeted Flutter tests for active context
- `flutter test`

Escalation:

- Use stronger model. This is architecture and isolation-sensitive.

### Task 3: Align Song Session-Expiry Cache Policy

Files:

- `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`
- song catalog controller tests
- app-level auth/cache tests
- `README.md`
- `docs/architecture/architecture.md`
- `docs/testing/testing-strategy.md`

Acceptance criteria:

- Session-expiry behavior is explicit and tested.
- Song and planning cleanup policies are either aligned or intentionally
  differentiated in docs.
- No unauthenticated read path can access cached authenticated song data.

Test commands:

- targeted song catalog controller tests
- `flutter test`

Escalation:

- Use stronger model. This is auth/session and local data policy.

### Task 4: Normalize Spec/Plan Status Labels

Files:

- `docs/specs/2026-04-19-song-list-plan-song-pick-ux.md`
- `docs/plans/2026-04-19-song-list-plan-song-pick-ux.md`
- `docs/specs/2026-04-22-song-reader-capo-and-instrument-display.md`
- `docs/plans/2026-04-22-song-reader-capo-and-instrument-display.md`
- other docs found by status scan

Acceptance criteria:

- All specs/plans have a status note directly under the title.
- Labels use only `Draft`, `In progress`, `Implemented`, or `Abandoned`.

Test commands:

- `rg -n "Status: (Delivered|Proposed)" docs/specs docs/plans`
- optional status lint script

Escalation:

- Mini worker acceptable.

### Task 5: Re-Audit After Fixes

Files:

- audit checklist plus changed files

Acceptance criteria:

- Full verify passes.
- Backend write contract scripts pass.
- Updated docs match implementation.
- Active-org and session-expiry findings are resolved or explicitly deferred.

Test commands:

- `./scripts/verify.sh`
- `bash scripts/tests/planning-write-contract-test.sh`
- `bash scripts/tests/song-crud-write-contract-test.sh`
- `./scripts/run-ci-locally.sh`

Escalation:

- Use stronger model for failures in SQL/RLS/sync/auth.

## Resumption Checkpoint

CHECKPOINT:

- Phase: Final audit checkpoint recorded
- Subsystem: repo rules, architecture model, auth/session, active organization,
  song catalog, song CRUD, planning read/write, SQL/RLS, CI/verification, docs
- Files inspected: primary sources listed in Scope
- Findings so far: no proven P0; P1 gaps in SQL write contract gate,
  active-organization model, song session-expiry cleanup policy, and
  docs/verification drift; P2 status label drift and main-branch implementation
  risk
- Open questions: whether project wants first-org fallback as documented MVP or
  an explicit active-org selector; whether song session expiry should purge
  cache or preserve offline data under a documented policy
- Next step: implement remediation Task 1 first, because it strengthens the
  backend authorization/OCC gate before further agentic work
