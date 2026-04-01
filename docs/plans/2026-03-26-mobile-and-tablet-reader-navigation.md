# Mobile And Tablet Reader Navigation Implementation Plan

> Status: Implemented

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make song reader navigation behave naturally on Android and iOS by preserving a real list-to-reader back stack, adding a visible reader back affordance, and providing a safe fallback to the song list when the reader is opened directly with no poppable history.

**Architecture:** Keep the current route structure and signed-in root screen unchanged. Fix the behavior with the smallest possible product change: move list-to-reader navigation to push-style routing, give the reader a single back action that pops when possible and falls back to a history-replacing return to the song list when it is not, and prove the behavior with widget, router, and integration tests. Do not introduce master-detail, split view, or new tablet-only layout state.

**Tech Stack:** Flutter, Riverpod, go_router, Flutter test, Markdown

---

### Task 1: Lock In Reader Back UX And System Back With Failing Widget Tests

**Files:**
- Modify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`

- [ ] **Step 1: Add a failing reader widget test for visible back affordance**

Extend `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart` with a test that renders `SongReaderScreen` inside a navigation-aware app shell and asserts the reader exposes a visible back control in the app bar.

The test should verify the reader still shows the existing persistent catalog status surface together with the new back affordance.

- [ ] **Step 2: Add a failing widget test for direct-entry system-back fallback**

Extend `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart` with a direct-entry flow that renders the reader as the top route with no poppable history and simulates a system back event.

The test should assert that the reader handles the back event itself and returns to the song list route instead of allowing the app to exit. Use the Flutter test API that exercises route popping or `PopScope` behavior directly rather than only tapping the app bar.

- [ ] **Step 3: Add a failing widget test for list-to-reader push behavior**

Extend `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` with a flow that:

1. renders the song list inside `MaterialApp.router`
2. taps a song title
3. verifies the reader route opens
4. triggers back navigation from the pushed reader route
5. verifies the list screen becomes visible again

This test should fail against the current `context.go(...)` behavior because there is no preserved back stack.

- [ ] **Step 4: Add any missing string expectations for the back affordance**

If the implementation needs user-facing copy such as a dedicated back tooltip or label, add the exact string constant to `apps/lyron_app/lib/src/shared/app_strings.dart` and use it in tests rather than hard-coded text.

- [ ] **Step 5: Run the focused widget tests to verify they fail**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/song_reader_screen_test.dart \
  test/presentation/song_library/song_list_screen_test.dart
```

Expected: FAIL because the reader does not currently guarantee a visible back affordance and list-to-reader navigation does not preserve a poppable back stack.

### Task 2: Implement Push Navigation And Reader Back Fallback

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Reference: `apps/lyron_app/lib/src/router/app_routes.dart`

- [ ] **Step 1: Change list-to-reader navigation to push-style routing**

Update `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart` so selecting a song uses push-style navigation instead of route replacement.

The implementation should continue opening the same `/songs/:songId` route and should not change the song list's role as the signed-in root screen.

- [ ] **Step 2: Add one explicit reader back control that is always visible**

Update `apps/lyron_app/lib/src/presentation/song_reader/song_reader_screen.dart` so the reader app bar always renders an explicit leading back affordance instead of relying on automatic implied leading behavior.

Wire that control to a single back handler with this intent:

```dart
void _handleBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }

  // Use replace-style navigation or the closest go_router equivalent so
  // a directly opened reader returns to the list without creating a back loop.
  context.replace(AppRoutes.home.path);
}
```

If `context.replace(...)` is not available in the repository's go_router version, use the smallest equivalent implementation that returns to `/` without pushing a new list route above the direct reader entry.

- [ ] **Step 3: Intercept Android-style system back with the same fallback logic**

Wrap the reader route body in `PopScope`, `WillPopScope`, or the current Flutter equivalent so system back uses the same pop-first / replace-second behavior as the visible reader back control.

The implementation must cover the direct-entry case where there is no poppable history and must not depend solely on tapping the app bar button.

- [ ] **Step 4: Preserve reader status visibility while adding the back control**

Keep the existing `_CatalogStatusSurface` behavior in the reader intact. The back affordance must not remove or hide the persistent online, offline, refreshing, or refresh-failed status surface already required by the local-first reader slice.

- [ ] **Step 5: Re-run the focused widget tests to verify they pass**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_reader/song_reader_screen_test.dart \
  test/presentation/song_library/song_list_screen_test.dart
