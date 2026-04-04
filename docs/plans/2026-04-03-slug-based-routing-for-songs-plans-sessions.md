# Slug-Based Routing For Songs, Plans, And Sessions Implementation Plan

> Status: Proposed

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move public song, plan, and session routes to slug-based URL segments while keeping ids as the canonical internal identifiers, and simplify scoped reader URLs so session-scoped song entry no longer exposes a session-item segment.

**Architecture:** Add slug columns and scoped uniqueness constraints in Postgres, backfill development data, and then introduce a thin slug-resolution seam at the route boundary. Router and navigation helpers will speak slug-based URLs, repositories, local stores, and reader context will continue to use ids after route resolution, and scoped reader entry will rely on the product rule that a song can appear only once within a session.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, Supabase Postgres migrations, Supabase seed data, Flutter test, integration test, Markdown

---

### Task 1: Add Database Slug Columns And Backfill Rules

**Files:**
- Create: `supabase/migrations/<next>_add_song_plan_session_slugs.sql`
- Modify: `supabase/seed/seed.sql`
- Modify: `docs/specs/2026-04-03-slug-based-routing-for-songs-plans-sessions.md`
- Test: `scripts/tests/` if an existing migration test harness is available
- Reference: `docs/domain/domain-model.md`

- [ ] **Step 1: Write the failing migration or schema verification test**

Add or extend the repository's schema verification flow so it proves:

- `songs.slug` exists and is unique within `organization_id`
- `plans.slug` exists and is unique within `organization_id`
- `sessions.slug` exists and is unique within `plan_id`
- existing rows can be backfilled without null slugs

- [ ] **Step 2: Run the focused schema verification to confirm it fails**

Run the repository's existing migration validation command for Supabase schema checks.

Expected: FAIL because the current schema does not define those slug columns or constraints.

- [ ] **Step 3: Add the migration**

Create a new Supabase migration that:

- adds the `songs.slug`, `plans.slug`, and `sessions.slug` columns
- backfills base slugs from `title` or `name`
- resolves collisions with scoped numeric suffixes
- marks the slug columns `not null`
- adds the required unique constraints

Keep the historical initial schema file unchanged so the new migration remains the single source of truth for slug-column DDL.

- [ ] **Step 4: Update seed data if needed**

Ensure seed inserts remain valid once slug columns are required.

- [ ] **Step 5: Re-run schema verification**

Run the same migration validation command again.

Expected: PASS.

### Task 2: Record Slug Fields In Domain Documentation

**Files:**
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md` if route resolution becomes an explicit application pattern
- Modify: `docs/testing/testing-strategy.md` if new standing test requirements are introduced
- Reference: `docs/specs/2026-04-03-slug-based-routing-for-songs-plans-sessions.md`

- [ ] **Step 1: Update the domain model doc**

Add `slug` to the key fields for songs, plans, and sessions, document the intended uniqueness scope for each aggregate, and record that a session may contain a given song at most once so the public scoped reader URL does not need a separate session-item segment.

- [ ] **Step 2: Update architecture and testing docs only if the implementation introduces durable new boundaries**

Document the route-resolution seam and the expected migration and not-found coverage if those become standing repository rules.

### Task 3: Add Slug Lookup Support Without Changing Internal Id Contracts

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_catalog_read_repository.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/song_library_service.dart`
- Modify: `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart`
- Modify: `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_store.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`
- Modify: `apps/lyron_app/lib/src/domain/song/song_summary.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/plan_summary.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/session_summary.dart`
- Modify: `apps/lyron_app/lib/src/domain/planning/session_item_summary.dart`
- Test: `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`
- Test: `apps/lyron_app/test/application/song_library/song_library_service_test.dart`
- Test: `apps/lyron_app/test/application/planning/active_planning_context_controller_test.dart`
- Test: `apps/lyron_app/test/offline/planning/planning_local_store_test.dart`

- [ ] **Step 1: Write failing repository tests for slug lookups**

Add tests that prove repositories can resolve:

- song route metadata to a slug-bearing view model and the underlying song id within the active organization
- plan route metadata to a slug-bearing view model and the underlying plan id within the active organization
- session route metadata to a slug-bearing view model and the underlying session id within a resolved plan

