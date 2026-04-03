# Local-First Planning Read Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make planning reads local-first for the active organization by eagerly synchronizing the full visible planning read model into a normalized local store and serving plan list, plan detail, and plan-origin reader context from persisted local state.

**Architecture:** Add a dedicated Drift-backed planning local store owned by the offline layer, then split planning access into a remote refresh repository plus a local read repository behind the existing planning boundary. A planning sync controller should eagerly refresh the full visible planning model for the signed-in active organization, replace the local read model atomically on success, preserve the previous local state on refresh failure, and clear authenticated planning data on explicit sign-out. Presentation should read planning data from local-first providers without knowing whether the current data originated from a recent online refresh or persisted local state.

**Tech Stack:** Flutter, Dart, Riverpod, Drift, SQLite, build_runner, Supabase Flutter client, Flutter test, integration test, Markdown

---

### Task 1: Add Drift-Backed Planning Local Storage

**Files:**
- Create: `apps/lyron_app/lib/src/offline/planning/planning_local_database.dart`
- Create: `apps/lyron_app/lib/src/offline/planning/planning_local_database.g.dart`
- Create: `apps/lyron_app/lib/src/offline/planning/planning_local_tables.dart`
- Create: `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`
- Create: `apps/lyron_app/test/offline/planning/planning_local_store_test.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Reference: `docs/specs/2026-04-03-local-first-planning-read.md`
- Reference: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_database.dart`
- Reference: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`

- [ ] **Step 1: Write the failing local-store tests**

Create `apps/lyron_app/test/offline/planning/planning_local_store_test.dart` to define the storage contract:

```dart
test('replaces the active planning projection atomically for one user and organization', () async {
  final database = TestPlanningLocalDatabase();
  final store = PlanningLocalStore(database);

  await store.replaceActiveProjection(
    userId: 'user-1',
    organizationId: 'org-1',
    plans: const [
      CachedPlanRecord(id: 'plan-1', name: 'Sunday AM', scheduledFor: null),
    ],
    sessions: const [
      CachedSessionRecord(id: 'session-1', planId: 'plan-1', position: 10, name: 'Worship'),
    ],
    items: const [
      CachedSessionItemRecord(
        id: 'item-1',
        sessionId: 'session-1',
        position: 10,
        songId: 'song-1',
        songTitle: 'A forrasnal',
      ),
    ],
    refreshedAt: DateTime(2026),
  );

  expect(
    await store.readPlanSummaries(userId: 'user-1', organizationId: 'org-1'),
    hasLength(1),
  );
});
```

Also cover:

- replacing a previous active planning projection for the same user and organization
- isolating local planning data between different organizations
- deleting all authenticated planning data for one user on sign-out
- never exposing new plans without matching sessions and session items for the same committed projection
- preserving duplicate-song session items as distinct entries keyed by `sessionItemId`
- preserving deterministic ordering for plans, sessions, and session items using `scheduled_for ASC NULLS LAST`, `updated_at DESC`, `id ASC` for plans and `position ASC`, `id ASC` for sessions and session items
- preserving parent keys `planId`, `sessionId`, and ownership metadata on the normalized child tables

- [ ] **Step 2: Run the focused store test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/offline/planning/planning_local_store_test.dart`

Expected: FAIL because the planning Drift database and store do not exist yet.

- [ ] **Step 3: Add the minimal Drift tables and database**

Create `apps/lyron_app/lib/src/offline/planning/planning_local_tables.dart` with focused tables for:

- projection ownership metadata keyed by `(userId, organizationId)`
- cached plan summaries/detail fields keyed by `planId`
- cached sessions keyed by `sessionId` with parent `planId`
- cached session items keyed by `sessionItemId`, `sessionId`, and `planId` with embedded song summary fields needed for planning reads

Create `apps/lyron_app/lib/src/offline/planning/planning_local_database.dart` with a small Drift database that exposes those tables and follows the repository's existing local database connection pattern.