```

Expected: PASS.

### Task 3: Prove Direct Reader Entry And Fallback Navigation At Router Level

**Files:**
- Modify: `apps/lyron_app/test/router/app_router_test.dart`
- Reference: `apps/lyron_app/lib/src/router/app_routes.dart`
- Reference: `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart`

- [ ] **Step 1: Add a failing router-level test for direct reader entry fallback**

Extend `apps/lyron_app/test/router/app_router_test.dart` with a signed-in test that boots the app at `/songs/blocked` or another concrete song ID while authenticated and with a visible catalog context.

Use provider overrides so the router test is deterministic:

- override `songLibraryReaderProvider` or `songLibraryRepositoryProvider` with a known reader result
- override `songLibraryListProvider` with a known song list
- keep the existing auth controller and catalog-state overrides explicit in the test

The test should:

1. confirm the reader route is shown first
2. invoke the reader back action
3. verify the app lands on the song list route
4. trigger another back event and verify the direct-entry reader is not re-pushed above the list

- [ ] **Step 2: Keep the router table unchanged unless a real seam is required**

Do not modify `apps/lyron_app/lib/src/router/app_router.dart` unless the failing test proves that the current router API needs a narrow seam for location assertion or fallback verification.

Do not introduce nested shells or speculative route names just for this slice.

- [ ] **Step 3: Run the focused router test to verify it passes**

Run:

```bash
cd apps/lyron_app && flutter test test/router/app_router_test.dart
```

Expected: PASS, including the new direct-reader fallback coverage and the existing auth redirect coverage.

### Task 4: Update Integration Coverage For End-To-End Back Navigation

**Files:**
- Modify: `apps/lyron_app/test/integration/song_reader_flow_test.dart`

- [ ] **Step 1: Add a failing integration expectation for returning from reader to list**

Extend `apps/lyron_app/test/integration/song_reader_flow_test.dart` so the signed-in happy path now proves:

1. the app boots into the song list
2. tapping a song opens the reader
3. invoking the visible back affordance returns to the song list
4. the existing session-expiry redirect still works after the reader has been opened

- [ ] **Step 2: Add a failing direct-entry integration test**

Extend `apps/lyron_app/test/integration/song_reader_flow_test.dart` with a second integration scenario that:

1. boots the app directly into `/songs/:songId`
2. uses explicit provider overrides for song data and catalog context
3. confirms the reader loads successfully from that direct route
4. triggers the visible back affordance or simulated system back
5. verifies the app lands on the song list instead of exiting or recreating a back loop

- [ ] **Step 3: Run the focused integration test to verify behavior**

Run:

```bash
cd apps/lyron_app && flutter test test/integration/song_reader_flow_test.dart
```

Expected: PASS after the navigation changes are in place.

- [ ] **Step 4: Re-read the integration test for slice boundaries**

Confirm the integration coverage still stays within the intended slice:

- no master-detail assumptions
- no tablet-only layout branching
- no auth model changes
- no cache-policy changes

### Task 5: Verify The Complete Navigation Slice

**Files:**
- Verify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`
- Verify: `apps/lyron_app/test/presentation/song_reader/song_reader_screen_test.dart`
- Verify: `apps/lyron_app/test/router/app_router_test.dart`
- Verify: `apps/lyron_app/test/integration/song_reader_flow_test.dart`
- Verify: `./scripts/verify.sh --skip-migrations`

- [ ] **Step 1: Run the focused Flutter navigation tests together**

Run:

```bash
cd apps/lyron_app && flutter test \
  test/presentation/song_library/song_list_screen_test.dart \
  test/presentation/song_reader/song_reader_screen_test.dart \
  test/router/app_router_test.dart \
  test/integration/song_reader_flow_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run the broader app-safe verification gate**

Run:

```bash
./scripts/verify.sh --skip-migrations
```

Expected: PASS for the app and documentation quality gate without requiring backend workflow changes for this navigation-only slice.

- [ ] **Step 3: Re-read the spec and plan together before handoff**

Re-read:

- `docs/specs/2026-03-26-mobile-and-tablet-reader-navigation.md`
- `docs/plans/2026-03-26-mobile-and-tablet-reader-navigation.md`

Confirm the implementation still matches these boundaries:

- song list remains the signed-in root
- reader remains full-screen on tablet
- reader back affordance is visible on iOS and Android
- deep-link fallback returns to the list without creating a back loop
- later side-sheet or split-view work remains possible without redoing the basic navigation model
