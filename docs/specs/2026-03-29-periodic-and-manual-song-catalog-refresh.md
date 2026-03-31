# Periodic And Manual Song Catalog Refresh Spec

> Status: Implemented

## Goal

Deliver a small but visible product improvement in the current authenticated local-first song-reading slice by allowing signed-in users to refresh the song catalog manually from the song list and by refreshing the catalog automatically at a fixed interval while the app is active.

## Scope

- Add a visible sync affordance to the signed-in song list UI.
- Allow the user to trigger a manual catalog refresh from that affordance.
- Refresh the authenticated song catalog automatically at a fixed interval while the app is active and the user remains signed in.
- Keep the current local-first full-snapshot model.
- Keep the current backend-owned authorization boundary.
- Keep the current read-only slice.
- Surface automatic refresh outcomes through the existing persistent catalog status area.
- Tighten verification so this slice does not widen the gap between documented quality gates and executable repository checks.

## Non-Goals

- No Supabase Realtime, websocket subscription, or push-notification dependency in this slice.
- No background platform service for refresh while the app is suspended or terminated.
- No partial row-level diff sync or incremental merge logic.
- No multi-organization switching UI.
- No change to the current `SongSummary` and raw `SongSource` repository contract.
- No write sync, mutation queue, or conflict handling changes.
- No redesign of the song list or reader information architecture.
- No broad cleanup-only refactor with no direct product outcome.

## Product Slice Summary

The current authenticated local-first song-reading slice proves that a signed-in user can read from a cached full catalog snapshot and that the app can recover from offline conditions without breaking the local-first boundary. What is still missing is a simple, explicit refresh model for day-to-day usage.

This slice adds two user-facing improvements:

- a manual refresh action in the song list
- periodic refresh attempts while the app is active

The slice intentionally keeps refresh behavior simple. The app will continue to fetch the full visible catalog from the backend and will continue to replace the active local snapshot only after a complete successful refresh. The feature is not about near-real-time collaboration. It is about keeping the authenticated cached catalog reasonably fresh without introducing a new synchronization architecture.

## Core Product Rules

- The active local catalog remains the latest successfully fetched full visible catalog snapshot.
- Manual refresh and periodic refresh must use the same catalog-refresh rules and the same repository boundary.
- A failed automatic refresh must not clear a previously valid cached catalog.
- A failed automatic refresh must be visible in the existing signed-in catalog status surface.
- Offline or unverifiable session conditions must continue to prefer cached authenticated reading when the current slice already allows it.
- Explicit sign-out must continue to remove cached authenticated catalog access.
- If a manual or periodic refresh is still in flight when explicit sign-out occurs, that in-flight refresh must not restore cached authenticated catalog access after sign-out completes.
- The current slice still assumes one active organization context at a time.

## User Flows

### Signed-In Song List With Manual Refresh

1. The user opens the signed-in song list.
2. The app shows the current catalog and the existing status surface.
3. The song list app bar includes a visible sync affordance.
4. The user taps the sync affordance.
5. The app starts a catalog refresh using the same full-snapshot rules as the existing automatic refresh path.
6. While refresh is in progress, the UI shows persistent refresh status.
7. If refresh succeeds, the active catalog is replaced with the latest full visible snapshot.
8. If refresh fails, the current active catalog remains visible and the failure is surfaced in the persistent status area.

### Signed-In Periodic Refresh While Active

1. The user is signed in and the app is active.
2. After a fixed interval, the app attempts a catalog refresh automatically.
3. If a refresh is already running, the new automatic attempt does not start a concurrent second refresh.
4. If the app has a valid active snapshot, that snapshot remains visible while the automatic refresh runs.
5. If the automatic refresh succeeds, the active snapshot is replaced atomically.
6. If the automatic refresh fails because connectivity is missing or unstable, the active cached catalog remains visible and the status surface communicates offline and refresh-failed state as appropriate.

For this slice, "active" means:

- the user is signed in
- the app process is in the foreground or resumed state
- the signed-in song-reading flow is currently mounted

This slice does not require periodic refresh while the app is backgrounded, suspended, or terminated.

### First Signed-In Use With No Cached Catalog

1. The user signs in successfully.
2. No cached catalog exists yet.
3. The app attempts the initial refresh.
4. If that refresh fails, the user sees the existing unavailable state rather than an empty catalog.
5. Manual refresh remains available so the user can retry explicitly.

### Offline Recovery

1. The user previously had a successful authenticated catalog snapshot.
2. Connectivity becomes unstable or unavailable.
3. A periodic refresh attempt fails.
4. The cached catalog remains readable.
5. The status surface makes the failed refresh and offline-cached state visible.
6. The user may manually retry later from the song list sync affordance.

## UI Requirements

### Song List Sync Affordance

- The signed-in song list app bar must include a visible sync affordance.
- The sync affordance must be available without opening a secondary menu.
- The affordance must clearly mean "refresh catalog" rather than "upload" or "status only".
- The affordance may be disabled while a refresh is already running.
- The affordance must not remove the existing sign-out action.