- [ ] **Step 4: Implement the store with atomic hard-replace behavior**

Create `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart` with methods shaped like:

```dart
abstract interface class PlanningLocalStore {
  Future<void> replaceActiveProjection({
    required String userId,
    required String organizationId,
    required List<CachedPlanRecord> plans,
    required List<CachedSessionRecord> sessions,
    required List<CachedSessionItemRecord> items,
    required DateTime refreshedAt,
  });

  Future<List<PlanSummary>> readPlanSummaries({
    required String userId,
    required String organizationId,
  });

  Future<PlanDetail?> readPlanDetail({
    required String userId,
    required String organizationId,
    required String planId,
  });

  Future<void> deletePlanningData({
    required String userId,
    required String organizationId,
  });

  Future<void> deletePlanningDataForUser({
    required String userId,
  });
}
```

Implement `replaceActiveProjection()` in one transaction so a partial refresh never becomes the active local planning state.
Implement `deletePlanningDataForUser()` for explicit sign-out so all authenticated planning projections for the user are removed together.

- [ ] **Step 5: Wire a provider seam for the local store**

Update `apps/lyron_app/lib/src/application/providers.dart` to expose one provider for the `PlanningLocalStore` so later tasks can override it cleanly in tests.

- [ ] **Step 6: Generate the Drift database output**

Run: `cd apps/lyron_app && dart run build_runner build --delete-conflicting-outputs`

Expected: PASS, generating `apps/lyron_app/lib/src/offline/planning/planning_local_database.g.dart`.

- [ ] **Step 7: Re-run the focused store test to verify it passes**

Run: `cd apps/lyron_app && flutter test test/offline/planning/planning_local_store_test.dart`

Expected: PASS.

### Task 2: Split Planning Access Into Remote Refresh And Local Read Boundaries

**Files:**
- Create: `apps/lyron_app/lib/src/application/planning/planning_sync_payload.dart`
- Create: `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart`
- Create: `apps/lyron_app/lib/src/application/planning/planning_remote_refresh_repository.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/planning_repository.dart`
- Modify: `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_repository.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Create: `apps/lyron_app/test/infrastructure/planning/supabase_planning_repository_test.dart`
- Modify: `apps/lyron_app/test/application/providers_test.dart`
- Reference: `apps/lyron_app/lib/src/domain/planning/plan_summary.dart`
- Reference: `apps/lyron_app/lib/src/domain/planning/plan_detail.dart`

- [ ] **Step 1: Write failing repository tests for full planning refresh payload mapping**

Extend `apps/lyron_app/test/infrastructure/planning/supabase_planning_repository_test.dart` with tests that prove the remote planning repository can materialize one full visible planning sync payload for the active organization, including:

- ordered plan summaries
- ordered sessions per plan
- ordered session items per session
- song summary fields needed for planning reads and reader entry
- distinct session item identity even when the same song appears multiple times in one session
- the same deterministic ordering keys as the backend read path: plans by `scheduled_for` asc nulls last, then `updated_at` desc, then `id` asc; sessions by `position` then `id`; session items by `position` then `id`

- [ ] **Step 2: Add a failing test for invalid or incomplete remote planning data**

Add a test that a readable plan row with missing session item song data fails explicitly instead of silently dropping the broken item from the sync payload.

- [ ] **Step 3: Run the focused repository test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_repository_test.dart`

Expected: FAIL because the repository still models only online list/detail reads.

- [ ] **Step 4: Refine the planning repository boundary**

Update `apps/lyron_app/lib/src/domain/planning/planning_repository.dart` so the planning boundary clearly separates:

- local-first list and detail reads
- remote full planning refresh for the active organization

Keep presentation-facing reads abstracted from backend payload shape.

- [ ] **Step 5: Add the sync payload model and remote refresh implementation**

