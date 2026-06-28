# Testing Strategy

## Principles

1. TDD is mandatory for behavior changes and new implementation work.
2. The repository must describe the intended test pyramid and quality gates.
3. All tests must be green before merge.
4. Critical offline, authorization, and sync behavior must be covered explicitly.
5. Song-reader slices must cover the supported ChordPro subset and recoverable parser warnings explicitly.

## Test Layers

### Unit Tests

Cover:

- Domain invariants
- Capability mapping behavior in pure application logic
- Sync orchestration decisions
- Authenticated catalog snapshot selection and refresh-state mapping
- ChordPro parsing and metadata mapping rules
- Song repository boundary behavior and backend summary/source mapping
- Song CRUD orchestration behavior, including authorization-failure handling, OCC conflict branching, slug reconciliation, and `pending_delete` filtering
- Song CRUD remote-delete convergence behavior, including persisted remote-deletion classification, same-id recreate routing, delete-sourced accepted convergence, and no-fetch discard when the canonical row is gone
- Planning repository boundary behavior, including plan ordering and plan-detail mapping
- Planning write orchestration behavior, including optimistic-concurrency base-version capture, provisional slug allocation, retryable failed mutations, empty-session delete enforcement, and session/session-item collection-edit compaction
- Planning sync-correctness regression coverage: exactly-once accepted-marker (already-accepted mutation reconciled/cleared, not re-sent), single-flight coalescing of concurrent `syncPendingMutations`, one batch refresh for N mutations (and zero refresh when none accepted), offline discard/retry of stuck mutations, actionable-merge keeping failed/conflict planEdits visible without blanking unset fields, and `PlanningMutationReconciler` characterization tests across all mutation kinds
- Slug-routing boundary behavior for route resolution, including explicit not-found surfaces for missing song, plan, and session slugs
- Slug-routing boundary behavior for scoped reader song resolution within a session, including the assumption that a song appears at most once per session
- Slug-routing boundary behavior for route generation, including canonical slug URLs and no id-based fallback when the canonical song slug is unavailable at the presentation edge
- Parser diagnostics and warning policy for the supported ChordPro subset

Current foundation baseline:

- capability code stability tests in Flutter
- offline policy tests in Flutter

Unified sync coverage includes:

- `UnifiedSyncOverview` aggregator unit tests for header status precedence (red wins over yellow wins over green), reason-code mapping (`pending_local`, `sync_failed`, `conflict`, `authorization_denied`, `dependency_blocked`, `remote_missing`), and plan-level grouping including failed plan creates, orphan session-item fallback rows, and the `planTitles` → mutation name → slug → origin snapshot title precedence chain.
- `UnifiedManualSyncController` unit tests for in-order song-sync → catalog-refresh → planning-sync → planning-refresh execution, single-flight semantics with a coalesced queued rerun, and step-isolated failure reporting via `UnifiedManualSyncRunResult`.
- Song-only, planning-only, and mixed-queue unified sync tests for the manual command.
- `OnlineTransitionDetector` unit tests for catalog and planning offline-to-online transitions, including `triggerWhenClean=false` suppression when no unsynced work exists.
- `ForegroundSyncListener` unit test for resume-only firing.
- Header sync control widget tests for green/yellow/red label and color, and popup widget tests for empty state, song row + plan conflict row rendering, `Sync now` button, and specific reason chips for `conflict`, `authorization_denied`, `dependency_blocked`, `remote_missing`, and `sync_failed`.
- Sign-out warning routing through `unifiedSyncOverviewProvider.hasUnsyncedWork` instead of the legacy per-domain providers.
- Refresh-failure preservation test confirming a failed catalog refresh keeps the header green and surfaces `stale` freshness without changing the primary header color.

Active local-first regression coverage includes:

- Song session-expiry cache policy regression coverage for active catalog context clearing, cached read blocking, persisted cache row retention, and re-sign-in restoration.
- Provider/local-store accepted-write fallback regression coverage for planning mutations when remote refresh fails.
- Song pending mutation persistence across Drift reopen for pending create, pending update, pending delete, and overlay replay behavior.

### Adversarial Offline/Sync Validation

The local-first-validation slice (`docs/specs/2026-06-29-local-first-validation.md`,
`docs/plans/2026-06-29-local-first-validation.md`) added a dedicated adversarial suite under
`apps/lyron_app/test/offline/adversarial/` plus two skip-gated integration suites, targeting
the correctness/robustness findings in `docs/architecture/repository-review-2026-06-22.md`
(`LF-1` through `LF-8`, `LF-T4`, `LF-T6`, `LF-T7`). Each suite proves or characterizes a
specific finding:

- `planning_fault_injection_test.dart` — `LF-1` (crash between backend acceptance and local
  clear does not re-send an already-accepted mutation) and `LF-2` (a partial-RPC-success
  batch followed by a failed refresh still reconciles correctly on the next run). Both were
  already shipped by ADR-019 and are validated, not newly fixed, by this suite.
