# Cross-Platform Catalog Connectivity Classification Fix Plan

> Status: Implemented

> **Goal:** Ensure local-first authenticated catalog behavior stays consistent across supported platforms when Supabase connectivity failures surface through different retryable exception shapes.

## Architecture

Keep the existing `SongCatalogController` state model and Drift-backed cache intact, but move connectivity detection onto one shared classifier that can be reused by organization resolution, session verification, and refresh failure handling.

## Steps

- [x] Reproduce the failure paths in the shared controller logic and identify where connectivity is classified too narrowly.
- [x] Add a failing controller test proving refresh failures surfaced as backend-unavailable PostgREST errors must degrade to `offlineCached`.
- [x] Add a failing controller test proving cached organization fallback still works when organization resolution fails with a retryable PostgREST backend-unavailable error.
- [x] Introduce a shared connectivity classifier for retryable transport, auth, and PostgREST failure shapes used by the supported platforms.
- [x] Reuse that classifier in `SongCatalogController` and in the session-verification provider path.
- [x] Add focused unit tests for the shared classifier so retryable auth and backend-unavailable failures stay covered without reclassifying authorization errors.
- [x] Run focused Flutter verification for the affected controller, provider, and app startup paths.

## Files

- Modify: `apps/lyrica_app/lib/src/application/song_library/song_catalog_controller.dart`
- Modify: `apps/lyrica_app/lib/src/application/providers.dart`
- Create: `apps/lyrica_app/lib/src/shared/connectivity_failure.dart`
- Modify: `apps/lyrica_app/test/application/song_library/song_catalog_controller_test.dart`
- Create: `apps/lyrica_app/test/shared/connectivity_failure_test.dart`
- Create: `docs/specs/2026-03-31-cross-platform-catalog-connectivity-classification-fix.md`
- Create: `docs/plans/2026-03-31-cross-platform-catalog-connectivity-classification-fix.md`