Create `apps/lyron_app/lib/src/application/planning/planning_sync_payload.dart` to represent the fully normalized planning data needed for one atomic local replacement.

Update `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_repository.dart` so it can build that payload from Supabase for the signed-in active organization.

- [ ] **Step 6: Wire provider seams for the local and remote planning repositories**

Update `apps/lyron_app/lib/src/application/providers.dart` to expose:

- a provider for the local planning read repository
- a provider for the remote planning refresh repository

Use those seams in presentation and sync code instead of ad hoc instantiation.

- [ ] **Step 7: Re-run the focused repository tests to verify they pass**

Run: `cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_repository_test.dart`

Expected: PASS.

- [ ] **Step 8: Update the provider-graph test for the new planning seams**

Update `apps/lyron_app/test/application/providers_test.dart` so it covers the new local planning read repository seam, the remote refresh repository seam, and the planning sync controller seam.

Run: `cd apps/lyron_app && flutter test test/application/providers_test.dart`

Expected: PASS.

### Task 3: Add A Planning Sync Controller For Eager Local-First Orchestration

**Files:**
- Create: `apps/lyron_app/lib/src/application/planning/planning_sync_state.dart`
- Create: `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`
- Create: `apps/lyron_app/test/application/planning/planning_sync_controller_test.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Reference: `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`
- Reference: `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`

- [ ] **Step 1: Write the failing controller tests**

Create `apps/lyron_app/test/application/planning/planning_sync_controller_test.dart` to define the orchestration contract:

```dart
test('keeps the previous local planning state when refresh fails', () async {
  final controller = PlanningSyncController(
    localStore: store,
    remoteRepository: remoteRepository,
    authSessionReader: () => const AppAuthSession(userId: 'user-1'),
    organizationReader: () => 'org-1',
  );

  await controller.refreshPlanning();
  remoteRepository.failRefresh();

  await controller.refreshPlanning();

  expect(controller.state.refreshStatus, PlanningRefreshStatus.failed);
  expect(controller.state.hasLocalPlanningData, isTrue);
});
```

Also cover:

- eager refresh starts when signed-in active-organization context becomes available
- first successful refresh establishes local planning availability
- overlapping refreshes do not run concurrently
- sign-out during an in-flight refresh prevents stale repopulation
- sign-out transitions the sync state to `signedOut`/unavailable and invalidates any in-flight refresh generation
- active-organization ownership is explicit in the controller state
- refresh requests serialize so only one refresh updates the local projection at a time
- a stale refresh completion is discarded after the active organization changes
- the controller observes a change-notifying active context provider, not the one-shot organization reader, for boundary changes
- switching to a new active organization that fails to refresh does not expose the previous organization's projection as the current boundary

- [ ] **Step 2: Run the focused controller test to verify it fails**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_sync_controller_test.dart`

Expected: FAIL because the controller and state types do not exist yet.

- [ ] **Step 3: Add explicit planning sync state types**

Create `apps/lyron_app/lib/src/application/planning/planning_sync_state.dart` with focused state such as:

```dart
enum PlanningRefreshStatus { idle, refreshing, failed }

enum PlanningAccessStatus { signedIn, signedOut }

class PlanningSyncState {
  const PlanningSyncState({
    this.userId,
    this.organizationId,
    required this.accessStatus,
    required this.refreshStatus,
    required this.hasLocalPlanningData,
    required this.lastRefreshedAt,
  });

  final String? userId;
  final String? organizationId;
}
```

Keep refresh status and local-availability state separate so the app can represent "refresh failed but local planning is still available" and can fully clear auth-bound identity on sign-out.

- [ ] **Step 4: Implement the sync controller**

Create `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart` to own:

- eager planning refresh trigger evaluation
- explicit full-organization refresh calls
- atomic replacement into the local store after successful remote refresh
- sign-out cleanup for authenticated planning data
- stable fallback behavior when refresh fails but local planning already exists
- monotonic generation tracking so older active-organization refresh completions are ignored
- sign-out invalidation that clears the access state, bumps the generation, and causes in-flight refresh completions to be ignored

