# Session-Scoped Plan Reader Navigation Implementation Plan

> Status: Implemented — later partially superseded by the slug-routing slice, which changed the public scoped reader URL to `/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug` while keeping the same internal reader-context contract.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add plan-detail-to-reader navigation and session-scoped previous and next reader navigation without introducing a second reader screen or a broader global navigation model.

**Architecture:** Keep the existing `SongReaderScreen` as the only reader screen, but add a dedicated plan-origin reader route that carries stable planning identifiers in the URL. This plan originally used id-based route segments; the shipped slug-routing slice later replaced the public route shape with `planSlug`, `sessionSlug`, and `songSlug` while keeping the same internal reader-context model. Resolve session-scoped navigation through a narrow route-backed context layer with two explicit paths: warm same-stack entry reuses already-loaded plan detail data, while cold direct entry or reload re-fetches planning context online before enabling scoped navigation. Enter the scoped reader with `push`, keep previous and next on a single reader stack entry through route replacement or equivalent in-place route updates, and preserve reader-local controls through a session-scoped runtime state holder that outlives individual song route instances.

**Tech Stack:** Flutter, Riverpod, go_router, Dart, Flutter test, integration test, manual browser validation, Markdown

---

### Task 1: Lock The Route Contract Before Changing UI Behavior

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_routes.dart`
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Modify: `apps/lyron_app/lib/src/presentation/planning/planning_routes.dart`
- Modify: `apps/lyron_app/test/router/app_router_test.dart`
- Reference: `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`

- [ ] **Step 1: Add a failing route-constant test for the canonical plan-origin reader route**

Add assertions in `apps/lyron_app/test/router/app_router_test.dart` for a new dedicated reader route that encodes:

```dart
expect(
  AppRoutes.planSessionSongReader.path,
  '/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug',
);
```

- [ ] **Step 2: Run the focused router test to verify it fails**

Run: `flutter test test/router/app_router_test.dart --plain-name "list, sign-in, planning, and reader route constants remain stable"`

Expected: FAIL because the new route constant does not exist yet.

- [ ] **Step 3: Add the canonical route constant and planning helper**

Update:

- `apps/lyron_app/lib/src/router/app_routes.dart`
- `apps/lyron_app/lib/src/presentation/planning/planning_routes.dart`

Add a helper similar to:

```dart
static String planSessionSongReaderLocation({
  required String planId,
  required String sessionId,
  required String sessionItemId,
  required String songId,
}) => AppRoutes.planSessionSongReader.path
    .replaceFirst(':planId', planId)
    .replaceFirst(':sessionId', sessionId)
    .replaceFirst(':sessionItemId', sessionItemId)
    .replaceFirst(':songId', songId);
```

- [ ] **Step 4: Register the new route in the app router without changing auth policy**

Update `apps/lyron_app/lib/src/router/app_router.dart` so the new route:

- is gated by the existing signed-in redirect rules
- builds the existing `SongReaderScreen`
- passes both `songId` and the stable planning identifiers needed for session-scoped mode

Do not remove or repurpose the existing `/songs/:songId` route.

- [ ] **Step 5: Re-run the focused router test to verify it passes**

Run: `flutter test test/router/app_router_test.dart --plain-name "list, sign-in, planning, and reader route constants remain stable"`

Expected: PASS

### Task 2: Resolve Route-Backed Scoped Reader Context Before UI Work

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context_resolver.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context_provider.dart`
- Create: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart`
- Create: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_provider_test.dart`
- Reference: `apps/lyron_app/lib/src/presentation/planning/planning_providers.dart`
- Reference: `apps/lyron_app/lib/src/domain/planning/plan_detail.dart`

- [ ] **Step 1: Write failing pure resolver tests for same-session neighbors and boundary rules**

Create `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart` covering:

- selected session item resolves from `planId + sessionId + sessionItemId + songId`
- previous and next are computed from session item order
- first item disables previous
- last item disables next
- single-item session disables both

Use `PlanDetail`, `SessionSummary`, and `SessionItemSummary` fixtures.

- [ ] **Step 2: Add a failing duplicate-song test**

In the same test file, add a session fixture where the same `songId` appears twice in one session:

```dart
const SessionItemSummary(
  id: 'item-10',
  position: 10,
  song: SongSummary(id: 'song-1', title: 'A forrásnál'),
),
const SessionItemSummary(
  id: 'item-20',
  position: 20,
  song: SongSummary(id: 'song-1', title: 'A forrásnál'),
),
```

Assert that navigation is anchored to `sessionItemId`, not only `songId`.

- [ ] **Step 3: Add a failing invalid-context test**

