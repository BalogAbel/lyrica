# Active Organization Membership Revocation Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distinguish verified empty membership from connectivity-related unknown state, deny cached fallback after verified empty membership, and clean authenticated local song/planning state with minimal state-machine hardening.

**Architecture:** Add one shared active-organization resolution result type, then reuse it in the existing song-catalog and planning controllers instead of widening the current state models. Keep the current single-active-organization local-first architecture, preserve connectivity-only fallback, and align verified-empty cleanup with the repository's existing sign-out/session-expiry deletion semantics rather than introducing a quarantine/archive subsystem.

**Tech Stack:** Flutter, Dart, Riverpod, Drift, Supabase Flutter client, Flutter test, integration test, Markdown

**Status:** Implemented

---

## Recommended Policy

- Treat active-organization resolution as one of: `selected(organizationId)`, `verifiedEmpty`, `unknownConnectivityFailure`, `unknownNonConnectivityFailure`.
- Allow cached fallback only for `unknownConnectivityFailure`.
- On `verifiedEmpty`, clear active song/planning context and delete authenticated local song data, planning projection data, song mutations, and planning mutations for the signed-in user.
- On `unknownNonConnectivityFailure`, do not use cached fallback; preserve an already-established in-memory planning boundary, but do not create a new boundary from cache.
- Preserve current offline-first behavior for connectivity failures, including cached cold-start recovery.
- Do not add quarantine/archive behavior in this slice; deletion is the minimal safe policy for the current single-active-org model.

## Assumptions

- `current_organization_ids` returning an empty list is an authoritative backend statement that the signed-in user has no currently visible organization memberships.
- The current product keeps only one active authenticated song snapshot and one active authenticated planning projection per user, so per-user cleanup is acceptable and simpler than per-org quarantine.
- Backend RLS remains the authorization boundary; this plan only hardens client-side local lifecycle semantics.
- If implementation reveals product requirements to retain revoked local drafts for later restoration, that is a new slice and not part of this minimal hardening change.

## Plan

### Task 1: Introduce explicit active-organization resolution semantics

**Files:**
- Create: `apps/lyron_app/lib/src/application/active_organization_resolution.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Create: `apps/lyron_app/test/application/active_organization_resolution_test.dart`
- Modify: `apps/lyron_app/test/application/providers_test.dart`
- Reference: `apps/lyron_app/lib/src/shared/connectivity_failure.dart`

- [ ] **Step 1: Write the failing classification tests**

Add `apps/lyron_app/test/application/active_organization_resolution_test.dart` covering:

- verified response with one org id => `selected('org-1')`
- verified response with multiple org ids => stable selected id remains the sorted first id
- verified response with no org ids => `verifiedEmpty`
- connectivity-classified thrown error => `unknownConnectivityFailure`
- malformed response or non-connectivity thrown error => `unknownNonConnectivityFailure`

- [ ] **Step 2: Run the focused classification tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test test/application/active_organization_resolution_test.dart
```

Expected: FAIL because the shared result type and classifier do not exist yet.

- [ ] **Step 3: Implement the minimal shared result type**

Create `apps/lyron_app/lib/src/application/active_organization_resolution.dart` with:

- one sealed result/value type for `selected`, `verifiedEmpty`, `unknownConnectivityFailure`, and `unknownNonConnectivityFailure`
- one classifier function that wraps the `current_organization_ids` RPC response and existing connectivity classifier

Keep `providers.dart` thin by moving result semantics into this small shared file instead of duplicating controller-specific branching.

- [ ] **Step 4: Update provider wiring**

Change `apps/lyron_app/lib/src/application/providers.dart` so the provider that currently returns `Future<String?>` can instead return the shared resolution result without changing backend ownership or the `current_organization_ids` RPC itself.

- [ ] **Step 5: Re-run focused tests**

Run:

```bash
cd apps/lyron_app && flutter test test/application/active_organization_resolution_test.dart
cd apps/lyron_app && flutter test test/application/providers_test.dart
```

Expected: PASS.

### Task 2: Harden song-catalog fallback and verified-empty cleanup

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Modify: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`
- Modify: `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`
- Modify: `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_library_providers_test.dart`

- [ ] **Step 1: Write failing controller tests for verified-empty versus connectivity**

Extend `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart` with tests proving:

- verified empty membership clears context and does not reopen the cached catalog
- verified empty membership deletes authenticated cached song data for the user
- connectivity-classified organization resolution failure still reuses the latest cached organization
- non-connectivity organization resolution failure does not reuse the cached organization

- [ ] **Step 2: Write the failing store test for per-user song cleanup**

Extend `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart` with a test proving authenticated song snapshots and song mutations for one user are removed together by the cleanup path used for verified empty membership.

- [ ] **Step 3: Run focused song tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart
cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart
```

