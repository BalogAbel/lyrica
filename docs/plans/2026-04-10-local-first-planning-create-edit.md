# Local-First Planning Create/Edit Implementation Plan

> Status: Completed

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local-first planning create/edit behavior for `plan create/edit` and `session create/rename/delete`, using a persisted mutation layer plus merged local-first planning views while preserving backend-owned authorization and the existing planning read projection.

**Architecture:** Keep the current Drift-backed planning projection as the repository-owned read model, add a separate persisted planning mutation store for pending local writes, and overlay those mutations inside the planning repository/application layer so the UI always reads merged local-first planning views. Add a backend-owned planning write contract with version-aware update/delete checks, provisional-slug reconciliation, and dependency-safe empty-session deletion. Foreground sync should run automatically when authenticated context is available, while manual retry remains available for failed mutations and sign-out must clear both projection and mutation state.

**Tech Stack:** Flutter, Dart, Riverpod, Drift, SQLite, Supabase Postgres, Supabase RLS/policy helpers, Flutter test, integration test, shell regression scripts, Markdown

---

### Task 1: Define The Backend Planning Write Contract

**Files:**
- Create: `supabase/migrations/202604100001_planning_write_contract.sql`
- Create: `scripts/tests/planning-write-contract-test.sh`
- Modify: `docs/specs/2026-04-10-offline-first-planning-create-edit.md`
- Reference: `supabase/migrations/202604080001_song_crud_write_contract.sql`
- Reference: `docs/domain/domain-model.md`

- [ ] **Step 1: Write the failing backend verification**

Create `scripts/tests/planning-write-contract-test.sh` so it proves:
- plan create is organization-scoped and persists `group_id = null`
- plan/session writes require backend-owned planning write authorization
- plan/session create returns canonical ids, versions, and canonical slugs
- plan/session update and delete reject stale `base_version`
- session delete is rejected when the session still contains `session_items`
- remote delete and authorization failures produce explicit machine-readable outcomes instead of silent no-ops

Use a structure like:

```bash
#!/usr/bin/env bash
set -euo pipefail

./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/provision-local-demo-user.sh

echo "verify planning write authorization, OCC, and empty-session delete contract"
```

- [ ] **Step 2: Run the focused backend verification to confirm it fails**

Run: `bash scripts/tests/planning-write-contract-test.sh`

Expected: FAIL because the planning write contract does not exist yet.

- [ ] **Step 3: Add the backend write contract**

Implement `supabase/migrations/202604100001_planning_write_contract.sql` with:
- backend-owned planning write functions or RPCs for:
  - create plan
  - update plan fields (`name`, `description`, `scheduled_for`)
  - create session
  - rename session
  - delete empty session
- capability and organization-scope enforcement inside Postgres
- version-aware update/delete checks against the current server row
- canonical slug allocation/reconciliation for offline-created plans and sessions
- explicit failure results for:
  - authorization denied
  - stale version conflict
  - remote row missing
  - session not empty

Use SQL shapes along these lines:

```sql
create or replace function api_create_plan(
  p_plan_id uuid,
  p_slug text,
  p_name text,
  p_description text,
  p_scheduled_for timestamptz
) returns table (
  id uuid,
  slug text,
  version bigint,
  updated_at timestamptz
)
security definer
language plpgsql;
```

- [ ] **Step 4: Re-run the backend verification**

Run: `bash scripts/tests/planning-write-contract-test.sh`

Expected: PASS.

### Task 2: Add Persisted Planning Mutation Storage In Drift

