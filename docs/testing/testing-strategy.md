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
- `storage_pressure_contract_test.dart` — `LF-T4`, promoted from characterization probe
  (`storage_pressure_probe_test.dart`) to enforced contract now that the mutation budget
  and eviction policy have landed (ADR-028). Drives the full chain against a
  `QueryExecutor` decorator that fails every INSERT: storage failure → droppable catalog
  sources evicted → one retry → a typed `LocalStorageWriteFailure` propagates; the failed
  mutation is confirmed absent from a subsequent read, ruling out a partial commit.
- `planning_squash_contract_test.dart` — `LF-T3`. Pins that folding repeated intent into
  one row per aggregate preserves exactly-once sync (ADR-019) and OCC base-version
  semantics: a squashed record keeps the base version and origin snapshot captured by the
  *first* local edit, not a later one (fixing a prior inconsistency where the reorder paths
  already did this but `planEdit`/`sessionRename`/`sessionDelete`/`sessionItemDelete` let a
  later draft rebase the stored base version, which would have silently suppressed a real
  conflict). Also pins that collapsing a still-pending `sessionCreate` deletes that
  session's pending `session_item` and `session_item_order` mutations in the same
  transaction, so nothing is left behind that could only ever fail `dependencyBlocked`.
- `test/application/storage/local_storage_budget_test.dart`,
  `planning_storage_accountant_test.dart`, `local_storage_monitor_test.dart` — the
  content-derived footprint and pressure-classification contracts behind ADR-028: bytes
  grow with mutation/projection content and shrink on `clearMutation`, pressure classifies
  `ok`/`warning`/`critical` at the mutation and total thresholds independently, and
  measurement is scoped per `(userId, organizationId)`.
- `test/application/storage/song_catalog_evictor_test.dart` — the eviction protection
  contracts: droppable sources (no pending song mutation) are freed and the freed byte
  estimate matches the before/after delta; a source backing a pending song mutation is
  never dropped; summaries and pending song mutations are never dropped; eviction is
  idempotent (a second pass frees nothing); and the multi-tenant case — a different
  `(userId, organizationId)` owner's droppable source is evicted independently of another
  owner's protected one, so eviction cannot cross tenant boundaries.
- `test/application/planning/budgeted_planning_mutation_store_test.dart` — the enforcement
  decorator: writes below the refuse threshold succeed; a write at or above it is refused
  with `PlanningMutationBudgetExceededException` and triggers no eviction (catalog eviction
  cannot relieve the mutation budget); a refusal leaves existing pending mutations untouched
  and `clearMutation` still drains a full store; a refused **fold** — an edit that would
  have merged into an already-pending aggregate — leaves that pending aggregate completely
  intact rather than partially applying or destroying it; a domain rejection
  (`LocalPlanningSlugConflictException`) propagates without eviction or retry.
- `clock_skew_probe_test.dart` — `LF-T6` probe. Adds an injectable clock seam to
  `PlanningMutationReconciler` (default wall-clock behavior unchanged) and confirms an
  injected skewed clock flows straight through into reconciled timestamps uncorrected. A
  server-clock anchor remains deferred (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`).
- `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart` — `LF-T1`
  scenario: offline edit → relaunch → reconnect → sync, skip-gated on a live local Supabase
  stack. Verified passing against a running stack.
- `apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart` — two-device
  concurrent-edit conflict matrix, skip-gated. Rename-vs-rename, reorder-vs-reorder,
  add-same-song-twice, edit-vs-remote-delete, and partial-edit-vs-full-edit pairs are all
  fully wired and verified passing against a running stack; the edit-vs-remote-delete and
  partial-edit-vs-full-edit error-code/semantics contracts are now pinned (see Backend
  Verification below).

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
- Overflow-safe slug-suffix numbering for plan/session names: a name ending in a number at or above 2^31 still creates successfully and keeps its full text slug, with collision numbering falling back to the slug root (e.g. `set-2`), verified in `scripts/tests/planning-write-contract-test.sh`
- Unique-song-per-session enforcement (SEC-5) at the database layer through the partial index `session_items_unique_song_per_session`: a direct duplicate insert is rejected with SQLSTATE 23505, and the `create_song_session_item` RPC re-raises it as `duplicate_song_in_session_blocked` (P0001)
- Pinned RPC error-code contracts for planning edits: editing a remotely-deleted plan raises `plan_not_found` (P0002, mapped to remoteMissing on the client), and `update_plan_fields` performs a full overwrite rather than a field-level merge, so a name-only edit also clears `description` and `scheduled_for`
- Invitation redemption outcome matrix (SEC-1): hybrid email binding, caller-keyed rate limiting on suspicious outcomes, and an audit trail (`public.invitation_redemption_attempts`) whose repeated
  terminal outcomes collapse to one row per caller, token and window for `redeem_invitation`'s full `redeemed | not_found | expired | already_redeemed | already_member | email_mismatch | rate_limited` status contract, verified in `scripts/tests/invitation-redemption-contract-test.sh`
- `public.slugify` output parity across accented characters, punctuation runs, leading/trailing separators, and the empty result, pinned before and unchanged after the `unaccent` extension's relocation out of `public`, verified in `scripts/tests/slug-parity-contract-test.sh`
- Backend-derived song shadow metadata: the ChordPro directive-scanner grammar including its two structural gates (tab-block inertness, affecting every field, and the key window governing `key_signature`), each of the five per-field extractors (`title`/`t`, `artist`, `key`, `tempo`, `tags`/`tag`) including last-occurrence-wins, invalid-value handling, and Unicode-whitespace trimming, the one accepted divergence in the key window (a comment the Dart parser reads as a section start does not close it in SQL) pinned as a named boundary rather than left to drift, `create_song`'s and `song_write_update_common`'s title-fallback chain, re-derivation on an update that carries no new source, and the `create_song`/`update_song`/`overwrite_song_update`/`song_write_update_common` signature and grant contract after parameter removal, verified in `scripts/tests/song-derived-metadata-contract-test.sh`

## Pre-Merge Quality Gates

- `dart format --set-exit-if-changed`
- `flutter analyze`
- `flutter test --coverage`
- `./scripts/coverage-gate.sh` — line-coverage ratchet. The threshold is the value
  measured when the gate landed (72%); raise it as coverage improves, never lower
  it to make a red build green. It evaluates the report the test run already
  produced, so the suite is not executed twice.
- `./scripts/dependency-audit.sh` — fails on a published advisory, a retracted or
  discontinued package (transitive included), or a declared dependency whose
  locked version is behind its own constraint. Deliberately silent about majors
  the constraints do not allow, since those need a migration rather than a gate.
- `./scripts/check-migrations.sh`
- `flutter build web --release` in CI (`web_build` job). Compile gate only; the
  web offline/IndexedDB e2e suite remains deferred in
  `docs/deferred/2026-06-29-web-offline-e2e.md`.
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