Expected: FAIL because the current controller treats empty membership as `String? == null` without explicit cleanup semantics.

- [ ] **Step 4: Implement minimal song-catalog hardening**

Update `SongCatalogController` so it consumes the shared active-organization resolution result and:

- denies cached fallback on `verifiedEmpty`
- performs authenticated song cleanup on `verifiedEmpty`
- keeps cached fallback only on `unknownConnectivityFailure`
- denies cached fallback on `unknownNonConnectivityFailure`

Prefer targeted branching over new broad catalog state enums.

- [ ] **Step 5: Add or reuse store cleanup helpers**

If the current song store helper set is insufficient, add only the smallest helper needed to remove authenticated song mutations together with cached catalog data for one user. Reuse existing `deleteCatalogsForUser()` behavior where possible rather than adding a parallel cleanup subsystem.

- [ ] **Step 6: Re-run focused song tests**

Run:

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart
cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart
cd apps/lyron_app && flutter test test/presentation/song_library/song_library_providers_test.dart
```

Expected: PASS.

### Task 3: Harden planning active-context fallback and verified-empty cleanup

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/active_planning_context_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`
- Modify: `apps/lyron_app/test/application/planning/active_planning_context_controller_test.dart`
- Modify: `apps/lyron_app/test/application/planning/planning_sync_controller_test.dart`
- Modify: `apps/lyron_app/test/offline/planning/planning_local_store_test.dart`

- [ ] **Step 1: Write failing planning context tests**

Extend `apps/lyron_app/test/application/planning/active_planning_context_controller_test.dart` with tests proving:

- verified empty membership clears planning context even when cached org data exists
- connectivity-classified lookup failure still allows cached cold-start fallback
- non-connectivity lookup failure does not allow cached cold-start fallback
- an already-established planning boundary stays in memory through non-connectivity lookup failure, but not through verified empty membership

- [ ] **Step 2: Write failing planning sync cleanup tests**

Extend `apps/lyron_app/test/application/planning/planning_sync_controller_test.dart` with tests proving:

- verified empty membership clears authenticated planning state for the user
- verified empty membership prevents stale refresh completion from repopulating cleared planning data

- [ ] **Step 3: Write the failing local-store cleanup test**

Extend `apps/lyron_app/test/offline/planning/planning_local_store_test.dart` with a test proving the verified-empty cleanup path deletes planning projection rows and persisted planning mutations for the affected user.

- [ ] **Step 4: Run focused planning tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test test/application/planning/active_planning_context_controller_test.dart
cd apps/lyron_app && flutter test test/application/planning/planning_sync_controller_test.dart
cd apps/lyron_app && flutter test test/offline/planning/planning_local_store_test.dart
```

Expected: FAIL because planning fallback currently catches too broad a failure class and verified empty membership has no dedicated cleanup path.

- [ ] **Step 5: Implement minimal planning hardening**

Update `ActivePlanningContextController` and `PlanningSyncController` so verified empty membership:

- clears the planning boundary immediately
- triggers authenticated planning cleanup for the user
- cannot be overwritten by stale in-flight refresh completions

Keep cached cold-start fallback limited to connectivity-only failure and preserve the current established-boundary behavior for non-connectivity unknown failures.

- [ ] **Step 6: Re-run focused planning tests**

Run:

```bash
cd apps/lyron_app && flutter test test/application/planning/active_planning_context_controller_test.dart
cd apps/lyron_app && flutter test test/application/planning/planning_sync_controller_test.dart
cd apps/lyron_app && flutter test test/offline/planning/planning_local_store_test.dart
```

Expected: PASS.

### Task 4: Drop pending mutations after verified empty membership

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_types.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
- Modify: `apps/lyron_app/test/application/song_library/song_mutation_sync_controller_test.dart`
- Modify: `apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart`

- [ ] **Step 1: Write failing mutation cleanup tests**

Add tests proving:

- verified empty membership removes pending song mutations instead of leaving them retryable
- verified empty membership removes pending planning mutations instead of leaving them retryable
- connectivity failures still preserve pending mutations for later replay

- [ ] **Step 2: Run focused mutation tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart
cd apps/lyron_app && flutter test test/application/planning/planning_mutation_sync_controller_test.dart
```

Expected: FAIL because the current mutation lifecycle does not model membership-revocation cleanup explicitly.

- [ ] **Step 3: Implement the smallest mutation cleanup seam**

Prefer deleting pending mutations through existing per-user cleanup paths invoked from verified-empty handling. Only add direct controller-level behavior if tests prove cleanup cannot be expressed cleanly through store/service wiring.

- [ ] **Step 4: Re-run focused mutation tests**

Run:

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart
cd apps/lyron_app && flutter test test/application/planning/planning_mutation_sync_controller_test.dart
```

Expected: PASS.

### Task 5: Add integration and documentation regression coverage

**Files:**
- Modify: `apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/local_first_planning_read_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/local_first_planning_write_flow_test.dart`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/deferred/2026-05-01-active-organization-membership-revocation.md`