Add a test that a mismatched `sessionItemId` or `songId` returns an explicit invalid context result instead of silently degrading to song-only mode.

- [ ] **Step 4: Write failing provider tests for warm-path and cold-path scoped resolution**

Create `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_context_provider_test.dart` to cover:

- warm same-stack entry can resolve scoped context from already-loaded `PlanDetail` data without requiring a second planning fetch
- cold direct entry resolves scoped context by re-fetching planning data through the existing planning provider path
- unavailable planning data produces an explicit scoped-context failure result

- [ ] **Step 5: Implement the minimal context model, resolver, and provider**

Create a narrow model such as:

```dart
class SessionScopedReaderContext {
  const SessionScopedReaderContext({
    required this.planId,
    required this.sessionId,
    required this.sessionItemId,
    required this.songId,
    required this.previousItem,
    required this.nextItem,
  });
}
```

Create a resolver that:

- locates the session from existing `PlanDetail`
- locates the selected item by `sessionItemId`
- verifies the `songId` matches the selected item
- computes previous and next from the latest readable ordering

Add a provider layer that:

- accepts the stable route ids
- supports a warm-path override from already-loaded plan detail data
- supports a cold-path read through `planningPlanDetailProvider(planId)`
- exposes an explicit failure result for invalid or unavailable scoped context

- [ ] **Step 6: Run the focused scoped-context tests to verify they pass**

Run:

```bash
flutter test \
  test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart \
  test/presentation/song_reader/session_scoped_reader_context_provider_test.dart
```

Expected: PASS

### Task 3: Add Session-Scoped Reader Runtime State That Survives Song Switches

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_runtime_state.dart`
- Create: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart`
- Create: `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart`
- Reference: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_state.dart`

- [ ] **Step 1: Write failing runtime-state tests for preserved reader controls**

Create `apps/lyron_app/test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart` to prove that a session-scoped runtime controller:

- starts with the current default reader settings
- updates view mode, transpose, and font scale
- preserves those settings when the selected song changes within the same `planId + sessionId` reader session
- resets when a different scoped reader session starts

- [ ] **Step 2: Run the focused runtime-state test to verify it fails**

Run: `flutter test test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart`

Expected: FAIL because the scoped runtime state holder does not exist yet.

- [ ] **Step 3: Implement the minimal runtime-state holder**

Create a narrow runtime state layer keyed by scoped reader session identity, for example `planId + sessionId`, so previous and next route changes do not lose:

- view mode
- transpose offset
- shared font scale

Do not move this state into global app state.

- [ ] **Step 4: Run the focused runtime-state test to verify it passes**

Run: `flutter test test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart`

Expected: PASS

### Task 4: Make Plan Detail Song Items Open The Scoped Reader

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Reference: `apps/lyron_app/lib/src/presentation/planning/planning_routes.dart`

- [ ] **Step 1: Write a failing widget test for tappable session items**

Update `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart` so it fails until session items render as interactive controls.

Assert that tapping a session item:

- uses `context.push(...)` semantics from plan detail into the reader
- lands on the canonical plan-origin reader URL
- does not replace the plan detail route underneath

- [ ] **Step 2: Implement the minimal interactive plan-detail item UI**

Update `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart` so each song-backed item:

- renders as an explicit interactive control
- uses the new `PlanningRoutes.planSessionSongReaderLocation(...)` helper
- enters the reader with `context.push(...)`
- carries enough stable ids to enter the scoped reader route

Do not redesign the screen beyond the minimum clear tap target.

- [ ] **Step 3: Add any missing user-facing copy**

Update `apps/lyron_app/lib/src/shared/app_strings.dart` only if the new interactive UI needs explicit text.

- [ ] **Step 4: Run the focused plan-detail widget tests to verify they pass**

Run: `flutter test test/presentation/planning/plan_detail_screen_test.dart`

Expected: PASS

### Task 5: Extend The Reader Screen For Optional Session-Scoped Mode

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_state.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_controller_test.dart`
- Reference: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_context.dart`
- Reference: `apps/lyron_app/lib/src/presentation/song_reader/session_scoped_reader_runtime_controller.dart`

- [ ] **Step 1: Write failing reader widget tests for scoped controls visibility**

Update `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart` to cover:

- scoped reader entry shows previous and next controls
- standard reader entry hides them
- first item disables previous
- last item disables next
- single-item session disables both

- [ ] **Step 2: Add a failing navigation-stack test for repeated next actions**

In the same test file, navigate next multiple times inside the scoped reader, then trigger the in-app back button and assert the user returns to the originating `/plans/:planId` screen rather than walking back through prior songs.

- [ ] **Step 3: Add a failing reader-state preservation test using actual previous and next navigation**

Change view mode, transpose, and font scale on a scoped reader, navigate to next or previous, and assert those settings remain intact through real scoped navigation.

- [ ] **Step 4: Implement the optional scoped-reader UI path**

Update `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` so it can accept optional planning identifiers and:

- resolve scoped context through the dedicated scoped-context layer from Task 2
- read and write scoped runtime state through the session-scoped runtime controller from Task 3
- show previous and next affordances only in scoped mode
- keep existing song-only mode unchanged
- move previous and next by session item identity using route replacement or an equivalent in-place route update so the reader remains a single stack entry

- [ ] **Step 5: Re-run the focused reader tests**

Run:

```bash
flutter test \
  test/presentation/song_reader/song_reader_screen_test.dart \
  test/presentation/song_reader/song_reader_controller_test.dart \
  test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart
```

Expected: PASS

### Task 6: Implement Explicit Error Handling For Invalid Or Unavailable Scoped Context

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [ ] **Step 1: Write a failing widget test for invalid scoped context**

Add a test that enters the scoped reader route with mismatched planning identifiers and asserts:

- the reader stays on the requested scoped route
- song content is not rendered
- an explicit error message is shown
- previous and next do not activate

- [ ] **Step 2: Add a failing widget test for “song resolves but planning context does not”**

Cover the reload-like case where song loading succeeds but planning-session context cannot be reconstructed from current readable planning data.

- [ ] **Step 3: Add a failing widget test for scoped song-load failure**

Add a scoped-route test where song loading fails and assert:

- the route remains on the requested scoped URL
- the explicit error surface is shown
- previous and next are suppressed
- the reader does not degrade into standard song-only behavior

- [ ] **Step 4: Implement the explicit scoped-context error surface**

Update `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` and `apps/lyron_app/lib/src/shared/app_strings.dart` so scoped-context failures produce a dedicated error surface rather than degrading to song-only reader behavior.

- [ ] **Step 5: Run the focused reader error tests**

Run: `flutter test test/presentation/song_reader/song_reader_screen_test.dart --plain-name "scoped"`

Expected: PASS

### Task 7: Finish Router Behavior For Direct Entry, Auth Redirect, And Back Fallback

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Reference: `apps/lyron_app/test/router/app_router_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`

- [ ] **Step 1: Write failing router tests for direct scoped entry, auth redirect, and auth restore**

Update `apps/lyron_app/test/router/app_router_test.dart` to cover:

- signed-out users cannot open the scoped reader route directly
- signed-in users can land on the scoped reader route from its canonical URL
- auth-initializing direct entry to the scoped reader URL survives restore and stays on the canonical scoped route rather than bouncing to the wrong destination

- [ ] **Step 2: Add a failing back-fallback test for no-stack scoped entry**

In a widget or router test, start directly on the scoped reader route, trigger back, and assert navigation goes to `/plans/:planId` rather than `/`.

- [ ] **Step 3: Implement the final router and back-handling rules**

Update the route matching and `SongReaderScreen` back logic so:

- standard reader keeps its current fallback to home
- scoped reader falls back to canonical plan detail when no prior stack exists
- same-stack pop remains preferred when available

- [ ] **Step 4: Run the focused router and back tests**

Run:

```bash
flutter test \
  test/router/app_router_test.dart \
  test/presentation/song_reader/song_reader_screen_test.dart
```

Expected: PASS

### Task 8: Add Flow-Level Coverage For Planning-To-Reader Navigation

**Files:**
- Create: `apps/lyron_app/test/integration/plan_session_reader_flow_test.dart`
- Reference: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`
- Reference: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Reference: `apps/lyron_app/test/router/app_router_test.dart`

- [ ] **Step 1: Write a failing flow test for plan detail to scoped reader navigation**

Create `apps/lyron_app/test/integration/plan_session_reader_flow_test.dart` with app-level routing and provider overrides that prove:

- plan list -> plan detail -> scoped reader works while signed in
- scoped reader previous and next stay within the current session

- [ ] **Step 2: Add a failing flow test for same-stack return visibility**

In the same file, scroll plan detail, open an item, return through the same in-app stack, and assert the previously opened item remains visible.

- [ ] **Step 3: Add a failing flow test for duplicate-song navigation identity**

Use a duplicated-song session fixture and assert that previous and next move by session item identity, not just song title or song id.

- [ ] **Step 4: Add a failing flow test for unchanged non-planning reader behavior**

Assert that:

- direct song-list-to-reader entry still uses the standard `/songs/:songId` route
- back from standard reader entry still returns to the song list rather than canonical plan detail

