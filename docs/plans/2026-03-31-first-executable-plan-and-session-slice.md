# First Executable Plan And Session Slice Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the active planning model to `plan -> session -> session_items`, seed executable planning data in local Supabase, and add a minimal authenticated read-only planning flow in Flutter without introducing planning writes or a local planning cache.

**Architecture:** Replace the current local schema ownership path from `sessions.event_id` to `sessions.plan_id`, remove `events` from the active planning baseline, and keep planning reads online-only behind explicit repository boundaries. Add one planning read model for plan summaries and one for plan detail with ordered sessions and ordered song-backed session items, then expose that through a dedicated signed-in plan list route and plan detail route without changing the current song-list home landing.

**Tech Stack:** Supabase Postgres migrations and seed SQL, Flutter, Riverpod, go_router, Supabase Flutter, Dart, Flutter test, integration test, Markdown

---

### Task 1: Lock In The Simplified Planning Schema With Failing Local SQL Verification

**Files:**
- Modify: `supabase/migrations/202603210001_initial_schema.sql`
- Modify: `supabase/seed/seed.sql`
- Reference: `docs/specs/2026-03-31-first-executable-plan-and-session-slice.md`
- Reference: `scripts/supabase.sh`

- [ ] **Step 1: Add a failing schema verification command for the current baseline**

First run:

```bash
./scripts/db-reset.sh
```

Expected: PASS, rebuilding the local database from the repository-owned migration and seed baseline before any assertions.

Run:

```bash
./scripts/supabase.sh db query "select column_name from information_schema.columns where table_schema = 'public' and table_name = 'sessions' order by ordinal_position;"
```

Expected: the current baseline still shows `event_id` and does not yet show the required `plan_id` plus `position` shape.

- [ ] **Step 2: Add a failing schema verification for dormant `events` dependency**

Run:

```bash
./scripts/supabase.sh db query "select constraint_name from information_schema.table_constraints where table_schema = 'public' and table_name in ('events','sessions') order by table_name, constraint_name;"
```

Expected: the current baseline still contains `events` ownership constraints and session foreign keys tied to `events`.

- [ ] **Step 3: Add a failing schema verification for session ordering uniqueness**

Run:

```bash
./scripts/supabase.sh db query "select constraint_name from information_schema.table_constraints where table_schema = 'public' and table_name = 'sessions' and constraint_type = 'UNIQUE' order by constraint_name;"
```

Expected: FAIL to show the required unique session ordering constraint on `(plan_id, position)` because the current baseline does not yet use that ownership model.

- [ ] **Step 4: Rewrite the planning tables in the local schema baseline**

Update `supabase/migrations/202603210001_initial_schema.sql` so that:

1. `public.events` is removed from the active local baseline
2. `public.sessions` uses `plan_id uuid not null`
3. `public.sessions` adds `position integer not null`
4. `unique (plan_id, position)` becomes the session-ordering constraint
5. all relevant foreign keys, indexes, helper functions, policies, and triggers follow the new ownership path

Do not introduce a separate transitional legacy path for `events` in this local-only slice.

- [ ] **Step 5: Re-run the focused schema verification queries**

First run:

```bash
./scripts/db-reset.sh
```

Expected: PASS, applying the updated schema and seed baseline cleanly.

Then run:

```bash
./scripts/provision-local-demo-user.sh
```

Expected: PASS, restoring the local demo auth fixture after reset.

Run:

```bash
./scripts/supabase.sh db query "select column_name from information_schema.columns where table_schema = 'public' and table_name = 'sessions' order by ordinal_position;"
./scripts/supabase.sh db query "select table_name from information_schema.tables where table_schema = 'public' and table_name in ('plans','events','sessions','session_items') order by table_name;"
./scripts/supabase.sh db query "select constraint_name from information_schema.table_constraints where table_schema = 'public' and table_name = 'sessions' and constraint_type = 'UNIQUE' order by constraint_name;"
```

Expected:

1. `sessions` includes `plan_id` and `position`
2. `events` is no longer required as an active planning table in the local baseline
3. `plans`, `sessions`, and `session_items` remain present
4. the `sessions` table includes the required unique ordering constraint for `(plan_id, position)`

