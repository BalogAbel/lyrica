# Periodic And Manual Song Catalog Refresh Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a visible manual catalog refresh action to the signed-in song list, refresh the authenticated catalog automatically every 5 minutes while the app is foregrounded in the signed-in flow, and tighten executable verification around the backend-backed refresh path without changing the current local-first or authorization boundaries.

**Architecture:** Extend the existing `SongCatalogController` so manual and periodic refresh share one guarded refresh path, with no overlapping refreshes and no cache restoration after explicit sign-out. Keep the full-snapshot replacement model, add one song-list sync affordance wired to the same controller, and verify the feature through focused controller/widget/integration tests plus a concrete CI gate update for backend-backed verification.

**Tech Stack:** Flutter, Riverpod, go_router, Supabase Flutter, Dart async/timers, Flutter test, GitHub Actions, Markdown

---

### Task 1: Lock In Refresh Scheduling And Sign-Out Safety With Controller Tests

**Files:**
- Modify: `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`
- Modify: `apps/lyron_app/test/application/providers_test.dart` only if a lifecycle seam is introduced there
- Modify: `apps/lyron_app/test/router/app_router_test.dart` only if mounted-flow activation is easiest to prove at router level
- Reference: `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`
- Reference: `apps/lyron_app/lib/src/application/providers.dart`

- [ ] **Step 1: Add a failing test for manual and periodic refresh sharing one guarded refresh path**

Extend `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart` with a test that proves:

1. a controller refresh can already be running
2. a second trigger arriving while that refresh is in flight does not start a concurrent duplicate fetch
3. the controller ends with one coherent snapshot update

Use a controllable fake repository with completers so the test can observe overlapping trigger attempts deterministically.

- [ ] **Step 2: Add a failing test for periodic refresh cadence**

Add a test that proves the scheduler fires only after the configured 5-minute interval and that it does not run while the controller is inactive.

Use `fake_async` or the repository’s preferred deterministic timer control so the test does not sleep in real time.

- [ ] **Step 3: Add a failing test for foreground-only periodic refresh**

Add a test that proves periodic refresh runs only while the app is in the foreground/resumed signed-in flow and does not fire while the lifecycle seam reports background/inactive state.

The test should use an explicit lifecycle dependency rather than relying on widget disposal as a proxy for app backgrounding.

- [ ] **Step 4: Add a failing test for sign-out during in-flight refresh**

Add a test that starts a refresh, calls the explicit sign-out path before the repository completes, then allows the in-flight refresh to finish.

Assert that:

1. the cached catalog is cleared
2. the controller returns to signed-out/initial catalog state
3. late refresh completion does not restore cached authenticated access

- [ ] **Step 5: Add a failing test for signed-out scheduler suppression**

Add a test that proves periodic refresh does not keep scheduling or executing once the user is signed out or once there is no current authenticated session.

- [ ] **Step 6: Add a failing test for mounted-flow deactivation**

Add a test that proves periodic refresh stops when the signed-in song-reading subtree unmounts even if the app remains foregrounded.

Prefer proving this through provider disposal or route-level unmounting rather than through sign-out, so the test covers the third part of the spec’s `active` definition explicitly.

- [ ] **Step 7: Run the focused controller tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart
```

Expected: FAIL because the current controller has no periodic scheduler contract and no explicit manual-vs-periodic overlap guard for this slice.

### Task 2: Implement Shared Refresh Scheduling In The Catalog Controller

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/catalog_snapshot_state.dart`
- Modify: `apps/lyron_app/lib/src/application/song_library/catalog_refresh_status.dart` only if required
- Modify: `apps/lyron_app/lib/src/application/song_library/catalog_connection_status.dart` only if required
- Modify: `apps/lyron_app/lib/src/application/providers.dart` if lifecycle wiring belongs at the composition root
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart` only if activation needs an explicit keep-alive point
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` only if activation needs an explicit keep-alive point
- Create or Modify: a narrow lifecycle seam near `apps/lyron_app/lib/src/application/` only if needed for deterministic tests
- Reference: `apps/lyron_app/lib/src/application/providers.dart`

- [ ] **Step 1: Introduce one explicit refresh entrypoint API**

Refactor `SongCatalogController` so both initial load, manual refresh, and periodic refresh call a single guarded refresh method.

Keep the current full-snapshot replacement semantics intact. Do not create separate refresh implementations per trigger.

- [ ] **Step 2: Add non-overlapping in-flight refresh protection**

Implement a guard so a second refresh trigger is ignored or coalesced while the current refresh is still running.

The implementation must keep one coherent state transition model and must not allow concurrent remote catalog fetches.

- [ ] **Step 3: Add a foreground-session periodic scheduler**

Add a 5-minute periodic scheduler owned by `SongCatalogController` or by a narrowly related helper if a helper is needed for testability.

The scheduler must:

1. start only while the signed-in song-reading flow is active
2. run only while an explicit lifecycle seam reports the app as foreground/resumed
3. trigger the same shared refresh path
4. stop on controller disposal
5. stop or become inert after explicit sign-out

