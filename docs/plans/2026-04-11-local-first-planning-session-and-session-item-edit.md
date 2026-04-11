# Local-First Planning Session And Session Item Edit Implementation Plan

> Status: Proposed

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local-first planning support for session reorder plus song-backed session-item add/delete/reorder on top of the existing planning create/edit slice.

**Architecture:** Preserve the current Drift-backed planning projection as the read model and the separate persisted planning mutation store as the local write-intent model. Extend the planning write contract with collection-aware session and session-item mutations, use plan-level OCC for session reorder and session-level OCC for session-item collection edits, and keep accepted-write reconciliation in the repository-owned sync path when immediate refresh fails.

**Tech Stack:** Flutter, Dart, Riverpod, Drift, SQLite, Supabase Postgres, Supabase RLS and SQL functions, Flutter test, integration test, shell regression scripts, Markdown

---

> Dependency: This plan builds directly on [docs/specs/2026-04-10-offline-first-planning-create-edit.md](docs/specs/2026-04-10-offline-first-planning-create-edit.md) and [docs/plans/2026-04-10-local-first-planning-create-edit.md](docs/plans/2026-04-10-local-first-planning-create-edit.md). Do not redesign the planning projection/mutation split, the foreground sync controller ownership, or the accepted-write reconciliation boundary established there.

### Task 1: Extend The Backend Planning Write Contract For Collection Mutations

**Files:**
- Create: `supabase/migrations/202604110001_planning_session_item_write_contract.sql`
- Modify: `scripts/tests/planning-write-contract-test.sh`
- Reference: `supabase/migrations/202604100001_planning_write_contract.sql`
- Reference: `docs/specs/2026-04-11-offline-first-planning-session-and-session-item-edit.md`

- [ ] **Step 1: Write the failing backend verification**

Extend `scripts/tests/planning-write-contract-test.sh` to prove:
- session reorder requires the backend-owned plan-management write capability already used for plan-scoped planning writes
- session reorder rejects stale plan `base_version`
- session-item add requires backend-owned session write authorization
- session-item add rejects songs outside the active organization visibility boundary
- session-item add rejects duplicate song insertion within one session
- session-item delete rejects stale session `base_version`
- session-item reorder rejects stale session `base_version`
- accepted reorder returns canonical sibling ordering metadata

- [ ] **Step 2: Run the focused backend verification**

Run: `bash scripts/tests/planning-write-contract-test.sh`

Expected: FAIL because the new session and session-item write contract does not exist yet.

- [ ] **Step 3: Add the SQL write contract**

Implement `supabase/migrations/202604110001_planning_session_item_write_contract.sql` with backend-owned functions or RPCs for:
- reordering sessions within one plan
- adding one song-backed session item to one session
- deleting one session item
- reordering session items within one session

The contract must:
- enforce authorization in Postgres
- enforce organization scope for added songs
- enforce the one-song-per-session invariant
- use plan-level `base_version` for session reorder
- use session-level `base_version` for session-item add/delete/reorder
- return enough canonical state to reconcile accepted local writes even when immediate refresh fails, including the parent aggregate id, the new parent `version`, and canonical sibling ordering with positions

- [ ] **Step 4: Re-run the backend verification**

Run: `bash scripts/tests/planning-write-contract-test.sh`

Expected: PASS.