- [ ] **Step 5: Wire the sync controller to auth and active-organization lifecycle**

Update `apps/lyron_app/lib/src/application/providers.dart` so the planning sync controller listens to:

- `appAuthControllerProvider` for sign-in, sign-out, and session-expiry transitions
- `activeCatalogContextProvider` for active-organization changes and current boundary identity

The controller must:

- eagerly refresh when a signed-in active-organization context becomes available
- refresh again when the active organization changes
- purge the previously active organization's local planning projection before exposing the new organization as current
- delete authenticated planning projections for the user on explicit sign-out
- reset the sync controller to signed-out/unavailable after explicit sign-out
- discard stale refresh completions using a monotonically increasing active-organization generation token

- [ ] **Step 6: Wire provider seams for the sync controller**

Update `apps/lyron_app/lib/src/application/providers.dart` to expose:

- a provider for the planning sync controller
- a provider for observing planning sync state
- a provider for the planning local store

- [ ] **Step 7: Re-run the focused controller tests to verify they pass**

Run: `cd apps/lyron_app && flutter test test/application/planning/planning_sync_controller_test.dart`

Expected: PASS.

- [ ] **Step 8: Update the provider-graph test for the planning store and sync-state seams**

Update `apps/lyron_app/test/application/providers_test.dart` so it covers the planning local store provider and the planning sync-state provider in addition to the local read repo, remote refresh repo, and sync controller.

Run: `cd apps/lyron_app && flutter test test/application/providers_test.dart`

Expected: PASS.

### Task 4: Move Planning List And Detail Reads To The Local Store

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Create: `apps/lyron_app/test/presentation/planning/planning_providers_test.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Reference: `apps/lyron_app/lib/src/shared/app_strings.dart`

- [ ] **Step 1: Write failing provider tests for local-first planning reads**

Create `apps/lyron_app/test/presentation/planning/planning_providers_test.dart` to prove:

- the planning list provider reads from local state
- the plan detail provider reads from local state
- route-driven plan-origin reader context can be resolved from local planning data after synchronization

- [ ] **Step 2: Add failing widget tests for initial vs synchronized local planning states**

Update:

- `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`
- `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`

Add coverage for:

- planning unavailable before first successful download
- planning visible from local state after synchronization
- refresh failure messaging while local data remains readable

- [ ] **Step 3: Run the focused provider and widget tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/planning/planning_providers_test.dart \
  test/presentation/planning/plan_list_screen_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart
```

Expected: FAIL because planning providers and UI still assume online-only reads.

- [ ] **Step 4: Move planning providers to local-first reads**

Update `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart` so plan list and plan detail reads come from the local planning repository and not directly from remote fetch behavior.

- [ ] **Step 5: Surface explicit planning availability states in the screens**

Update the planning screens so they can distinguish:

- no local planning state yet
- local planning available
- refresh in progress
- refresh failed while local planning remains available

Keep the UI utilitarian; this slice is about behavior, not redesign.

- [ ] **Step 6: Re-run the focused provider and widget tests to verify they pass**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/planning/planning_providers_test.dart \
  test/presentation/planning/plan_list_screen_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart
```

Expected: PASS.

### Task 5: Keep Session-Scoped Reader Context Local-First

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context_provider.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context_resolver.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_provider_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart`
- Reference: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context.dart`

- [ ] **Step 1: Write failing tests for offline scoped-reader context resolution**

Extend the existing song-reader context tests so they prove:

- plan-origin reader context resolves from locally synchronized planning data
- offline scoped-reader context still computes previous and next within the same session
- missing local planning context produces the existing explicit invalid-context failure behavior
- duplicate-song sessions keep `sessionItemId` as the navigation anchor instead of collapsing to `songId`

- [ ] **Step 2: Run the focused reader-context tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart \
  test/presentation/song_reader/session_scoped_reader_context_provider_test.dart
```