Also add failure tests for missing slugs.

- [ ] **Step 2: Run the focused repository tests**

Run:

- `cd apps/lyron_app && flutter test test/infrastructure/song_library/local_first_song_repository_test.dart`
- `cd apps/lyron_app && flutter test test/infrastructure/song_library/supabase_song_repository_test.dart`
- `cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_repository_test.dart`

Expected: FAIL because slug lookup contracts do not exist yet.

- [ ] **Step 3: Add the minimal lookup API**

Extend the concrete read seams with narrowly-scoped lookup methods or route-facing DTOs that return ids plus slug metadata, instead of changing the existing detail and reader methods to slug-first.

- [ ] **Step 4: Implement the lookup paths**

Implement slug lookup against `SongCatalogReadRepository` -> `SongLibraryService` -> `SongCatalogStore` for songs and `PlanningLocalReadRepository` -> `PlanningLocalStore` for plans and sessions, while preserving all existing id-based list, detail, and reader methods.

- [ ] **Step 5: Re-run the focused repository tests**

Run the same three test commands again.

Expected: PASS.

### Task 4: Change Route Definitions And Navigation Helpers To Slugs

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_routes.dart`
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_routes.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Test: `apps/lyron_app/test/router/app_router_test.dart`
- Test: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`
- Test: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write failing router tests for slug-based canonical paths**

Update the router tests so they expect:

- `/songs/:songSlug`
- `/plans/:planSlug`
- `/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug`

Also cover direct entry and invalid-slug not-found behavior.

- [ ] **Step 2: Run the focused router and presentation tests**

Run:

- `cd apps/lyron_app && flutter test test/router/app_router_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/song_library/song_list_screen_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_list_screen_test.dart`
- `cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart`

Expected: FAIL because route templates and route builders still emit id-based URLs.

- [ ] **Step 3: Update route constants and route helpers**

Change route parameter names and helper methods to construct slug-based URLs only.

- [ ] **Step 4: Add route-bound slug resolution**

Update router entry points so they resolve slugs to ids before instantiating the existing screens and provider flows.

Use a dedicated async route-resolution boundary so slug lookups can surface a loading state while the route is resolving and can short-circuit to explicit not-found behavior before the current screen/provider trees mount.

Update the route-facing summary/view-model objects so the screens have the slug values they need to build canonical URLs without mutating the internal id-based reader context.

- [ ] **Step 5: Keep reader context id-based after resolution**

Verify the scoped reader screen still receives ids for `planId`, `sessionId`, `sessionItemId`, and `songId` after the router resolves `planSlug`, `sessionSlug`, and `songSlug` to the single matching session item in that session.

- [ ] **Step 6: Re-run the focused router and presentation tests**

Run the same four test commands again.

Expected: PASS.

### Task 5: Prove The Full User Flows Still Work

**Files:**
- Modify: `apps/lyron_app/test/integration/song_reader_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/plan_session_reader_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/plan_and_session_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/local_first_planning_read_flow_test.dart`
- Reference: `apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart`

- [ ] **Step 1: Write or update integration expectations for slug-based entry**

Update the integration tests so they enter song, plan, and scoped reader flows through slug-based URLs and still verify the same visible outcomes.

- [ ] **Step 2: Run the focused integration suite**

Run:

- `cd apps/lyron_app && flutter test test/integration/song_reader_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/plan_session_reader_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/plan_and_session_flow_test.dart`
- `cd apps/lyron_app && flutter test test/integration/local_first_planning_read_flow_test.dart`

Expected: FAIL before the implementation is complete, then PASS once routing and lookup behavior land.

### Task 6: Final Verification

**Files:**
- Modify: any files touched during implementation

- [ ] **Step 1: Run the complete targeted verification set**

Run the focused repository, router, presentation, and integration tests from the earlier tasks.

Expected: PASS.

- [ ] **Step 2: Run formatter or generators only where needed**

Run the repository's normal formatting and code generation commands for the files changed in this slice.

- [ ] **Step 3: Review docs and route helpers together**

Confirm the spec, plan, and domain documentation all match the shipped slug boundaries:

- songs unique within organization
- plans unique within organization
- sessions unique within plan
- a session can contain a given song at most once
- no redirect support
- ids remain internal