- [ ] **Step 1: Write failing integration tests**

Add integration coverage proving:

- verified empty membership does not reopen stale local song data after a previously cached session
- connectivity failure still reopens cached song and planning data
- verified empty membership clears persisted planning writes instead of replaying them after app restart

- [ ] **Step 2: Run focused integration tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test test/integration/local_first_authenticated_song_reader_flow_test.dart
cd apps/lyron_app && flutter test test/integration/local_first_planning_read_flow_test.dart
cd apps/lyron_app && flutter test test/integration/local_first_planning_write_flow_test.dart
```

Expected: FAIL because verified empty membership is not yet represented end-to-end.

- [ ] **Step 3: Update durable docs with shipped behavior**

After code and tests pass, update:

- `docs/architecture/architecture.md` with explicit active-organization resolution semantics and verified-empty cleanup behavior
- `docs/domain/domain-model.md` with authenticated local-data lifecycle rules after membership revocation
- `docs/testing/testing-strategy.md` with required regression coverage for verified empty membership versus connectivity failure
- `docs/deferred/2026-05-01-active-organization-membership-revocation.md` to mark the deferred item resolved or superseded

- [ ] **Step 4: Re-run focused integration tests**

Run:

```bash
cd apps/lyron_app && flutter test test/integration/local_first_authenticated_song_reader_flow_test.dart
cd apps/lyron_app && flutter test test/integration/local_first_planning_read_flow_test.dart
cd apps/lyron_app && flutter test test/integration/local_first_planning_write_flow_test.dart
```

Expected: PASS.

## Acceptance Criteria

- `verifiedEmpty` is represented explicitly in application logic and is not inferred only from `null`.
- Song and planning flows only use cached fallback for connectivity-classified failures.
- Verified empty membership immediately removes authenticated local song/planning read data and pending mutations for the signed-in user.
- Non-connectivity organization lookup failures do not cold-start from cached organization data.
- Previously established planning in-memory boundaries survive unknown non-connectivity failures but not verified empty membership.
- Existing sign-out/session-expiry cleanup and connectivity-driven offline-first behavior still pass regression coverage.
- The implementation stays scoped to controller/provider/store hardening and does not broaden into route or auth rewrites.

## Exact Validation Commands

Run these commands in order during implementation:

```bash
cd apps/lyron_app && flutter test test/application/active_organization_resolution_test.dart
cd apps/lyron_app && flutter test test/application/providers_test.dart
cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart
cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart
cd apps/lyron_app && flutter test test/presentation/song_library/song_library_providers_test.dart
cd apps/lyron_app && flutter test test/application/planning/active_planning_context_controller_test.dart
cd apps/lyron_app && flutter test test/application/planning/planning_sync_controller_test.dart
cd apps/lyron_app && flutter test test/offline/planning/planning_local_store_test.dart
cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart
cd apps/lyron_app && flutter test test/application/planning/planning_mutation_sync_controller_test.dart
cd apps/lyron_app && flutter test test/integration/local_first_authenticated_song_reader_flow_test.dart
cd apps/lyron_app && flutter test test/integration/local_first_planning_read_flow_test.dart
cd apps/lyron_app && flutter test test/integration/local_first_planning_write_flow_test.dart
cd apps/lyron_app && dart format --set-exit-if-changed lib test
cd apps/lyron_app && flutter analyze
./scripts/verify.sh --skip-migrations
```

If any backend-backed integration path or repository contract changes beyond app-only logic during implementation, replace the last command with:

```bash
./scripts/verify.sh
```

## Rollback Plan

- Revert the shared active-organization resolution type and restore the previous `Future<String?>` organization-reader contract.
- Revert controller branching to the current connectivity-only fallback behavior.
- Revert any new cleanup helper methods and retain existing sign-out/session-expiry-only deletion semantics.
- Keep the new tests until the rollback commit is complete, then either revert them with the code or adjust them to document the intentionally restored behavior.
- If rollout risk is discovered after partial implementation, ship only Task 1 plus narrowly scoped failing tests in a draft branch rather than partially merging cleanup semantics.

## Escalation Points

- Product/security sign-off is required if anyone proposes quarantine instead of deletion for verified empty membership.
- Escalate if implementation needs backend contract changes to `current_organization_ids`; this plan assumes the existing RPC remains sufficient.
- Escalate if verified-empty cleanup conflicts with a product requirement to preserve local drafts after revocation; that is a new slice, not an incidental tweak.
- Escalate if song-mutation cleanup reveals dependency on unsurfaced user workflows such as conflict review after revocation.
- Escalate if planning write cleanup cannot be expressed through current per-user deletion semantics without broadening the state model.