### Task 2: Seed Real Planning Fixtures And Prove Visibility Boundaries

**Files:**
- Modify: `supabase/seed/seed.sql`
- Reference: `supabase/migrations/202603210001_initial_schema.sql`
- Reference: `docs/specs/2026-03-31-first-executable-plan-and-session-slice.md`

- [ ] **Step 1: Add a failing seed verification query for visible planning fixtures**

First run:

```bash
./scripts/db-reset.sh
```

Expected: PASS, rebuilding from the current baseline before checking planning fixtures.

Then run:

```bash
./scripts/provision-local-demo-user.sh
```

Expected: PASS, restoring the demo auth fixture after reset.

Run:

```bash
./scripts/supabase.sh db query "select p.name as plan_name, s.name as session_name, si.position, song.title from public.plans p join public.sessions s on s.plan_id = p.id and s.organization_id = p.organization_id join public.session_items si on si.session_id = s.id and si.organization_id = s.organization_id join public.songs song on song.id = si.song_id and song.organization_id = si.organization_id where p.organization_id = '11111111-1111-1111-1111-111111111111' order by p.name, s.position, si.position;"
```

Expected: FAIL or empty result because the current seed does not yet create planning fixtures.

- [ ] **Step 2: Add visible and hidden planning fixtures to the seed**

Update `supabase/seed/seed.sql` to create:

1. one simple single-session demo plan in the demo organization
2. one multi-session demo plan in the demo organization
3. ordered `session_items` in each seeded session referencing existing demo songs
4. one hidden-organization plan with at least one session and one song-backed session item
5. explicit timestamps and IDs that exercise plan ordering, for example:
   - one earlier `scheduled_for`
   - one later `scheduled_for`
   - at least one `scheduled_for = null`
   - deterministic `updated_at` values so the tie-breaker path is provable when needed

For this slice:

1. keep seeded plans organization-scoped with `group_id = null`
2. keep seeded sessions aligned to the owning plan organization and `group_id`
3. use stable explicit `position` values for sessions and session items

- [ ] **Step 3: Re-run the visible planning fixture query**

First run:

```bash
./scripts/db-reset.sh
```

Expected: PASS, loading the revised planning fixtures into a clean local database.

Then run:

```bash
./scripts/provision-local-demo-user.sh
```

Expected: PASS, restoring the demo auth fixture after reset.

Run:

```bash
./scripts/supabase.sh db query "select p.name as plan_name, s.name as session_name, s.position as session_position, si.position as item_position, song.title from public.plans p join public.sessions s on s.plan_id = p.id and s.organization_id = p.organization_id join public.session_items si on si.session_id = s.id and si.organization_id = s.organization_id join public.songs song on song.id = si.song_id and song.organization_id = si.organization_id where p.organization_id = '11111111-1111-1111-1111-111111111111' order by p.scheduled_for nulls last, p.updated_at desc, p.id, s.position, si.position;"
```

Expected: PASS with ordered demo planning rows.

- [ ] **Step 4: Add a failing hidden-organization visibility query**

Run:

```bash
status_env="$("./scripts/supabase.sh" status -o env)" && eval "$status_env" && psql "$DB_URL" -c "select organization_id, name from public.plans where organization_id = '11111111-1111-1111-1111-111111111112';"
```

Expected: PASS as an admin-style local check, confirming the hidden planning fixture exists for later authorization tests.

- [ ] **Step 5: Add a failing signed-in visibility proof for the demo user**

Run:

```bash
./scripts/provision-local-demo-user.sh
status_env="$("./scripts/supabase.sh" status -o env)" && eval "$status_env" && cd apps/lyron_app && flutter test test/integration/plan_and_session_flow_test.dart --plain-name "demo user cannot read hidden-organization plans" --dart-define=SUPABASE_URL="$API_URL" --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
```

Expected: FAIL because the planning integration test does not yet exist.

### Task 3: Add Planning Domain Models And Repository Contracts With Focused Unit Tests