**Files:**
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_tables.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_database.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_database.g.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`
- Create: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart`
- Create: `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
- Create: `apps/lyron_app/test/offline/planning/planning_mutation_store_test.dart`
- Reference: `apps/lyron_app/lib/src/application/song_library/drift_song_mutation_store.dart`

- [ ] **Step 1: Write the failing mutation-store tests**

Create `apps/lyron_app/test/offline/planning/planning_mutation_store_test.dart` with tests that prove:
- pending mutations persist across database reopen
- plan create/edit and session create/rename/delete can be recorded independently from the read projection
- create-then-edit compacts into one pending create
- create-then-delete annihilates the local mutation
- session mutations stay tied to the parent locally created plan
- session delete disappears from merged reads immediately but remains recoverable if backend rejection arrives later
- failed authorization/dependency/remote-delete states stop overlaying the normal merged view
- local provisional plan/session slugs stay unique before sync succeeds

Use a test seam like:

```dart
test('create then edit collapses into one pending plan create', () async {
  final store = makePlanningMutationStore();

  await store.recordPlanCreate(...);
  await store.recordPlanEdit(...);

  final mutations = await store.readPendingMutations(userId: 'user-1', organizationId: 'org-1');
  expect(mutations.single.kind, PlanningMutationKind.planCreate);
});
```

- [ ] **Step 2: Run the focused mutation-store tests**

Run: `cd apps/lyron_app && flutter test test/offline/planning/planning_mutation_store_test.dart`

Expected: FAIL because no planning mutation storage exists yet.

- [ ] **Step 3: Extend the planning database and add the mutation store**

Add focused mutation tables to `planning_local_tables.dart` for:
- persisted planning mutations keyed by `userId`, `organizationId`, `aggregateType`, and aggregate id
- mutation ordering metadata for parent-before-child sync
- failure context for authorization, dependency, remote-delete, and conflict states

Create `planning_mutation_sync_types.dart` with explicit domain types such as:

```dart
enum PlanningMutationKind {
  planCreate,
  planEdit,
  sessionCreate,
  sessionRename,
  sessionDelete,
}

enum PlanningMutationSyncStatus {
  pending,
  failedAuthorization,
  failedDependency,
  failedRemoteDelete,
  conflict,
}
```

Create `drift_planning_mutation_store.dart` with methods shaped like:

```dart
abstract interface class PlanningMutationStore {
  Future<void> recordPlanCreate(...);
  Future<void> recordPlanEdit(...);
  Future<void> recordSessionCreate(...);
  Future<void> recordSessionRename(...);
  Future<void> recordSessionDelete(...);
  Future<List<PlanningMutationRecord>> readPendingMutations(...);
  Future<bool> hasUnsyncedMutations({required String userId});
}
```

- [ ] **Step 4: Generate the Drift output**

Run: `cd apps/lyron_app && dart run build_runner build --delete-conflicting-outputs`

Expected: PASS, regenerating `planning_local_database.g.dart`.

- [ ] **Step 5: Re-run the focused mutation-store tests**

Run: `cd apps/lyron_app && flutter test test/offline/planning/planning_mutation_store_test.dart`

Expected: PASS.

### Task 3: Overlay Mutations Into Merged Local-First Planning Reads

**Files:**
- Modify: `apps/lyron_app/lib/src/domain/planning/planning_repository.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart`
- Create: `apps/lyron_app/lib/src/application/planning/planning_write_service.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Modify: `apps/lyron_app/test/offline/planning/planning_local_store_test.dart`
- Create: `apps/lyron_app/test/application/planning/planning_write_service_test.dart`
- Modify: `apps/lyron_app/test/application/providers_test.dart`

- [ ] **Step 1: Write the failing repository and service tests**

Add tests that prove:
- pending plan create appears immediately in `listPlans()`
- pending plan edit immediately changes merged list/detail fields
- eligible session delete disappears from merged plan detail immediately
- failed authorization/dependency/remote-delete mutations no longer overlay the normal merged read model
- merged plan ordering still uses `scheduled_for ASC NULLS LAST`, then `updated_at DESC`, then `id ASC`
- locally created session ordering appends deterministically after synchronized sessions

Use test snippets like:

```dart
test('merged plan detail hides a locally deleted empty session', () async {
  final repository = makePlanningRepositoryWithProjectionAndMutations(...);

  final detail = await repository.getPlanDetail('plan-1');

  expect(detail.sessions.map((session) => session.id), isNot(contains('session-2')));
});
```

- [ ] **Step 2: Run the focused repository and service tests**