Expected: FAIL because the provider still assumes online planning reads on cold entry.

- [ ] **Step 3: Move cold-path planning context resolution to the local planning store**

Update `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context_provider.dart` so the cold path resolves planning reader context from synchronized local planning data rather than re-fetching planning detail online.

Keep the route contract and invalid-context rules unchanged.

- [ ] **Step 4: Re-run the focused reader-context tests to verify they pass**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart \
  test/presentation/song_reader/session_scoped_reader_context_provider_test.dart
```

Expected: PASS.

### Task 6: Prove Local-First Planning End-To-End Against Local Supabase

**Files:**
- Modify: `apps/lyron_app/test/integration/plan_and_session_flow_test.dart`
- Create: `apps/lyron_app/test/integration/local_first_planning_flow_test.dart`
- Modify: `scripts/verify.sh`
- Modify: `README.md`
- Modify: `docs/testing/testing-strategy.md`

- [ ] **Step 1: Write the failing integration coverage for local-first planning**

Create `apps/lyron_app/test/integration/local_first_planning_flow_test.dart` to prove:

- eager refresh downloads planning for the active organization
- offline plan list and plan detail remain readable after synchronization
- plan-origin reader context still resolves from locally persisted planning data
- failed refresh preserves the previous local planning state
- explicit sign-out clears authenticated local planning access
- switching the active organization does not leak the previous organization's local planning projection

- [ ] **Step 2: Run the focused integration test to verify it fails**

Run:

```bash
cd apps/lyron_app && flutter test test/integration/local_first_planning_flow_test.dart \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

Expected: FAIL because the planning local-first flow does not exist yet.

- [ ] **Step 3: Keep or refine the existing online planning integration test**

Update `apps/lyron_app/test/integration/plan_and_session_flow_test.dart` only as needed so it keeps covering backend visibility, ordering, and hidden-organization isolation without duplicating the new local-first planning flow assertions.
- Keep or add one assertion that cached planning data remains isolated when the active organization changes.

- [ ] **Step 4: Wire the new integration test into repository verification**

Update `scripts/verify.sh` so the planning verification path includes the new local-first planning integration coverage alongside the existing authenticated planning read checks.

- [ ] **Step 5: Re-run the focused integration test to verify it passes**

Run:

```bash
cd apps/lyron_app && flutter test test/integration/local_first_planning_flow_test.dart \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

Expected: PASS.

### Task 7: Update Durable Documentation For The New Planning Boundary

**Files:**
- Modify: `README.md`
- Modify: `docs/product/vision.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`
- Reference: `docs/specs/2026-04-03-local-first-planning-read.md`

- [ ] **Step 1: Update repository-level product and architecture language**

Update:

- `README.md`
- `docs/product/vision.md`
- `docs/architecture/architecture.md`

Document that planning is now local-first for the active organization after successful synchronization, and that the current slice still uses full active-organization refresh semantics.

- [ ] **Step 2: Update the domain and testing docs**

Update:

- `docs/domain/domain-model.md`
- `docs/testing/testing-strategy.md`

Document:

- authenticated local planning ownership by user and active organization
- normalized local planning read model expectations
- required test and verification coverage for local-first planning reads

- [ ] **Step 3: Run the relevant automated checks**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/offline/planning/planning_local_store_test.dart \
  test/infrastructure/planning/supabase_planning_repository_test.dart \
  test/application/planning/planning_sync_controller_test.dart \
  test/presentation/planning/planning_providers_test.dart \
  test/presentation/planning/plan_list_screen_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart \
  test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart \
  test/presentation/song_reader/session_scoped_reader_context_provider_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run repository verification for the slice**

Run: `./scripts/verify.sh`

Expected: PASS, including the planning local-first verification path and the pre-existing repository quality gates.