Do not introduce platform background services or websocket subscriptions.

- [ ] **Step 4: Add the smallest lifecycle seam required**

Introduce the smallest explicit lifecycle dependency required to satisfy the spec’s definition of `active`.

Prefer a seam that can be driven deterministically in tests, for example:

```dart
abstract interface class AppForegroundState {
  bool get isForeground;
  Stream<bool> watchForeground();
}
```

Wire that seam from the composition root using the current Flutter lifecycle APIs only as far as needed. Do not spread `WidgetsBindingObserver` logic through presentation widgets for this slice.

- [ ] **Step 5: Make mounted-flow activation concrete with provider disposal**

Convert `songCatalogControllerProvider` and the directly dependent catalog-state providers to an `autoDispose` shape, and keep them owned by the signed-in song-list / reader subtree rather than the app root.

The implementation intent for this slice is:

1. foreground lifecycle controls whether polling is allowed while the signed-in flow exists
2. provider disposal controls whether polling survives after the signed-in song-reading subtree unmounts

Do not leave mounted-flow activation implicit.

- [ ] **Step 6: Preserve sign-out invalidation of in-flight work**

Ensure explicit sign-out still invalidates in-flight refresh generation so late repository completion cannot repopulate the cache or restore signed-in catalog state.

Reuse the current generation-based stale-result protection if it already fits; strengthen it only as far as needed for the new scheduler behavior.

- [ ] **Step 7: Re-run the focused controller tests to verify they pass**

Run:

```bash
cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart
```

Expected: PASS.

### Task 3: Add A Visible Manual Sync Affordance To The Song List

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Add a failing widget test for the visible sync affordance**

Extend `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` with a test that renders the signed-in song list and asserts that the app bar exposes a visible sync action alongside sign-out.

- [ ] **Step 2: Add a failing widget test for manual refresh invocation**

Add a test that taps the sync affordance and verifies the controller refresh path is invoked exactly once.

Use a test double or provider override that makes invocation observable without requiring backend traffic.

- [ ] **Step 3: Add a failing widget test for disabled/in-progress refresh affordance**

Add a test that renders the song list while the catalog is in `refreshing` state and verifies the sync affordance is disabled or otherwise prevented from retriggering refresh.

- [ ] **Step 4: Implement the sync affordance and wiring**

Update `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart` to add one visible sync action in the app bar.

The action should:

1. invoke the shared controller refresh path
2. remain available in the signed-in song list
3. not remove the existing sign-out action
4. avoid duplicate triggers while refresh is already in progress

Add any required user-facing string constants to `apps/lyron_app/lib/src/shared/app_strings.dart`.

- [ ] **Step 5: Run the focused song-list widget tests to verify they pass**

Run:

```bash
cd apps/lyron_app && flutter test test/presentation/song_library/song_list_screen_test.dart
```

Expected: PASS.

### Task 4: Prove Automatic Refresh State Visibility In Widget And Provider Tests

**Files:**
- Modify: `apps/lyron_app/test/presentation/song_library/song_library_providers_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Reference: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`

- [ ] **Step 1: Add a failing provider-level test for periodic refresh updating visible list data**

Extend `apps/lyron_app/test/presentation/song_library/song_library_providers_test.dart` or the nearest existing provider test file with a scenario where the active snapshot changes after a refresh and the visible song list reflects the updated cached catalog.

- [ ] **Step 2: Add a failing widget test for automatic refresh failure visibility**

Extend `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` with a scenario where:

1. cached catalog data exists
2. an automatic refresh fails
3. the song list remains visible
4. the persistent status surface shows the expected stale/offline failure messaging

- [ ] **Step 3: Implement only the minimum state/UI adjustments required**

If the existing status surface already covers the desired copy and states, keep it. Only add or refine state wiring if the tests prove a real gap.

Do not redesign the signed-in list screen for this slice.

- [ ] **Step 4: Run the focused provider and widget tests to verify they pass**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_library/song_library_providers_test.dart \
  test/presentation/song_library/song_list_screen_test.dart