**Files:**
- Create: `apps/lyron_app/lib/src/domain/planning/plan_summary.dart`
- Create: `apps/lyron_app/lib/src/domain/planning/plan_detail.dart`
- Create: `apps/lyron_app/lib/src/domain/planning/planning_repository.dart`
- Create: `apps/lyron_app/lib/src/domain/planning/session_summary.dart`
- Create: `apps/lyron_app/lib/src/domain/planning/session_item_summary.dart`
- Create: `apps/lyron_app/test/domain/planning/plan_detail_test.dart` if pure model behavior warrants it
- Create: `apps/lyron_app/test/infrastructure/planning/supabase_planning_repository_test.dart`
- Reference: `apps/lyron_app/lib/src/domain/song/song_summary.dart`

- [ ] **Step 1: Add a failing repository test for `listPlans()` ordering**

Create `apps/lyron_app/test/infrastructure/planning/supabase_planning_repository_test.dart` with a test that proves `listPlans()` returns visible plans in:

1. `scheduled_for` ascending with null values last
2. `updated_at` descending tie-breaker
3. `id` ascending final tie-breaker

Use deterministic fixture rows or repository mapping doubles, not widget assertions.

- [ ] **Step 2: Add a failing repository test for `getPlanDetail(planId)` shape**

Add a test that proves `getPlanDetail(planId)` returns:

1. one plan
2. sessions ordered by `position`
3. session items ordered by `position`
4. embedded song summary fields required to render titles without extra per-item song fetches

- [ ] **Step 3: Add a failing repository test for missing-song references**

Add a test that proves if a readable plan detail contains a `session_item` whose referenced song cannot be resolved in the readable projection, the repository returns a failure instead of silently dropping that item.

- [ ] **Step 4: Create the planning domain models and repository contract**

Add the minimal planning domain and repository files required for this slice. Keep them read-only and narrowly scoped to:

1. plan summaries for list rendering
2. plan detail with sessions and song-backed session items

Do not introduce write-side entities, sync queue concepts, or speculative nested-list abstractions.

- [ ] **Step 5: Run the focused planning repository tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_repository_test.dart
```

Expected: FAIL because the planning repository implementation does not yet exist.

### Task 4: Implement The Supabase Planning Read Path

**Files:**
- Create: `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_repository.dart`
- Modify: `apps/lyron_app/lib/src/application/providers.dart`
- Modify: `apps/lyron_app/test/application/providers_test.dart`
- Modify: `apps/lyron_app/test/infrastructure/planning/supabase_planning_repository_test.dart`
- Reference: `apps/lyron_app/lib/src/infrastructure/song_library/supabase_song_repository.dart`
- Reference: `apps/lyron_app/lib/src/infrastructure/auth/supabase_auth_repository.dart`

- [ ] **Step 1: Implement `listPlans()`**

Implement the smallest Supabase-backed read path that returns the visible plan summaries for the signed-in scope using the spec’s ordering rules.

Keep the query logic repository-owned. Do not push joins or ordering logic into widgets.

- [ ] **Step 2: Add one backend-owned visibility seam for consistent plan list and detail reads**

Implement one repository-owned backend seam so `listPlans()` and `getPlanDetail(planId)` share the same effective read gate:

1. either stricter read policies on the planning tables
2. or one secured view / RPC / query path that exposes only plans the signed-in user may both list and open

Do not rely on widget-side filtering of plan summaries. Backend ownership of authorization is required.

- [ ] **Step 3: Implement `getPlanDetail(planId)`**

Implement the plan detail read path so it returns:

1. the visible plan summary
2. ordered sessions
3. ordered song-backed session items
4. enough song summary data for display without extra per-item song fetches

Use the smallest repository-owned approach that keeps the UI simple, whether through joined queries, a view, an RPC, or multiple repository-controlled requests.

- [ ] **Step 4: Wire the planning repository into provider composition**

Add provider wiring in `apps/lyron_app/lib/src/application/providers.dart` for:

1. a `PlanningRepository`
2. only shared composition-root dependencies

Keep this slice online-only. Do not add a Drift planning cache or a local planning read model.

- [ ] **Step 5: Re-run the focused planning repository and provider tests**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/infrastructure/planning/supabase_planning_repository_test.dart \
  test/application/providers_test.dart
```

Expected: PASS.

