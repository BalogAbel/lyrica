# Song Sync Convergence Hardening Implementation Plan

> Status: Proposed

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining song-mutation convergence gap for server-side song deletion while local intent still exists, and keep planning and reader references understandable after canonical song removal.

**Architecture:** Preserve the existing local-first song CRUD model, but add explicit remote-deletion classification on top of the current `sync_status` queue. Update-sourced remote deletion converges through same-id backend recreation, delete-sourced remote deletion converges as accepted deletion, and planning/session-scoped reader flows render preserved human-readable song references instead of crashing into a generic not-found state.

**Tech Stack:** Flutter, Dart, Riverpod, Drift, SQLite, Supabase Postgres, shell regression scripts, Flutter test, integration test, Markdown

---

> Dependency: This plan builds directly on [docs/specs/2026-04-05-song-crud.md](docs/specs/2026-04-05-song-crud.md), [docs/plans/2026-04-08-offline-first-song-crud.md](docs/plans/2026-04-08-offline-first-song-crud.md), and [docs/specs/2026-04-19-song-sync-convergence-hardening.md](docs/specs/2026-04-19-song-sync-convergence-hardening.md). Do not redesign the existing song mutation queue, authorization boundary, or planning projection architecture while implementing this slice.

### Task 1: Extend The Backend Song Write Contract For Remote-Deleted Convergence

**Files:**
- Modify: `supabase/migrations/202604080001_song_crud_write_contract.sql`
- Modify: `scripts/tests/song-crud-write-contract-test.sh`
- Reference: `docs/specs/2026-04-19-song-sync-convergence-hardening.md`

- [ ] **Step 1: Write the failing backend verification**

Extend `scripts/tests/song-crud-write-contract-test.sh` to prove:
- update against a remotely deleted song returns explicit `song_not_found`
- delete against a remotely deleted song converges as accepted deletion rather than version conflict
- same-id recreation path requires backend-owned `canEditSongs`
- same-id recreation returns canonical recreated song row
- same-id recreation preserves organization scoping and slug reconciliation rules

- [ ] **Step 2: Run the focused backend verification**

Run: `bash scripts/tests/song-crud-write-contract-test.sh`

Expected: FAIL because the backend contract does not yet define the new convergence paths.

- [ ] **Step 3: Extend the SQL write contract**

Update `202604080001_song_crud_write_contract.sql` so it:
- preserves `song_not_found` for update-style writes that depended on an existing row
- treats delete against an already deleted row as accepted convergence
- exposes a deliberate same-id recreate path for update-sourced remote deletion recovery
- keeps authorization and organization scoping backend-enforced
- returns canonical recreated row data for local reconciliation

- [ ] **Step 4: Re-run the backend verification**

Run: `bash scripts/tests/song-crud-write-contract-test.sh`

Expected: PASS.