- `song_single_flight_test.dart` — `LF-3` for the song sync path. Added a single-flight guard
  to `SongMutationSyncController.syncPendingSongs` (mirroring the existing planning guard from
  ADR-019) so concurrent sync triggers coalesce into one in-flight run instead of double-sending.
- `planning_merge_visibility_test.dart` — `LF-4` (a conflicted edit stays visible in the merged
  read instead of silently reverting) and `LF-5` (a partial edit preserves untouched fields
  instead of blanking them), both validating existing ADR-019 behavior; and `LF-6` (the merge
  now dedups a duplicate offline song-add by `songId`, a fix, not just a validation).
- `planning_reconcile_nullfield_test.dart` — `LF-8`. The reconciler now throws a typed
  `ReconcileFieldError` for a null required-on-create field instead of silently coercing it to
  `''`/`0`, replacing the prior silent-corruption path with an explicit, testable failure.
- `planning_migration_test.dart` — `LF-T7` (planning half): a pending planning mutation
  survives a Drift database close/reopen. Validates existing behavior.
- `song_catalog_migration_test.dart` — `LF-T7` (catalog half): `SongCatalogDatabase` now
  declares an explicit `MigrationStrategy` (previously `schemaVersion 2` with none) and a
  pending song mutation is confirmed to survive close/reopen. This is a hardening fix, not
  just a validation.
- `storage_pressure_probe_test.dart` — `LF-T4` probe. Confirms a storage write failure
  propagates as an exception instead of being silently swallowed. Characterizes current
  behavior; the full size-monitor/eviction policy remains deferred
  (`docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`).