```

Expected: PASS.

### Task 5: Extend Backend-Backed Integration Coverage For Manual And Periodic Refresh

**Files:**
- Modify: `apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart`
- Modify: `apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart`
- Modify: `scripts/verify.sh` if new integration env vars are required
- Reference: `scripts/provision-local-demo-user.sh`
- Reference: `supabase/seed/seed.sql`

- [ ] **Step 1: Add a failing backend-backed integration test for manual refresh**

Extend `apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart` with a scenario that:

1. signs in to local Supabase
2. loads the current catalog
3. changes backend-visible catalog data through a test-controlled path
4. triggers the manual refresh path
5. verifies the refreshed catalog reflects the backend change

Use the smallest explicit local-test mechanism already accepted in the repo to create backend change stimulus. If the current integration harness cannot mutate backend state from Flutter tests, add one narrow local-only test seam, for example:

- passing `SERVICE_ROLE_KEY` into the backend-backed integration tests and using a dedicated service-role test client only inside those tests, or
- adding one local-only helper path used exclusively by repository verification

Do not redesign the product backend contract for this.

- [ ] **Step 2: Add a failing backend-backed integration test for periodic refresh success after backend changes**

Extend the integration coverage with a second backend-backed scenario that:

1. signs in
2. establishes an initial catalog snapshot
3. mutates backend-visible song data through the same local-test mechanism
4. triggers the periodic refresh path deterministically without waiting 5 real minutes
5. verifies the active catalog reflects the backend change after the periodic refresh completes

- [ ] **Step 3: Add a failing local-first integration test for periodic refresh preserving cached behavior on failure**

Extend `apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart` with a scenario that:

1. creates a valid cached snapshot
2. simulates a periodic refresh attempt
3. forces refresh failure
4. proves the cached catalog remains readable
5. proves the state surfaces remain consistent with offline/refresh-failed behavior

- [ ] **Step 4: Keep periodic timing deterministic in tests**

Do not wait 5 real minutes in integration tests. Expose only the smallest seam needed to trigger the periodic refresh behavior deterministically in tests.

The seam must not become a production-only alternate refresh model.

- [ ] **Step 5: Run the focused backend-backed integration tests to verify they pass**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/integration/authenticated_song_reader_flow_test.dart \
  test/integration/local_first_authenticated_song_reader_flow_test.dart
```

When running outside the full verify script, pass the required `SUPABASE_URL` and `SUPABASE_ANON_KEY` values.

Expected: PASS with local Supabase running.

### Task 6: Tighten Repository Verification And CI For The Refresh Slice

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/verify.sh` only if needed for explicit refresh coverage
- Modify: `scripts/tests/verify-test.sh` if `scripts/verify.sh` changes
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/testing/testing-strategy.md`
- Modify: `README.md`
- Modify: `docs/workflows/development-workflow.md` if CI or local verification guidance changes

- [ ] **Step 1: Add a failing CI/workflow expectation**

Decide the concrete gate for this slice:

1. either CI runs `./scripts/verify.sh`
2. or CI runs a dedicated equivalent job that includes backend-backed authenticated song-reading verification

Capture that decision in tests or workflow assertions where feasible before editing the workflow.

- [ ] **Step 2: Update the workflow to execute backend-backed verification with required tooling**

Modify `.github/workflows/ci.yml` so this slice no longer relies only on `./scripts/verify.sh --skip-migrations` for pull requests affecting the current backend-backed refresh path.

Whichever concrete gate you choose, make the workflow executable in the same job by installing the required Supabase tooling dependencies there. For example:

1. add `actions/setup-node` before a full `./scripts/verify.sh` run, or
2. create a dedicated backend-verify job that installs Node, runs `npm ci --prefix tooling/supabase`, and then runs the backend-backed verify path

Prefer the smallest workflow change that actually enforces the documented gate.

- [ ] **Step 3: Update repository docs to match the real gate**

If CI or local verification behavior changes, update:

- `docs/architecture/architecture.md`
- `docs/testing/testing-strategy.md`
- `README.md`
- `docs/workflows/development-workflow.md`

Keep the manual offline-relaunch acceptance boundary unchanged unless the implementation proves an actual documentation mismatch.

In `docs/architecture/architecture.md`, document the durable activation rule if the implementation now relies on provider lifetime to stop periodic polling when the signed-in song-reading subtree unmounts.

- [ ] **Step 4: Run the local verification script contract tests if they changed**

Run:

```bash
bash scripts/tests/verify-test.sh
```

and any other focused script tests touched by the workflow change.

Expected: PASS.

### Task 7: Run End-To-End Verification For The Slice

**Files:**
- Verify: `apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`
- Verify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Verify: `apps/lyron_app/test/presentation/song_library/song_library_providers_test.dart`
- Verify: `apps/lyron_app/test/integration/authenticated_song_reader_flow_test.dart`
- Verify: `apps/lyron_app/test/integration/local_first_authenticated_song_reader_flow_test.dart`
- Verify: `./scripts/verify.sh`

- [ ] **Step 1: Run the focused app tests together**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/application/song_library/song_catalog_controller_test.dart \
  test/presentation/song_library/song_list_screen_test.dart \
  test/presentation/song_library/song_library_providers_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run the full repository verification gate for this slice**

Run:

```bash
./scripts/verify.sh
```

Expected: PASS, including backend-backed authenticated song-reading and local-first cache coverage.

- [ ] **Step 3: Re-read the spec and plan together before handoff**

Re-read:

- `docs/specs/2026-03-29-periodic-and-manual-song-catalog-refresh.md`
- `docs/plans/2026-03-29-periodic-and-manual-song-catalog-refresh.md`

Confirm the implementation still matches these boundaries:

- no realtime/websocket dependency
- no background refresh while suspended or terminated
- one shared refresh path for manual and periodic triggers
- 5-minute foreground-session periodic cadence
- no overlapping refresh runs
- no stale in-flight refresh restoring cache after sign-out
- automated verification tightened for the backend-backed refresh path