### Persistent Status Visibility

- The existing persistent catalog status surface remains the primary location for refresh state communication.
- Automatic refresh outcomes must be visible there, not only manual refresh outcomes.
- The user must be able to distinguish at minimum:
  - online and up to date
  - refresh in progress
  - offline using cached catalog
  - refresh failed while cached catalog remains visible
- This slice may reuse existing status strings where they remain accurate, but any new copy must stay concise and product-facing.

## Refresh Semantics

### Refresh Entry Points

This slice introduces two refresh triggers:

- manual refresh initiated by the user from the song list
- periodic refresh initiated automatically while the app is active

Both triggers must call one shared refresh path rather than maintaining separate refresh implementations.

### Fixed-Interval Refresh

- The repository must define one fixed refresh interval for this slice.
- The fixed interval for this slice is 5 minutes.
- The interval should be long enough to avoid noisy or wasteful polling and short enough to keep the song list reasonably fresh during active use.
- The implementation must avoid overlapping refresh executions.
- The implementation may skip scheduling when the user is signed out or when the relevant signed-in flow is not active.

### Atomic Snapshot Replacement

- The active catalog must still be updated only by a completed full visible catalog refresh.
- Partial refresh data must never become the active snapshot.
- If a refresh fails after the previous snapshot already existed, the previous snapshot remains active.

## Architecture Requirements

### No Push-Based Sync In This Slice

- This slice must not depend on Supabase Realtime, Postgres change subscriptions, websocket presence, or mobile push notifications.
- The refresh model remains client-initiated polling.
- If the repository later wants realtime invalidation, that should be a separate slice layered on top of the same full-refresh boundary rather than a hidden requirement of this one.

### Backend Boundary

- Supabase Auth and Postgres RLS remain the authorization and visibility authority.
- The app still fetches minimal song summaries and raw ChordPro source through the current repository boundary.
- The backend contract does not change to "what changed since X" for this slice.
- Flutter must not introduce client-side authorization rules while implementing manual or periodic refresh.

### Active Organization Context

- The repository must treat active organization resolution as an explicit implementation concern in this slice.
- The spec does not require multi-organization switching UI.
- The implementation must not further hide active-organization selection inside unrelated refresh code.
- If the current implementation continues to assume one active organization, the relevant decision path must remain explicit and testable.

## Workflow And Verification Requirements

This slice includes targeted hardening because the refresh feature depends directly on backend-backed and local-first behavior.

- The implementation must leave backend-backed refresh behavior better verified than before, not less.
- Repository verification for this slice must continue to prove:
  - authenticated backend song reads
  - local-first persistent cache reopen behavior
  - explicit sign-out cache removal
- The automated verification change in this slice is specifically about the backend-backed refresh path:
  - `./scripts/verify.sh` should continue to exercise the backend-backed authenticated song-reading integration coverage
  - `.github/workflows/ci.yml` must no longer stop at the app-only gate for this slice
  - CI must execute either `./scripts/verify.sh` itself or a dedicated equivalent that includes the backend-backed authenticated song-reading verification required by this slice
- This slice does not change the repository's current boundary between:
  - automated persistent-cache reopen proof
  - native manual offline-relaunch acceptance
- This slice does not require expanding the manual-validation scripts unless a refresh-specific acceptance gap is discovered during implementation.
- This does not require solving every repository workflow concern in one slice, but this feature must not ship while leaving its own critical refresh path outside executable verification.

## Testing Requirements

TDD is mandatory.

### Unit Tests

Cover:

- manual refresh trigger wiring
- periodic refresh scheduling behavior
- prevention of overlapping refresh runs
- automatic refresh behavior when signed out
- sign-out during an in-flight refresh preventing stale refresh completion from restoring cached authenticated access
- automatic refresh behavior when offline cached state exists
- shared refresh path behavior for manual and periodic triggers

### Widget Tests

Cover:

- visible sync affordance on the signed-in song list
- manual refresh invocation from the sync affordance
- disabled or in-progress sync affordance behavior while refreshing
- persistent status visibility for automatic refresh in-progress and failure states

### Integration Tests

Cover:

- manual refresh updating the active catalog after backend changes
- periodic refresh updating the active catalog after backend changes
- periodic refresh failure preserving the previous cached snapshot
- local-first reading continuing after a failed automatic refresh

### Backend And Workflow Verification

Cover:

- authenticated backend song-reading integration
- local-first authenticated cache reopen integration
- repository verification entrypoints and CI wiring touched by this slice

## Success Criteria

- Signed-in users can manually refresh the song catalog from a visible sync affordance in the song list.
- The app attempts automatic catalog refresh at a fixed interval while active and signed in.
- Manual and automatic refresh share one refresh path and one snapshot-replacement policy.
- Failed automatic refresh attempts do not destroy a valid cached catalog.
- Automatic refresh outcomes are visible in the persistent song-list status surface.
- The slice does not introduce realtime/websocket dependencies.
- The repository finishes the slice with stronger executable verification around backend-backed refresh behavior than before.
