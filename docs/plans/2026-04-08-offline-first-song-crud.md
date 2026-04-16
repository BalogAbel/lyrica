# Offline-First Song CRUD Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add backend-authorized local-first song create, update, and delete flows with optimistic concurrency, explicit conflict resolution, dependency-safe deletion, and sign-out safeguards.

**Architecture:** Extend the existing authenticated song cache into a song write slice by adding local write-side mutation tracking in Drift, a backend-owned write contract gated by `canEditSongs`, and a sync coordinator that keeps local reads authoritative while offline. Deletion remains soft locally until acknowledged remotely, `pending_delete` rows disappear from normal reads immediately, and conflicts resolve through explicit user choice rather than silent retry behavior.

**Tech Stack:** Flutter, Dart, Riverpod, Drift, SQLite, Supabase Postgres, Supabase RLS/policy helpers, Flutter test, integration test, Markdown

---

### Task 1: Define Backend Song Write Contract And Database Rules

**Files:**
- Modify: `supabase/migrations/<next>_song_crud_write_contract.sql`
- Modify: `supabase/seed/seed.sql` if required by new constraints
- Modify: `docs/specs/2026-04-05-song-crud.md`
- Test: `scripts/tests/<song-crud-backend-test>.sh`
- Reference: `docs/domain/domain-model.md`

- [ ] **Step 1: Write the failing backend verification**

Add or extend backend regression coverage so it proves:
- song writes require backend-owned `canEditSongs`
- song slug uniqueness remains scoped to `organization_id`
- delete is rejected when any `session_item` still references the song
- accepted song deletion cascades to song-owned attachments
- explicit overwrite mutations are distinct from ordinary stale-version writes

- [ ] **Step 2: Run the backend verification to confirm it fails**

Run the focused backend regression command for the new song CRUD write contract.

Expected: FAIL because the backend write path and dependency protections do not exist yet.

- [ ] **Step 3: Add the backend mutation contract**

Implement the backend song write path so:
- ordinary create, update, and delete mutations require `canEditSongs`
- update and delete compare `base_version` against the current server `version`
- stale writes fail with an explicit conflict response
- explicit overwrite mutations are allowed only after user confirmation and still require `canEditSongs`
- delete re-checks `session_items` dependencies before removing the song

- [ ] **Step 4: Re-run the backend verification**

Run the same focused backend regression command again.

Expected: PASS.

### Task 2: Add Drift Write-Side Song Mutation Storage

**Files:**
- Modify: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_tables.dart`
- Modify: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_database.dart`
- Modify: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`
- Test: `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`

- [ ] **Step 1: Write the failing store tests**

Add tests that prove the local store can:
- persist `pending_create`, `pending_update`, `pending_delete`, `synced`, and `conflict`
- hide `pending_delete` rows from normal read queries and slug lookup queries
- preserve dedicated access to pending rows for sync-status and conflict surfaces
- keep offline-created slugs unique within one organization before sync succeeds
- update the local slug to the server-returned canonical slug after create sync

- [ ] **Step 2: Run the focused store tests**

Run: `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`

Expected: FAIL because write-side song mutation behavior is not implemented yet.

- [ ] **Step 3: Implement the minimal Drift extensions**

Extend the existing song catalog store/database so it can:
- persist song mutation metadata including `base_version`, `sync_status`, and sync-error context
- exclude `pending_delete` rows from normal read methods
- expose targeted read methods for pending/conflict recovery flows
- allocate the next available local slug suffix when a new offline song would collide with an existing cached or pending song slug in the same organization
- reconcile the locally generated slug to the backend-returned canonical slug after sync success

- [ ] **Step 4: Re-run the focused store tests**

Run the same test command again.

Expected: PASS.

### Task 3: Add Song CRUD Application Logic And Conflict Handling

**Files:**
- Create: `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/song_library_service.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Test: `apps/lyron_app/test/application/song_library/song_mutation_sync_controller_test.dart`
- Test: `apps/lyron_app/test/application/song_library/song_library_service_test.dart`

- [ ] **Step 1: Write the failing application-layer tests**

Add tests that prove:
- create queues `pending_create` with UUID v4 and generated slug
- update queues `pending_update` with the current `base_version`
- delete is blocked locally when a `session_item` currently references the song
- authorization failures are surfaced as non-retryable sync errors, not merge conflicts
- stale-version failures become `conflict`
- explicit overwrite actions call the dedicated overwrite path instead of ordinary retry logic