### Task 5: Add Planning Presentation State And Read-Only Screens

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Create: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`
- Create: `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`
- Create: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart` if new user-facing copy is needed
- Reference: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Reference: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`

- [ ] **Step 1: Add a failing widget test for plan list rendering**

Create `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart` with a test that proves the screen renders visible plan summaries from provider overrides in the required order.

- [ ] **Step 2: Add a failing widget test for plan detail rendering**

Create `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart` with a test that proves:

1. sessions render in ascending `position`
2. song-backed session items render in ascending `position`
3. multiple sessions are visibly distinct within one plan

- [ ] **Step 3: Add a failing widget test for plan-detail error handling**

Add a test that proves a plan-detail load failure renders an explicit failure surface rather than silently showing incomplete session data.

- [ ] **Step 4: Implement the planning providers and screens**

Add the smallest presentation state and screens required for:

1. plan list loading
2. plan detail loading
3. ordered session rendering
4. ordered song title rendering
5. clear loading and failure states

Provider ownership for this slice must follow the existing app pattern:

1. `apps/lyron_app/lib/src/application/providers.dart` owns only shared infrastructure composition such as the `PlanningRepository`
2. `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart` owns feature-facing `FutureProvider` or equivalent read providers for plan list and plan detail

Do not add editing controls, reorder gestures, or final UX polish.

- [ ] **Step 5: Run the focused planning widget tests**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/planning/plan_list_screen_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart
```

Expected: PASS.

### Task 6: Add Signed-In Routing And Navigation Into The Planning Flow

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_routes.dart`
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/test/router/app_router_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Modify: `apps/lyron_app/test/app/lyron_app_test.dart` if the signed-in app shell expectations change

- [ ] **Step 1: Add a failing router test for signed-in planning routes**

Extend `apps/lyron_app/test/router/app_router_test.dart` with tests proving:

1. signed-in users can reach the planning list route
2. signed-in users can reach the plan detail route
3. signed-out users are redirected away from planning routes

- [ ] **Step 2: Add a failing widget test for navigation from the song list into planning**

Extend `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` with a test that proves the signed-in song list exposes a visible navigation affordance into the planning area.

- [ ] **Step 3: Implement route definitions and navigation wiring**

Update the router so that:

1. the existing signed-in home route still lands on the song list
2. a dedicated planning list route exists
3. a dedicated plan detail route exists
4. planning routes share the signed-in gate with the current home and song reader routes

Add the smallest visible entry point from the song list into the planning list route.

- [ ] **Step 4: Run the focused router and navigation tests**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/router/app_router_test.dart \
  test/presentation/song_library/song_list_screen_test.dart
```

Expected: PASS.

### Task 7: Add Backend-Backed Repository Integration Proof For The Planning Read Slice

**Files:**
- Create: `apps/lyron_app/test/integration/plan_and_session_flow_test.dart`
- Modify: `scripts/verify.sh` if this slice becomes part of the standard local verification path
- Reference: `apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart`
- Reference: `scripts/provision-local-demo-user.sh`
- Reference: `supabase/seed/seed.sql`

- [ ] **Step 1: Add a failing backend-backed integration test for visible demo planning data**

Create `apps/lyron_app/test/integration/plan_and_session_flow_test.dart` with a backend-backed integration test that:

1. signs in with the local demo user
2. instantiates the live Supabase-backed planning repository
3. loads the seeded visible plans
4. loads one seeded plan detail
5. verifies ordered sessions and ordered song-backed session items are returned

Use the same style as the existing backend-backed integration tests: live Supabase, repository/controller level, explicit env vars, no router-driven UI navigation.

- [ ] **Step 2: Add a failing backend-backed integration test for hidden-organization isolation**

Add a scenario that proves the signed-in demo user cannot load or navigate to hidden-organization planning data.

Prefer a repository-level proof that:

1. hidden plans do not appear in `listPlans()`
2. direct access to a hidden `planId` fails through the planning repository

- [ ] **Step 3: Implement only the minimum missing wiring required for integration**

If the integration tests expose repository, router, or widget gaps not already covered by unit and widget work, fix them in the narrowest layer responsible.

Do not widen the slice into planning writes or offline planning support.

- [ ] **Step 4: Run the focused integration test**

Run:

```bash
./scripts/provision-local-demo-user.sh
status_env="$("./scripts/supabase.sh" status -o env)" && eval "$status_env" && cd apps/lyron_app && flutter test test/integration/plan_and_session_flow_test.dart --dart-define=SUPABASE_URL="$API_URL" --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
```

Expected: PASS.

### Task 8: Update Canonical Docs And Re-Read The Slice End-To-End

**Files:**
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/product/vision.md`
- Modify: `docs/testing/testing-strategy.md` if this slice changes the standard backend-backed verification expectations
- Modify: `README.md` if repository-level guidance or current-slice summaries change
- Modify: `docs/specs/2026-03-31-first-executable-plan-and-session-slice.md` only if implementation reveals material spec drift
- Modify: `docs/plans/2026-03-31-first-executable-plan-and-session-slice.md`

- [ ] **Step 1: Update canonical repository docs to match the implemented planning shape**

Record the simplified `plan -> session -> session_items` direction and the first executable planning read slice in the canonical docs listed above.

Keep durable domain and architecture knowledge in repository docs, not only in the spec and plan.

- [ ] **Step 2: Re-read the spec and plan together**

Confirm the implementation plan still matches:

1. schema direction
2. seed fixtures
3. repository contract
4. authorization rules
5. route placement
6. testing expectations

If anything materially changed during implementation, update the spec and this plan in the same change.

- [ ] **Step 3: Run the focused end-to-end verification set**

Run:

```bash
./scripts/supabase.sh db query "select p.name, s.name, s.position, si.position from public.plans p join public.sessions s on s.plan_id = p.id and s.organization_id = p.organization_id join public.session_items si on si.session_id = s.id and si.organization_id = s.organization_id order by p.scheduled_for nulls last, p.updated_at desc, p.id, s.position, si.position;"
./scripts/provision-local-demo-user.sh
status_env="$("./scripts/supabase.sh" status -o env)" && eval "$status_env" && cd apps/lyron_app && flutter test \
  test/infrastructure/planning/supabase_planning_repository_test.dart \
  test/presentation/planning/plan_list_screen_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart \
  test/router/app_router_test.dart \
  test/integration/plan_and_session_flow_test.dart \
  --dart-define=SUPABASE_URL="$API_URL" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY"
```

Expected: PASS.

- [ ] **Step 4: Stage the slice once docs, code, and tests agree**

Run:

```bash
git add supabase/migrations/202603210001_initial_schema.sql supabase/seed/seed.sql apps/lyron_app/lib/src apps/lyron_app/test docs/domain/domain-model.md docs/architecture/architecture.md docs/product/vision.md README.md docs/specs/2026-03-31-first-executable-plan-and-session-slice.md docs/plans/2026-03-31-first-executable-plan-and-session-slice.md
```

Expected: staged planning slice changes only.

## File Map

- `supabase/migrations/202603210001_initial_schema.sql`
  Repository-owned local schema baseline; rewrite the planning ownership path from `event` to `plan`.
- `supabase/seed/seed.sql`
  Local demo and hidden planning fixtures for executable read validation.
- `apps/lyron_app/lib/src/domain/planning/`
  Read-only planning models and repository contract for this slice.
- `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_repository.dart`
  Online-only Supabase-backed planning reads.
- `apps/lyron_app/lib/src/application/providers.dart`
  Composition root for repository/provider wiring.
- `apps/lyron_app/lib/src/presentation/planning/`
  Minimal plan list and plan detail surfaces plus their presentation providers.
- `apps/lyron_app/lib/src/router/app_routes.dart`
  Route identifiers for planning list and plan detail.
- `apps/lyron_app/lib/src/router/app_router.dart`
  Signed-in navigation and route protection wiring.
- `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
  Small visible entry point from the signed-in song list into the planning area.
- `apps/lyron_app/test/infrastructure/planning/`
  Repository-level planning read tests.
- `apps/lyron_app/test/presentation/planning/`
  Widget tests for plan list and plan detail.
- `apps/lyron_app/test/router/app_router_test.dart`
  Route protection and navigation tests for the new planning routes.
- `apps/lyron_app/test/integration/plan_and_session_flow_test.dart`
  Backend-backed end-to-end proof for the new planning read slice.