- [ ] **Step 5: Implement only the missing wiring needed to make the flow tests pass**

Do not add speculative abstractions here. Use this task only to finish any routing or provider glue still missing after the lower-level tasks.

- [ ] **Step 6: Run the focused flow test**

Run: `flutter test test/integration/plan_session_reader_flow_test.dart`

Expected: PASS

### Task 9: Verify Browser Reload Behavior With The Best Available Repository-Owned Mechanism

**Files:**
- Modify: `apps/lyron_app/test/router/app_router_test.dart`
- Optional Modify: `docs/workflows/development-workflow.md` only if a new durable validation rule is learned
- Reference: `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`

- [ ] **Step 1: Add a deterministic direct-entry test that approximates reload restoration**

In `apps/lyron_app/test/router/app_router_test.dart`, start the app directly at the scoped reader URL with signed-in auth and assert that:

- the selected song loads
- scoped previous and next boundaries are present
- the route remains at the canonical scoped URL

This is the repository-owned automated proxy for browser reload semantics.

- [ ] **Step 2: Add a deterministic auth-restore direct-entry test**

Start the app at the scoped reader URL while auth is still initializing, complete `restoreSession()`, then resolve planning and song data and assert the app remains on the canonical scoped URL.

- [ ] **Step 3: Add a deterministic direct-entry failure test**

Start directly at the scoped reader URL with planning context intentionally unavailable and assert the explicit scoped-context error state.

- [ ] **Step 4: Add a deterministic reorder-after-reload test**

Simulate a cold scoped-route resolution where the fetched `PlanDetail` ordering differs from the warm in-memory ordering and assert previous and next are recomputed from the freshly fetched readable session order rather than stale in-memory neighbors.

- [ ] **Step 5: Run the focused router test suite**

Run: `flutter test test/router/app_router_test.dart`

Expected: PASS

- [ ] **Step 6: Perform a manual Chrome reload walkthrough before handoff**

Run: `flutter run -d chrome`

Expected manual checks:

- opening a song from plan detail lands on the canonical scoped URL
- browser refresh keeps the user on the same scoped URL
- when auth restores and planning data is available, the same session-scoped reader is reconstructed
- back from a reload-entered scoped reader goes to the canonical plan detail route

Record any durable discrepancy in repository docs before merging if the automated proxy missed it.

### Task 10: Run The Focused Verification Gate And Prepare The Slice For Execution Handoff

**Files:**
- Modify: `docs/plans/2026-04-01-session-scoped-plan-reader-navigation.md` only to check off completed steps during execution
- Reference: `docs/specs/2026-04-01-session-scoped-plan-reader-navigation.md`

- [ ] **Step 1: Run the focused automated verification set**

Run:

```bash
flutter test \
  test/router/app_router_test.dart \
  test/presentation/planning/plan_detail_screen_test.dart \
  test/presentation/song_reader/song_reader_screen_test.dart \
  test/presentation/song_reader/song_reader_controller_test.dart \
  test/presentation/song_reader/session_scoped_reader_context_resolver_test.dart \
  test/presentation/song_reader/session_scoped_reader_context_provider_test.dart \
  test/presentation/song_reader/session_scoped_reader_runtime_controller_test.dart \
  test/integration/plan_session_reader_flow_test.dart
```

Expected: PASS

- [ ] **Step 2: Re-run explicit regression checks for home routing and unchanged planning rendering**

Run:

```bash
flutter test test/router/app_router_test.dart --plain-name "signed-in users are redirected away from the sign-in route"
flutter test test/presentation/planning/plan_list_screen_test.dart
flutter test test/presentation/planning/plan_detail_screen_test.dart
```

Expected: PASS, proving signed-in home still lands on the song list and planning list/detail rendering still behaves as expected outside the new reader flow.

- [ ] **Step 3: Run repository formatting or analysis only for changed scope if needed**

Run: `dart format apps/lyron_app/lib apps/lyron_app/test docs/specs docs/plans`

Expected: PASS with only intended file changes.

- [ ] **Step 4: Re-run any test subset made stale by the final edits**

Run the smallest affected subset again after any late fixes.

Expected: PASS

- [ ] **Step 5: Commit in small, reviewable slices during execution**

Recommended commit sequence:

```bash
git commit -m "test(router): lock scoped plan reader route contract"
git commit -m "feat(planning): open session items in scoped song reader"
git commit -m "feat(song-reader): add session-scoped previous next navigation"
git commit -m "test(reader): cover reload fallback and duplicate-song navigation"
```

Do not batch the whole slice into one opaque commit.