Run:
- `cd apps/lyron_app && flutter test test/application/planning/planning_write_service_test.dart`
- `cd apps/lyron_app && flutter test test/offline/planning/planning_local_store_test.dart`

Expected: FAIL because merged planning reads and write service orchestration do not exist yet.

- [ ] **Step 3: Implement the merged read path and write service**

Update `planning_local_read_repository.dart` so it overlays persisted planning mutations on top of the synchronized projection before returning:
- `listPlans()`
- `getPlanDetail()`
- slug lookup methods

Create `planning_write_service.dart` to validate and record local writes:
- plan create with provisional slug allocation
- plan edit restricted to `name`, `description`, `scheduled_for`
- session create with append-to-end position
- session rename
- session delete only when merged current detail shows zero `session_items`

Use service seams like:

```dart
class PlanningWriteService {
  Future<void> createPlan(PlanningWriteContext context, PlanCreateDraft draft);
  Future<void> editPlan(PlanningWriteContext context, PlanEditDraft draft);
  Future<void> createSession(PlanningWriteContext context, SessionCreateDraft draft);
  Future<void> renameSession(PlanningWriteContext context, SessionRenameDraft draft);
  Future<void> deleteSession(PlanningWriteContext context, SessionDeleteDraft draft);
}
```

- [ ] **Step 4: Wire provider seams for merged reads and writes**

Update `application/providers.dart` to expose:
- `planningMutationStoreProvider`
- `planningWriteServiceProvider`
- a planning repository provider that now reads merged local-first views

- [ ] **Step 5: Re-run the focused repository and service tests**

Run the same two test commands again plus:
- `cd apps/lyron_app && flutter test test/application/providers_test.dart`

Expected: PASS.

### Task 4: Add Planning Mutation Sync And Remote Reconciliation

**Files:**
- Create: `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_mutation_repository.dart`
- Create: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_sync_state.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Create: `apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart`
- Create: `apps/lyron_app/test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`
- Modify: `apps/lyron_app/test/application/planning/planning_sync_controller_test.dart`
- Modify: `apps/lyron_app/test/application/planning/active_planning_context_controller_test.dart`
- Modify: `apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

- [ ] **Step 1: Write the failing sync and remote repository tests**

Add coverage for:
- automatic foreground sync after local mutation record when signed-in active context is available
- manual retry of pending and failed mutations
- parent-before-child create ordering and child-before-parent destructive ordering
- slug reconciliation after backend returns canonical slug
- authorization failures moving mutations out of normal merged reads
- remote-delete and stale-version conflicts remaining inspectable instead of disappearing
- successful mutation reconciliation updating the projection and clearing mutation rows
- auth-boundary cleanup for session expiry, revoked auth session, authenticated account switch, and active-organization switch

- [ ] **Step 2: Run the focused sync tests**

Run:
- `cd apps/lyron_app && flutter test test/application/planning/planning_mutation_sync_controller_test.dart`
- `cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`

Expected: FAIL because the write-side sync path does not exist yet.

- [ ] **Step 3: Implement the remote planning mutation repository**

Create `supabase_planning_mutation_repository.dart` that maps local mutation records to the backend write contract and returns canonical success/failure results such as:

```dart
sealed class PlanningMutationRemoteResult {
  const PlanningMutationRemoteResult();
}

final class PlanningMutationRemoteSuccess extends PlanningMutationRemoteResult {
  const PlanningMutationRemoteSuccess(this.payload);
}