### Task 2: Extend Planning Mutation Types And Persistence

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_types.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/drift_planning_mutation_store.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_tables.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_database.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_database.g.dart`
- Modify: `apps/lyron_app/test/offline/planning/planning_mutation_store_test.dart`

- [ ] **Step 1: Write the failing mutation-store tests**

Add coverage for:
- `session_reorder` compaction by plan
- `session_item_create_song` compaction and local append behavior
- pending session delete removing the deleted session from any surviving pending plan-level reorder
- `session_item_delete` annihilating a locally created item
- `session_item_reorder` compaction by session
- reorder records dropping deleted siblings from the final sibling set
- dependency ordering between pending session create and dependent session reorder or session-item mutations
- failure-status persistence for authorization, dependency, remote-missing, and conflict outcomes on the new mutation kinds

- [ ] **Step 2: Run the focused mutation-store tests**

Run: `cd apps/lyron_app && flutter test test/offline/planning/planning_mutation_store_test.dart`

Expected: FAIL because the store cannot represent the new mutation kinds yet.

- [ ] **Step 3: Extend mutation taxonomy and storage**

Update the mutation types to add:
- `sessionReorder`
- `sessionItemCreateSong`
- `sessionItemDelete`
- `sessionItemReorder`

Persist enough mutation data to reconstruct:
- target plan or session id
- ordered sibling ids for reorder mutations
- selected song id for item creation
- local provisional item id and appended local `position`
- synchronized parent `base_version`

- [ ] **Step 4: Regenerate Drift output**

Run: `cd apps/lyron_app && dart run build_runner build --delete-conflicting-outputs`

Expected: PASS, regenerating `planning_local_database.g.dart`.

- [ ] **Step 5: Re-run the mutation-store tests**

Run: `cd apps/lyron_app && flutter test test/offline/planning/planning_mutation_store_test.dart`

Expected: PASS.

### Task 3: Extend Merged Local Reads And Planning Write Service

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_write_service.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/planning_repository.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/plan_detail.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/session_summary.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/session_item_summary.dart`
- Create: `apps/lyron_app/test/application/planning/planning_local_read_repository_test.dart`
- Modify: `apps/lyron_app/test/application/planning/planning_write_service_test.dart`

- [ ] **Step 1: Write the failing repository and service tests**

Add tests that prove:
- pending session reorder immediately changes merged plan detail ordering
- pending song add immediately appears in the owning session with local song summary data
- pending item delete immediately disappears from the normal merged view
- pending item reorder immediately changes visible session-item order
- duplicate song add is blocked before local record when the merged session already contains that song
- the write service captures plan-level `base_version` for session reorder and session-level `base_version` for session-item collection edits

- [ ] **Step 2: Run the focused repository and service tests**

Run:
- `cd apps/lyron_app && flutter test test/application/planning/planning_local_read_repository_test.dart`
- `cd apps/lyron_app && flutter test test/application/planning/planning_write_service_test.dart`

Expected: FAIL because merged planning reads and the write service do not support the new slice yet.

- [ ] **Step 3: Implement merged-read overlay and write-service entry points**

Extend `planning_write_service.dart` with methods for:
- reordering sessions within one plan
- adding one song item to one session
- deleting one session item
- reordering items within one session

Extend `planning_local_read_repository.dart` so merged plan detail can overlay:
- pending session reorder
- pending local song item create
- pending session-item delete
- pending session-item reorder

Keep duplicate prevention and local song-catalog dependency checks in the application layer where they improve immediate UX, but do not treat them as canonical authorization.

- [ ] **Step 4: Re-run the repository and service tests**

Run the same two commands again.

Expected: PASS.

### Task 4: Extend Remote Sync Mapping And Accepted-Write Reconciliation

**Files:**
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Modify: `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_mutation_repository.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_sync_state.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`
- Modify: `apps/lyron_app/test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`
- Modify: `apps/lyron_app/test/application/planning/planning_mutation_sync_controller_test.dart`

- [ ] **Step 1: Write the failing sync and repository tests**

Add coverage for:
- mapping each new mutation kind to the correct backend RPC
- conflict classification for stale plan or session `base_version`
- dependency classification for duplicate-song and out-of-scope song visibility rejection into the existing `failedDependency` bucket
- accepted session reorder reconciliation when the immediate refresh fails
- accepted session-item add/delete/reorder reconciliation when the immediate refresh fails
- clearing successful mutations only after refresh or direct reconciliation completes
- preserving failed non-overlaying mutations for explicit retry or discard

