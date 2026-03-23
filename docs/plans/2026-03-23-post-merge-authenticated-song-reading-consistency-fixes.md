# Post-Merge Authenticated Song Reading Consistency Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the post-merge consistency issues in the authenticated local Supabase song-reading slice without widening scope or changing the intended architecture.

**Architecture:** Keep the authenticated slice backend-owned and explicit. Remove the hidden asset fallback from the authenticated song repository boundary, make local demo provisioning truly idempotent, surface startup auth bootstrap behavior in an executable way, and align failure semantics and documentation with the implemented backend-only reading path.

**Tech Stack:** Flutter, Riverpod, go_router, Supabase local scripts, Flutter widget tests, Dart unit tests, SQL schema constraints, repository documentation

---

### Task 1: Make Demo Provisioning Truly Idempotent

**Files:**
- Modify: `supabase/migrations/202603210001_initial_schema.sql`
- Modify: `scripts/provision-local-demo-user.sh`
- Test: `scripts/tests/provision-local-demo-user-test.sh`

- [ ] **Step 1: Write the failing provisioning regression test**

Add `scripts/tests/provision-local-demo-user-test.sh` to prove that running the provisioning path twice does not create duplicate organization-scoped memberships for the demo user.

- [ ] **Step 2: Run the provisioning regression test to verify it fails**

Run: `scripts/tests/provision-local-demo-user-test.sh`
Expected: FAIL because the current nullable `group_id` unique key does not prevent duplicate organization-scoped memberships.

- [ ] **Step 3: Implement the minimal schema and script fix**

Add a repository-owned uniqueness rule that makes organization-scoped memberships idempotent even when `group_id` is `null`, then keep `scripts/provision-local-demo-user.sh` aligned with the new conflict target.

If older local databases already contain duplicated organization-scoped memberships from the pre-fix workflow, repair them inside the migration before recreating the unique index. Keep the earliest duplicate row by `created_at, id`.

- [ ] **Step 4: Re-run the provisioning regression test to verify it passes**

Run: `scripts/tests/provision-local-demo-user-test.sh`
Expected: PASS with one organization-scoped membership after repeated provisioning.

### Task 2: Remove Hidden Asset Fallback From The Authenticated Slice

**Files:**
- Modify: `apps/lyrica_app/lib/src/presentation/song_library/song_library_providers.dart`
- Modify: `apps/lyrica_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyrica_app/test/presentation/song_library/song_library_providers_test.dart`
- Modify: `apps/lyrica_app/test/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Write failing tests for backend-only repository ownership**

Add tests proving that the authenticated app slice does not read bundled song assets when auth is not ready or signed out, and that the signed-out experience is handled by auth/routing rather than an asset-backed song catalog.

- [ ] **Step 2: Run the focused provider and song-list tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_library/song_library_providers_test.dart test/presentation/song_library/song_list_screen_test.dart`
Expected: FAIL because the current provider graph falls back to `AssetSongRepository`.

- [ ] **Step 3: Implement the minimal provider fix**

Keep the repository boundary backend-only for this slice and let auth/routing own signed-out handling instead of falling back to bundled assets.

- [ ] **Step 4: Re-run the focused provider and song-list tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/presentation/song_library/song_library_providers_test.dart test/presentation/song_library/song_list_screen_test.dart`
Expected: PASS.

### Task 3: Make Auth Bootstrap And Reader Failure Semantics Match The Spec

**Files:**
- Modify: `apps/lyrica_app/lib/src/application/auth/app_auth_controller.dart`
- Modify: `apps/lyrica_app/lib/src/domain/song/song_not_found_exception.dart`
- Create: `apps/lyrica_app/lib/src/domain/song/song_access_denied_exception.dart`
- Modify: `apps/lyrica_app/lib/src/infrastructure/song_library/supabase_song_repository.dart`
- Modify: `apps/lyrica_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyrica_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyrica_app/test/app/lyrica_app_test.dart`
- Modify: `apps/lyrica_app/test/router/app_router_test.dart`
- Modify: `apps/lyrica_app/test/infrastructure/song_library/supabase_song_repository_test.dart`
- Modify: `apps/lyrica_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [ ] **Step 1: Write failing tests for startup bootstrap and denied/not-found mapping**

Add tests that prove:
- app startup can remain in an executable initializing state before auth restoration completes
- access-denied reader failures are handled separately from not-found failures
- transient backend failures still show retryable UI

- [ ] **Step 2: Run the focused auth, router, repository, and reader tests to verify they fail**

Run: `cd apps/lyrica_app && flutter test test/app/lyrica_app_test.dart test/router/app_router_test.dart test/infrastructure/song_library/supabase_song_repository_test.dart test/presentation/song_reader/song_reader_screen_test.dart`
Expected: FAIL because the current implementation redirects immediately during bootstrap and collapses denied/not-found behavior.

- [ ] **Step 3: Implement the minimal auth and failure-semantics fix**

Keep auth bootstrap centralized, preserve the signed-out route policy, add an executable initializing surface, and map denied/not-found outcomes explicitly at the repository boundary and reader UI.

- [ ] **Step 4: Re-run the focused tests to verify they pass**

Run: `cd apps/lyrica_app && flutter test test/app/lyrica_app_test.dart test/router/app_router_test.dart test/infrastructure/song_library/supabase_song_repository_test.dart test/presentation/song_reader/song_reader_screen_test.dart`
Expected: PASS.

### Task 4: Align Specs, Plans, And Repository Docs With The Corrected Slice

**Files:**
- Modify: `README.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `docs/specs/2026-03-23-executable-local-supabase-authenticated-song-reading.md`
- Modify: `docs/plans/2026-03-23-executable-local-supabase-authenticated-song-reading.md`

- [ ] **Step 1: Update repository docs to describe the backend-only authenticated slice accurately**

Remove stale wording that still presents the current catalog as asset-backed for this slice, add the new post-merge plan reference where useful, and make failure semantics and bootstrap behavior match the implemented flow.

- [ ] **Step 2: Verify documentation consistency by re-reading the updated files**

Run: `sed -n '1,240p' README.md docs/domain/domain-model.md docs/testing/testing-strategy.md docs/specs/2026-03-23-executable-local-supabase-authenticated-song-reading.md`
Expected: The docs consistently describe backend-only authenticated reads, app-local parsing/rendering, backend-enforced authorization, and the real local workflow.

### Task 5: Run Full Verification

**Files:**
- Modify: none

- [ ] **Step 1: Run the full local verification path**

Run: `./scripts/verify.sh`
Expected: PASS.

- [ ] **Step 2: Re-run the provisioning regression test after full verification**

Run: `scripts/tests/provision-local-demo-user-test.sh`
Expected: PASS.