final class PlanningMutationRemoteFailure extends PlanningMutationRemoteResult {
  const PlanningMutationRemoteFailure(this.code, this.message);
}
```

- [ ] **Step 4: Implement sync orchestration**

Create `planning_mutation_sync_controller.dart` so it:
- reads pending mutations for the active authenticated planning context
- runs foreground automatic sync when local writes are recorded and auth/context allow it
- stops on connectivity failures
- marks authorization/dependency/remote-delete failures as non-overlaying failure states
- preserves conflict state for later explicit resolution
- refreshes or reconciles the projection with backend-accepted canonical rows and slugs
- clears or invalidates authenticated pending planning mutations when the authenticated user or active organization boundary changes
- does not replay a prior user's or prior organization's mutations in the new boundary

- [ ] **Step 5: Re-run the focused sync tests**

Run the same two test commands again plus:
- `cd apps/lyron_app && flutter test test/application/planning/planning_sync_controller_test.dart`

Expected: PASS.

### Task 5: Add Planning Write UI, Status Surfaces, And Sign-Out Safeguards

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Create: `apps/lyron_app/test/presentation/planning/plan_write_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Modify: `apps/lyron_app/test/router/app_router_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Write the failing widget and router tests**

Add coverage for:
- create-plan affordance from the plan list
- edit-plan affordance for `name`, `description`, `scheduled_for`
- create-session, rename-session, and delete-empty-session affordances in plan detail
- immediate UI update after local write
- visible pending/failed mutation state where needed
- manual retry affordance for failed planning mutations
- sign-out warning when unsynchronized planning mutations exist

- [ ] **Step 2: Run the focused widget and router tests**

Run:
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_list_screen_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_write_screen_test.dart`
- `cd apps/lyron_app && flutter test test/router/app_router_test.dart`

Expected: FAIL because planning write UI does not exist yet.

- [ ] **Step 3: Implement the minimal planning write surfaces**

Update presentation so:
- the plan list exposes create-plan entry and reflects merged local ordering
- the plan detail screen exposes plan edit plus session create/rename/delete actions
- delete is offered only for empty sessions
- provisional local changes appear immediately
- failed non-overlaying mutations remain visible in a focused status/review surface instead of silently changing the main merged view
- sign-out is blocked behind the documented discard warning when planning mutations remain unsynced

- [ ] **Step 4: Re-run the focused widget and router tests**

Run the same four commands again.

Expected: PASS.

### Task 6: Prove End-To-End Planning Write Behavior And Update Durable Docs

**Files:**
- Create: `apps/lyron_app/test/integration/local_first_planning_write_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/local_first_planning_read_flow_test.dart`
- Modify: `README.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Create: `docs/architecture/decisions/ADR-014-planning-write-projection-mutation-boundary.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/product/vision.md`
- Modify: `docs/specs/2026-04-10-offline-first-planning-create-edit.md`
- Modify: `docs/plans/2026-04-10-local-first-planning-create-edit.md`

- [ ] **Step 1: Write the failing integration tests**

Create integration coverage for:
- offline plan create followed by slug reconciliation after sync
- offline plan edit followed by successful foreground sync
- offline session create and rename
- eligible session delete disappearing immediately and reappearing if backend delete is rejected
- app restart preserving pending planning mutations and merged reads
- auth/session boundary cleanup removing prior-user pending planning mutations
- active-organization switch clearing prior-organization pending planning mutations before the new organization becomes current
- explicit sign-out discard flow for unsynchronized planning mutations

- [ ] **Step 2: Run the focused integration suite**

Run:
- `cd apps/lyron_app && flutter test test/integration/local_first_planning_read_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/local_first_planning_write_flow_test.dart`

Expected: FAIL until Tasks 1-5 are complete.

- [ ] **Step 3: Re-run after implementation**

Run the same two integration commands again.

Expected: PASS.

- [ ] **Step 4: Update durable repository docs**

Make the docs agree on the shipped slice:
- `README.md` describes local-first planning write scope and verification path
- `docs/domain/domain-model.md` records planning write invariants, organization-scoped create, and empty-session delete rules
- `docs/architecture/architecture.md` records the planning projection-plus-mutation boundary and foreground sync behavior
- `docs/architecture/decisions/ADR-014-planning-write-projection-mutation-boundary.md` captures the durable architectural decision
- `docs/testing/testing-strategy.md` records standing planning write coverage
- `docs/product/vision.md` reflects the newly executable planning write slice

- [ ] **Step 5: Run final verification**

Run:
- `cd apps/lyron_app && flutter test`
- `cd apps/lyron_app && flutter analyze`
- `bash scripts/tests/planning-write-contract-test.sh`
- `./scripts/check-migrations.sh`

Expected: PASS.