- [ ] **Step 2: Run the focused sync tests**

Run:
- `cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`
- `cd apps/lyron_app && flutter test test/application/planning/planning_mutation_sync_controller_test.dart`

Expected: FAIL because the sync path cannot map or reconcile the new mutations yet.

- [ ] **Step 3: Implement remote mapping and reconciliation**

Update the sync path so it:
- serializes the new collection mutations in dependency-safe order
- sends the correct parent `base_version`
- applies backend-returned canonical ordering and version data back into the local projection
- leaves authorization, dependency, remote-missing, and conflict failures outside the normal merged overlay
- wires the new mutation kinds and reconciliation branches through `application/providers.dart` so the running app uses the extended sync mapping and accepted-write patch path

- [ ] **Step 4: Re-run the focused sync tests**

Run the same two commands again.

Expected: PASS.

### Task 5: Add Minimal Planning UI Surfaces For The New Slice

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_routes.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Modify: `apps/lyron_app/test/router/app_router_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Add coverage for:
- minimal session reorder affordance in plan detail
- minimal add-song flow that selects from the locally visible song catalog
- add-song affordance remaining unavailable when the active organization has no locally available song catalog
- item delete affordance
- item reorder affordance
- immediate local update after each action
- failure-status surface for non-overlaying planning mutations from this slice

- [ ] **Step 2: Run the focused widget tests**

Run:
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart`
- `cd apps/lyron_app && flutter test test/router/app_router_test.dart`

Expected: FAIL because the UI does not expose the new slice yet.

- [ ] **Step 3: Implement the minimal UI**

Update the planning detail flow so it:
- exposes session reorder without requiring final drag-and-drop polish
- exposes song add from the local catalog already available to the active organization
- gates song add when the local catalog for the active organization is unavailable instead of pretending offline add can proceed
- exposes item delete and item reorder
- keeps status and retry surfaces aligned with the existing planning write architecture

- [ ] **Step 4: Re-run the focused widget tests**

Run the same two commands again.

Expected: PASS.

### Task 6: Prove End-To-End Behavior And Update Durable Docs

**Files:**
- Modify: `apps/lyron_app/test/integration/local_first_planning_write_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/local_first_planning_read_flow_test.dart`
- Modify: `README.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`
- Reference: `docs/specs/2026-04-11-offline-first-planning-session-and-session-item-edit.md`
- Reference: `docs/plans/2026-04-11-local-first-planning-session-and-session-item-edit.md`

- [ ] **Step 1: Write the failing integration tests**

Add coverage for:
- offline session reorder followed by successful sync
- offline song add followed by successful sync
- offline item delete followed by successful sync
- offline item reorder followed by successful sync
- app restart preserving the pending collection mutations and merged plan detail
- auth-boundary cleanup removing pending collection mutations and projection data together

- [ ] **Step 2: Run the focused integration suite**

Run:
- `cd apps/lyron_app && flutter test test/integration/local_first_planning_read_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/local_first_planning_write_flow_test.dart`

Expected: FAIL until Tasks 1-5 are complete.

- [ ] **Step 3: Re-run after implementation**

Run the same two integration commands again.

Expected: PASS.

- [ ] **Step 4: Update durable repository docs**

Update:
- `README.md` with the expanded planning write scope and verification wording
- `docs/domain/domain-model.md` with session reorder and song-backed session-item mutation invariants
- `docs/architecture/architecture.md` with the collection-mutation sync and reconciliation boundary
- `docs/testing/testing-strategy.md` with standing verification expectations for the new slice

- [ ] **Step 5: Run final verification**

Run:
- `cd apps/lyron_app && flutter test`
- `cd apps/lyron_app && flutter analyze`
- `bash scripts/tests/planning-write-contract-test.sh`
- `./scripts/check-migrations.sh`

Expected: PASS.
