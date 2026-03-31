# Cross-Platform Catalog Connectivity Classification Fix

> Status: Implemented

## Goal

Keep the authenticated local-first song catalog in a consistent offline-cached mode across all supported Flutter targets when the Supabase stack becomes unreachable or partially unavailable after a successful cache fill.

## Problem

Two related failures were observed during offline cache validation:

- a manual refresh after backend shutdown could log a refresh failure while the UI still reported the catalog as online
- a cold relaunch after one successful sync and backend shutdown could fail to reopen the cached catalog even though a valid local snapshot existed

The current implementation relies on a narrow set of exception types to decide whether a failure is connectivity-related. In practice, equivalent backend-unavailable conditions may surface as different Supabase, PostgREST, auth, proxy, or transport errors on different platforms.

## Scope

- Normalize connectivity-failure classification for authenticated catalog flows across supported platforms.
- Apply that shared classification to:
  - active organization resolution
  - session verification
  - manual and automatic catalog refresh failure handling
- Preserve the existing local-first full-snapshot model.
- Preserve explicit sign-out cache deletion semantics.

## Non-Goals

- No new sync transport or realtime channel.
- No change to cache storage layout.
- No change to authorization ownership.
- No change to the native-first acceptance boundary for offline relaunch.

## Required Behavior

- Connectivity-like backend failures must degrade an existing cached catalog to `offlineCached` instead of leaving the UI in `online`.
- Retryable auth fetch failures must be treated as unverifiable connectivity, not as confirmed session expiry.
- Cached organization resolution must still fall back to the latest cached organization when backend-unavailable conditions are reported through retryable proxy or PostgREST failures instead of only raw socket failures.
- The same cached snapshot must remain readable after cold relaunch when:
  - a valid authenticated session is still locally restorable
  - a valid cached catalog exists
  - the backend is currently unreachable or unavailable

## Verification

- Controller tests must prove backend-unavailable refresh failures degrade to `offlineCached`.
- Controller tests must prove cached organization fallback still works when the backend-unavailable condition is surfaced as a retryable PostgREST failure.
- Unit tests must prove the shared connectivity classifier recognizes retryable auth and PostgREST connectivity failures without misclassifying authorization failures.