- `clock_skew_probe_test.dart` — `LF-T6` probe. Adds an injectable clock seam to
  `PlanningMutationReconciler` (default wall-clock behavior unchanged) and confirms an
  injected skewed clock flows straight through into reconciled timestamps uncorrected. A
  server-clock anchor remains deferred (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`).
- `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart` — `LF-T1`
  scenario: offline edit → relaunch → reconnect → sync, skip-gated on a live local Supabase
  stack. Faithfully wired but unverified against a running stack
  (`docs/deferred/2026-06-29-integration-live-stack-verification.md`).
- `apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart` — two-device
  concurrent-edit conflict matrix, skip-gated. Rename-vs-rename, reorder-vs-reorder, and
  add-same-song-twice pairs are fully wired; edit-vs-remote-delete and
  partial-edit-vs-full-edit pairs are structure-only pending live error-code/semantics
  confirmation (`docs/deferred/2026-06-29-integration-live-stack-verification.md`).

### Widget Tests

Cover:

- Route-level screens
- Empty, loading, and failure states
- Capability-driven UX affordances
- Offline indicators and conflict surfaces
- Song CRUD flows, including delete-blocked messaging for referenced songs and sign-out warnings for unsynced mutations
- Persistent song-catalog status surfaces for online, offline, refreshing, and refresh-failed modes
- Song list and reader controls, including view mode, transposition, font scaling, and warning surfaces
- Reader zoom gesture coverage: two-pointer pinch increases font scale while single-finger drag still scrolls (verified via scroll-position assertion, not only callback absence); double-tap fit-to-screen and restore cycle; full-width scrollbar layout confirming the scroll view spans the full viewport width at any content width
- Reader zoom seed-on-open: store provider overridden with an in-memory fake; `readerUserIdProvider` overridden with a test identity; font size on rendered text asserted to reflect the seeded value
- Local key-value preference stores (shared_preferences): unit-tested via `SharedPreferences.setMockInitialValues` for read/write roundtrip, per-key isolation, and null-on-miss; production stores exposed behind a Riverpod interface for override in widget tests
- Planning list/detail loading, empty, and failure states plus signed-in navigation affordances into planning
- Planning create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder flows, including failed-mutation review surfaces and sign-out warnings when planning mutations remain unsynced
- Test environment stability via mandatory persistence stubbing in all `ProviderScope` overrides to prevent real Drift database instantiation and associated CI race conditions.
- Async safety verification via post-await `context.mounted` checks in all repository-interacting widgets.
- Route-level slug resolution behavior for songs, plans, and session-scoped reader entry, including canonical slug URLs and explicit not-found behavior
- Session-scoped reader tombstone behavior, including preserved planning title precedence and deleted-song copy when the canonical song row is gone

### Integration Tests

Cover:

- App bootstrap and routing
- Local-first flows
- Sync queue lifecycle
- Offline song create, update, delete, sync, and conflict-resolution flows
- Remote delete versus local pending update/delete convergence flows plus session-scoped reader tombstone behavior after canonical song removal
- Auth session bootstrap against test doubles or integration backends
- Authenticated backend song reads against the local Supabase stack, including organization-scope isolation
- Authenticated backend planning reads against the local Supabase stack, including ordered plan/session expansion and hidden-organization isolation
- Persistent cache reopen from the latest authenticated cached catalog in automation, plus cache removal on explicit sign-out
- Persistent planning-cache reopen for the active organization in automation, plus cache removal on explicit sign-out and refresh-failure offline reuse
- Local-first planning write persistence across database reopen, merged local planning write visibility for session and session-item collection edits, and explicit sign-out cleanup for both planning projection and planning mutations

### Backend Verification

Cover:

- Migration validity
- Migration application in a local Supabase stack through `./scripts/supabase.sh`
- Slug-column backfill and uniqueness verification for songs, plans, and sessions
- SQL function behavior
- RLS policy expectations
- Song write authorization enforcement for `canEditSongs`
- Planning write authorization enforcement for plan create/edit, session create/rename/delete/reorder, and song-backed session-item add/delete/reorder RPCs
- Planning optimistic-concurrency checks for plan/session update, delete, and collection-reorder RPCs
- Planning empty-session delete rejection when `session_items` still exist
- Planning duplicate-song rejection for session-item add and active-organization song-visibility enforcement for song-backed session-item creation
- Delete rejection while `session_items` still reference the song, plus attachment cleanup after accepted song deletion
- Song remote-delete backend behavior, including same-id recreate authorization/output and accepted delete convergence when the target row is already gone
- Seed script idempotency where applicable
- Local demo auth provisioning through `./scripts/provision-local-demo-user.sh`
- Regression coverage for repeated local demo auth provisioning where workflow scripts depend on idempotency
- Migration regression coverage for repair paths that must succeed on previously duplicated local membership data

## Pre-Merge Quality Gates

- `dart format --set-exit-if-changed`
- `flutter analyze`
- `flutter test`
- `./scripts/check-migrations.sh`
- local Supabase reset and demo auth provisioning when backend-backed slices change
- authenticated backend integration coverage for real Supabase song reads
- authenticated backend integration coverage for real Supabase planning reads when the planning slice changes
- local-first authenticated reader integration coverage for persistent cache reopen, hard replace, periodic refresh failure cache preservation, and explicit sign-out
- local-first authenticated planning integration coverage for persistent cache reopen, ordered detail reuse, refresh-failure cache preservation, organization-boundary invalidation, and explicit sign-out
- local-first planning write integration coverage for persisted pending mutations, merged local plan/session/session-item writes, and explicit sign-out cleanup

`./scripts/check-migrations.sh` is the canonical migration lint entrypoint for both local development and CI. It starts or reuses local Supabase through the repository-managed wrapper before invoking `db lint`, so migration verification does not depend on hidden workflow-specific database bootstrap steps.

The slug-routing slice adds a dedicated backend regression script under `scripts/tests/` that resets local Supabase and verifies the new slug columns, backfilled seed values, and scoped uniqueness constraints against the running database. Keep that style of verification close to the migration slice so route changes do not silently drift from database reality.

`./scripts/backend-write-contracts.sh` is the canonical backend SQL write-contract regression gate. It bootstraps one local Supabase fixture, then runs the planning and song CRUD contract suites serially so authorization, optimistic concurrency, dependency rejection, duplicate handling, and delete semantics stay merge-gated.

`./scripts/verify.sh` is the preferred local entrypoint because it runs the Flutter checks first, delegates migration lint bootstrap to `./scripts/check-migrations.sh`, runs `./scripts/backend-write-contracts.sh` unless explicitly told to skip that block, then resets the local database and runs the manual-validation script contract test plus the authenticated backend song-reading, local-first authenticated reader, authenticated planning read, and local-first planning read integration tests with repository-discovered `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SERVICE_ROLE_KEY` values where required. The backend-backed gate now proves SQL write contracts, manual refresh and periodic refresh against the real local Supabase stack, the planning read path against the same local stack, persistent cache reopen behavior plus periodic refresh failure cache preservation and explicit sign-out cleanup after database close/reopen for both song and planning reads. Native manual validation still covers true offline relaunch acceptance. Use `./scripts/verify.sh --skip-migrations` only when the change is confined to app and documentation work and does not affect backend-backed song reading, backend-backed planning reads, local-first planning reads, planning write contracts, or local Supabase workflow behavior. `--skip-backend-write-contracts` is reserved for CI split-job parity and should not replace the full local gate.

## AI-Assisted Development Rules

- AI may accelerate implementation, but it does not replace tests.
- If a new behavior is introduced, at least one test must demonstrate the intended behavior.
- Repository documentation must be updated when tests reveal changed assumptions.
- If backend tooling is unavailable locally, CI must still keep the corresponding verification path enforced, and pull requests must not bypass the backend-backed `./scripts/verify.sh` gate for the authenticated song-reader and local-first planning read slices.