### Task 2: Add Explicit Remote-Deletion Classification In Song Sync Types And Mapping

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_types.dart`
- Modify: `apps/lyron_app/lib/src/infrastructure/song_library/supabase_song_mutation_repository.dart`
- Create: `apps/lyron_app/test/infrastructure/song_library/supabase_song_mutation_repository_test.dart`
- Modify: `apps/lyron_app/test/application/song_library/song_mutation_sync_controller_test.dart`

- [ ] **Step 1: Write the failing sync-mapping tests**

Add coverage for:
- mapping backend `song_not_found` to explicit remote-deletion classification instead of generic unknown failure
- distinguishing update-sourced remote deletion from delete-sourced remote deletion
- preserving conflict-origin intent so remote deletion from prior `pending_update` and prior `pending_delete` still converges through correct path
- same-id recreate path being selected only for update-sourced `keep mine`
- canonical slug reconciliation after same-id recreate when backend returns a different slug
- delete-sourced remote deletion clearing local state without surfacing a new conflict

- [ ] **Step 2: Run the focused sync tests**

Run:
- `cd apps/lyron_app && flutter test test/infrastructure/song_library/supabase_song_mutation_repository_test.dart`
- `cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart`

Expected: FAIL because remote-deletion classification does not exist yet.

- [ ] **Step 3: Implement the minimal sync-type and repository changes**

Update the song sync types and remote repository so they:
- add explicit remote-deletion error classification
- preserve `conflictSourceSyncStatus` for recovery decisions
- persist remote-deletion classification through existing mutation metadata so restart and retry preserve recovery semantics
- map update-style `song_not_found` into explicit recovery state
- map delete-style `song_not_found` into accepted delete convergence
- keep conflict-sourced update versus conflict-sourced delete resolution distinct after remote deletion classification
- route update-sourced `keep mine` to same-id recreation instead of ordinary overwrite retry

- [ ] **Step 4: Re-run the focused sync tests**

Run the same two commands again.

Expected: PASS.

### Task 3: Implement Store And Sync-Controller Convergence Rules

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/drift_song_mutation_store.dart`
- Modify: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`
- Modify: `apps/lyron_app/test/application/song_library/song_mutation_sync_controller_test.dart`
- Modify: `apps/lyron_app/test/offline/song_catalog/song_catalog_store_test.dart`
- Modify: `apps/lyron_app/test/application/song_library/song_library_service_test.dart`

- [ ] **Step 1: Write the failing local convergence tests**

Add coverage for:
- update-sourced remote deletion becoming explicit recovery state
- conflict-sourced update remote deletion preserving explicit keep/discard recovery
- `discard mine` removing the local song row when no canonical song remains
- delete-sourced remote deletion clearing the local pending delete
- conflict-sourced delete remote deletion converging to accepted deletion for both explicit choices
- auto-resolving previously conflicting delete rows when remote disappearance means both actions now converge to accepted deletion
- update-sourced `keep mine` reconciling the recreated canonical row back to `synced`
- preserving durable failure state when recreate or discard later fails

- [ ] **Step 2: Run the focused local convergence tests**

Run:
- `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`
- `cd apps/lyron_app && flutter test test/application/song_library/song_library_service_test.dart`
- `cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart`

Expected: FAIL because the local store and controller do not yet implement the new convergence rules.

- [ ] **Step 3: Implement the local convergence behavior**

Update the controller and store so they:
- persist explicit remote-deletion recovery state for update-sourced rows
- keep persisted remote-deletion classification owned by existing local mutation metadata encoding and decoding in `drift_song_mutation_store.dart` plus underlying `song_catalog_store.dart` persistence, not by transient controller-only flags
- preserve original conflict intent so update-origin and delete-origin conflict rows resolve differently after remote deletion
- clear delete-sourced rows when remote deletion already matches local intent
- allow `discard mine` to converge without fetching a non-existent canonical row
- reconcile recreated canonical songs back into the active local catalog
- keep unsynced-state accounting correct after convergence

- [ ] **Step 4: Re-run the focused local convergence tests**

Run the same three commands again.

Expected: PASS.

### Task 4: Add Planning And Reader Tombstone-Style Reference Handling

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context_provider.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context_resolver.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_provider_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write the failing reference-behavior tests**

Add coverage for:
- session-scoped reader route remaining valid when the planning item still exists but the canonical song row is gone
- reader rendering preserved planning title plus deleted-song messaging instead of bare not-found
- unresolved update-sourced remote-delete conflict rendering read-only deleted/conflict messaging instead of local draft song body
- discard-path tombstone copy using preserved planning title instead of discarded local draft title
- planning detail continuing to show human-readable song title for affected session items
- tombstone state not showing bare `songId`
- tombstone state not using generic `Song not found` as primary copy
- tombstone state hiding edit affordance
- ordinary direct song lookup still behaving like normal catalog not-found when no planning context exists

- [ ] **Step 2: Run the focused reference-behavior tests**

Run:
- `cd apps/lyron_app && flutter test test/presentation/song_reader/session_scoped_reader_context_provider_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart`

Expected: FAIL because reader/reference recovery UI does not yet exist.

- [ ] **Step 3: Implement the minimal tombstone-style UI behavior**

Update the planning and reader flow so it:
- keeps session-scoped context resolution anchored to preserved planning data even when catalog canonicalization cannot find canonical song row
- uses preserved planning reference data when canonical song loading fails inside session-scoped reader context
- renders a deleted-song informational state with planning-owned preserved title
- keeps tombstone copy aligned with spec minimum contract: preserved title, deleted or unavailable label, no bare `songId`, no generic primary not-found copy, no edit affordance
- avoids pretending the missing canonical song is still editable or fully readable
- keeps ordinary non-context song routes unchanged

- [ ] **Step 4: Re-run the focused reference-behavior tests**

Run the same four commands again.

Expected: PASS.

### Task 5: Prove End-To-End Remote-Deleted Convergence

**Files:**
- Modify: `apps/lyron_app/test/integration/local_first_song_crud_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/plan_session_reader_flow_test.dart`
- Reference: `docs/testing/testing-strategy.md`

- [ ] **Step 1: Write the failing integration coverage**

Add integration tests for:
- remote delete versus local pending update, followed by `keep mine` same-id recreation
- remote delete versus local pending update, followed by `discard mine`
- remote delete versus local pending delete converging as accepted deletion
- session-scoped reader showing deleted-song messaging from preserved planning data after canonical song removal

- [ ] **Step 2: Run the focused integration suite**

Run:
- `cd apps/lyron_app && flutter test test/integration/local_first_song_crud_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/plan_session_reader_flow_test.dart`

Expected: FAIL until Tasks 1-4 are complete.

- [ ] **Step 3: Re-run after implementation**

Run the same two commands again after Tasks 1-4 are complete.

Expected: PASS.

### Task 6: Close Documentation And Deferred-State Loop

**Files:**
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/architecture/decisions/ADR-013-song-write-sync-boundary.md` or add follow-up ADR if this contract needs separate decision record
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/deferred/2026-04-08-offline-song-crud.md`

- [ ] **Step 1: Update durable documentation**

Document:
- explicit remote-deletion convergence rules
- same-id recreation semantics for update-sourced `keep mine`
- delete-sourced accepted convergence
- planning and reader preserved-reference behavior

- [ ] **Step 2: Remove or supersede the deferred gap**

Update `docs/deferred/2026-04-08-offline-song-crud.md` in the same implementation change so the repository no longer shows this correctness gap as still unresolved.

- [ ] **Step 3: Run final focused verification**

Run:
- `bash scripts/tests/song-crud-write-contract-test.sh`
- `cd apps/lyron_app && flutter test test/infrastructure/song_library/supabase_song_mutation_repository_test.dart`
- `cd apps/lyron_app && flutter test test/application/song_library/song_mutation_sync_controller_test.dart`
- `cd apps/lyron_app && flutter test test/offline/song_catalog/song_catalog_store_test.dart`
- `cd apps/lyron_app && flutter test test/application/song_library/song_library_service_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/song_reader/session_scoped_reader_context_provider_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/song_reader/song_reader_screen_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart`
- `cd apps/lyron_app && flutter test test/integration/local_first_song_crud_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/plan_session_reader_flow_test.dart`

Expected: PASS.
