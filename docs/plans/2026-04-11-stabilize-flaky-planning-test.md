# Implementation Plan: Stabilize Flaky Planning Test [COMPLETED]

This plan addresses the `Bad state: No element` failure in the `disables add-song when no cached catalog is available` test. This failure likely stems from a race condition or non-deterministic viewport behavior in the CI environment (GitHub Actions).

## User Review Required

> [!IMPORTANT]
> This change modifies the test finding logic to be more robust against lazy-loaded list views and potential microtask timing differences in headless environments.

## Proposed Changes

### presentation/planning [PlanDetailScreen Test]

#### [MODIFY] [plan_detail_screen_test.dart](file:///Users/abelbalog/Documents/Development/private/lyrica/apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart)
- Update `buildApp` to use more stable immediate `overrideWithValue` for `catalogSnapshotStateProvider` (already done) and ensure `visibleSongs` is immediately available.
- Refine the failing test:
  1. Explicitly wait for the loading state to vanish.
  2. Use a more robust finder for the `TextButton` that handles potential off-screen lazy loading by using `skipOffstage: false`.
  3. Change the `tester.widget` call to be more resilient by asserting the presence of the finder results first.

## Verification Plan

### Automated Tests
- Run the localized test:
  `flutter test test/presentation/planning/plan_detail_screen_test.dart --plain-name "disables add-song when no cached catalog is available"`
- Run the full suite:
  `flutter test test/presentation/planning/plan_detail_screen_test.dart`
- Run with multiple repetitions (local check for flakiness):
  `for i in {1..20}; do flutter test test/presentation/planning/plan_detail_screen_test.dart --plain-name "disables add-song when no cached catalog is available" || break; done`