- [ ] **Step 2: Run the focused application tests**

Run:
- `cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart`
- `cd apps/lyron_app && flutter test test/application/song_library/song_library_service_test.dart`

Expected: FAIL because song mutation orchestration does not exist yet.

- [ ] **Step 3: Implement the minimal application workflow**

Implement the application layer so it:
- creates and updates local rows first
- queues manual sync attempts through one coordinator in this MVP branch
- distinguishes conflict, authorization, dependency, and connectivity failures
- keeps authorization/dependency failures visible on the mutation row while leaving explicit user-initiated manual sync as the only shipped retry path in this MVP branch
- applies the server-returned canonical row after successful create/update or explicit overwrite
- clears local rows only after accepted delete sync
- blocks ordinary edit/delete flows while a row is in `conflict`, forcing the explicit keep/discard resolution path
- persists keep/discard failure outcomes back onto the local conflict row instead of dropping the exception on the floor

- [ ] **Step 4: Re-run the focused application tests**

Run the same two test commands again.

Expected: PASS.

### Task 4: Add User-Facing Song CRUD And Recovery Surfaces

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Test: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Test: `apps/lyron_app/test/router/app_router_test.dart`

- [ ] **Step 1: Write the failing widget and router tests**

Add coverage for:
- manual sync affordance
- hidden `pending_delete` songs in normal navigation
- conflict UI offering keep/discard actions
- delete-blocked messaging when the song is still used by a session
- sign-out warning when unsynced song mutations exist

- [ ] **Step 2: Run the focused widget and router tests**

Run:
- `cd apps/lyron_app && flutter test test/presentation/song_library/song_list_screen_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart`
- `cd apps/lyron_app && flutter test test/router/app_router_test.dart`

Expected: FAIL because the new song CRUD UX does not exist yet.

- [ ] **Step 3: Implement the minimal UI surfaces**

Add the smallest presentation flow that:
- lets the user create, edit, and request deletion of songs locally
- hides `pending_delete` rows from normal lists and slug navigation
- exposes sync status, authorization/dependency failures, and conflict recovery
- blocks sign-out behind the documented unsynced-work warning

- [ ] **Step 4: Re-run the focused widget and router tests**

Run the same three test commands again.

Expected: PASS.

### Task 5: Prove End-To-End Song CRUD Behavior

**Files:**
- Modify: `apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart`
- Create: `apps/lyron_app/test/integration/local_first_song_crud_flow_test.dart`
- Reference: `docs/testing/testing-strategy.md`

- [ ] **Step 1: Write the failing integration coverage**

Add integration tests for:
- offline create followed by successful sync
- offline update followed by conflict and explicit overwrite/discard actions
- delete blocked by `session_items`
- accepted delete cascading attachment cleanup
- sign-out discard flow for unsynced mutations
- Treat reconnect-triggered background mutation sync as deferred follow-up work for a later slice; do not claim it as shipped behavior in this plan.

- [ ] **Step 2: Run the focused integration suite**

Run:
- `cd apps/lyron_app && flutter test test/integration/authenticated_song_reader_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/local_first_song_crud_flow_test.dart`

Expected: FAIL until the full song CRUD slice is implemented.

- [ ] **Step 3: Re-run after implementation**

Run the same two integration commands after Tasks 1-4 are complete.

Expected: PASS.

### Task 6: Final Verification And Documentation Consistency

**Files:**
- Modify: any files touched during implementation

- [ ] **Step 1: Run the complete verification set**

Run the focused backend, store, application, widget, router, and integration commands from the earlier tasks.

Expected: PASS.

- [ ] **Step 2: Run repository verification appropriate to the changed slice**

Run:
- `flutter test`
- `flutter analyze`
- `./scripts/check-migrations.sh`

Expected: PASS.

- [ ] **Step 3: Review the durable docs together**

Confirm these repository documents agree on the final shipped behavior:
- `docs/specs/2026-04-05-song-crud.md`
- `docs/plans/2026-04-08-offline-first-song-crud.md`
- `docs/domain/domain-model.md`
- `docs/architecture/architecture.md`
- `docs/architecture/decisions/ADR-013-song-write-sync-boundary.md`
- `docs/testing/testing-strategy.md`
- `docs/product/vision.md`
