# Local-First Cached Authenticated Song Reading Spec

## Goal

Deliver the first local-first authenticated song-reading slice for Lyrica by making the latest successfully fetched full visible song catalog available for offline reading while preserving the current authenticated backend boundary, app-local ChordPro parsing, and read-only scope.

## Scope

- Cache the full visible authenticated song catalog locally after a successful backend read.
- Cache both minimal song summaries and raw ChordPro source for that visible catalog.
- Support offline song reading from the latest successfully fetched full catalog snapshot.
- Guarantee authenticated offline relaunch from the active cached snapshot on native Flutter targets.
- Treat browser-based offline authenticated relaunch as best-effort, not as a guaranteed acceptance criterion for this slice.
- Preserve the current authenticated routing and backend-owned authorization boundary.
- Preserve app-local ChordPro parsing, diagnostics, and reader projection.
- Add explicit UI state visibility for online, offline, refreshing, and refresh-failed states.
- Keep the slice read-only.

## Non-Goals

- No song create, update, delete, or editing UI.
- No write sync or mutation queue.
- No conflict resolution for writes.
- No plans, sessions, or setlist workflows.
- No multi-organization switching UI.
- No backend parsed-song payloads.
- No change to the current song domain contract centered on `SongSummary` and raw `SongSource`.
- No attempt to solve fullscreen or presentation-mode continuity behavior when catalog visibility changes during an active reading session.

## Product Slice Summary

The authenticated backend song-reading slice already proves that a signed-in user can authenticate against local Supabase, load an organization-scoped song list, open a song, and read it through the existing in-app parser and reader flow. What remains unproven is the repository's documented local-first operating model.

This slice proves the next narrow but critical claim: once the authenticated backend-backed catalog has been fetched successfully, the app can continue to provide usable song browsing and reading from local state during poor or absent connectivity without widening the architecture or introducing write behavior.

This is not a general offline-sync slice. It is the first executable local-first read slice for authenticated song reading.

## Core Product Rules

- The active local catalog is the latest successfully fetched full visible catalog snapshot.
- The app must not expose a partially refreshed catalog as the active catalog.
- The user should experience the latest full known catalog, not an unpredictable subset of individually cached songs.
- The app must clearly communicate connectivity and refresh state in the UI.
- Offline cached reading remains an authenticated experience, not a public local archive.
- Explicit sign-out removes access to the authenticated cached catalog.
- Authenticated cached catalog ownership is scoped to the authenticated user and active organization context that produced the current snapshot.
- This slice assumes one active organization context at a time.

## User Flows

### Signed-In Online Launch

1. The user opens the app with a valid authenticated context.
2. If a previously stored local catalog snapshot exists, the app may show it immediately.
3. The app attempts to refresh the full visible song catalog from the backend.
4. Until the refresh completes successfully, the previous local snapshot remains the active catalog.
5. If the backend refresh completes successfully, the app replaces the active local catalog with the new full visible snapshot.

### Signed-In Relaunch With Poor Or No Connectivity

1. The user opens the app without usable backend connectivity.
2. If a previously stored full catalog snapshot exists for the authenticated user context, the app shows that cached catalog.
3. The user can open songs from that cached catalog and read them through the existing reader flow.
4. The UI clearly indicates that the app is operating from cached offline state.

For this slice, the hard guarantee for authenticated offline relaunch applies to native Flutter targets. Browser-based relaunch may still depend on web session-persistence behavior outside the local song-cache itself.

### First Authenticated Use Without Connectivity

1. The user launches the app without usable backend connectivity.
2. No previous full local catalog snapshot exists.
3. The app does not show an empty song list as though no songs exist.
4. The app shows an explicit unavailable state indicating that no cached catalog is available yet.

### Connectivity Restored

1. The app regains usable backend connectivity.
2. The app attempts to fetch a new full visible catalog snapshot.
3. The currently active local snapshot remains active unless and until the new full snapshot completes successfully.
4. After a successful refresh, the new snapshot becomes the only active catalog.

### Explicit Sign-Out

1. The user explicitly signs out.
2. The app removes the authenticated cached catalog for that signed-in user.
3. The signed-out user cannot continue browsing or reading authenticated cached songs through this slice.

## Data Access Boundary

This slice must preserve the current architecture.

- The reader remains centered on minimal `SongSummary` data and raw `SongSource`.
- ChordPro parsing remains in Flutter.
- Reader projection and rendering remain in Flutter.
- Backend authorization remains owned by Supabase Auth identity and Postgres RLS.
- The local cache is a read model for this slice, not a new domain redesign.
- The slice must not reintroduce bundled asset fallback as the normal authenticated song-reading path.

## Catalog Snapshot Policy

### Full Visible Catalog Cache

The cache entry point for this slice is the full visible authenticated song catalog, not individual opportunistic per-song caching.

When the app successfully fetches the authenticated song catalog from the backend, it should persist:

- the full visible song summary list
- the raw ChordPro source for each song in that visible catalog
- enough metadata to determine whether the current catalog is cached, active, refreshing, or stale

The persisted catalog snapshot for this slice must be owned by the authenticated user and the active organization context that produced it. This slice must not treat authenticated song cache as device-global shared content.

For this slice, the app assumes one active organization context at a time. The cached catalog represents the latest full visible catalog for that active organization only, and the implementation retains only one current authenticated catalog snapshot per user. This slice does not introduce multi-organization switching UI or multiple simultaneously retained local song catalogs.

### Atomic Full Snapshot

The active local catalog must be updated only by a completed full visible catalog snapshot.

- A partial backend refresh must not become the active local catalog.
- If a refresh fails partway through, the previously active full snapshot remains active.
- The user should always read from one coherent catalog snapshot.

### Hard Replace

When a new full visible catalog snapshot completes successfully, it replaces the previous active local catalog.

- Songs no longer present in the new visible catalog are removed from the active local catalog.
- This slice does not preserve a separate archived catalog of no-longer-visible songs.
- Future slices may refine continuity rules for an already open reader session, but that is out of scope here.

## Auth And Offline Read Semantics

This remains an authenticated slice even when the reader is operating from local cache.

- Offline cached reading is allowed only for the last authenticated user context when connectivity is unavailable.
- A missing backend refresh caused by lack of connectivity does not automatically force the app into a signed-out experience if the user has a valid prior authenticated local context and an available cached catalog.
- The cached authenticated catalog belongs to the current authenticated user and represents the latest successful snapshot for the user's active organization context.
- Explicit sign-out deletes that cached authenticated catalog.
- If the backend can reliably determine that the session is expired or invalid, the app must require reauthentication instead of continuing authenticated cached reading.
- If session validity cannot be determined reliably because connectivity is missing or unstable, the app may continue in cached offline reading mode for the last authenticated user context and its latest active-organization snapshot.
- Connectivity failures must not be treated as equivalent to confirmed session expiry.
- The app must distinguish between:
  - signed out
  - signed in with fresh backend state
  - signed in using cached offline state
  - refreshing backend state

This slice does not define new role logic in Flutter. Flutter reacts to authenticated state and cached availability; backend policy remains authoritative whenever online refresh occurs.

## Connectivity And Refresh Visibility

The UI must make operating state explicit.

At minimum, the authenticated song list shell must provide persistent visible status for:

- online and up to date
- refreshing catalog
- offline using cached catalog
- refresh failed while showing cached catalog

These states should not be hidden as incidental debug text or transient toasts. The user should be able to understand whether the app is showing fresh backend state or cached local state while continuing to use the reader flow.

If connectivity drops while a refresh is already in flight, the app should continue showing the active cached catalog and treat the result as a combined state:

- connectivity state: offline using cached catalog
- refresh outcome: the most recent refresh attempt failed

This slice does not require those two aspects to collapse into one exclusive application state. The UI should be able to communicate both that the app is currently operating from cached offline state and that the latest refresh attempt did not succeed.

This requirement applies to the core list and reader experience for this slice. Later product slices may refine how those indicators behave in specialized full-screen or presentation-oriented views.

## Failure Semantics

The slice must distinguish at least these cases:

- `noCachedCatalog`
  - no usable backend connectivity and no previously stored full catalog snapshot
  - result: show an explicit unavailable state, not an empty list

- `cachedCatalogAvailableOffline`
  - no usable backend connectivity, but a previously fetched full catalog snapshot exists
  - result: show the cached catalog with persistent offline status

- `sessionStateUnverifiableDueToConnectivity`
  - session validity cannot be confirmed because connectivity is missing or unstable, but a cached catalog exists for the last authenticated user context and its latest active-organization snapshot
  - result: continue cached authenticated reading with persistent offline status rather than treating the user as explicitly signed out

- `catalogRefreshInProgress`
  - a cached catalog is available and a backend refresh is running
  - result: keep the active catalog visible and show persistent refresh status

- `catalogRefreshFailed`
  - a cached catalog remains available, but the attempted backend refresh failed
  - result: keep the cached catalog visible and show persistent failure/stale status
  - if connectivity dropped during an in-flight refresh, the app may show this together with offline cached status rather than forcing an exclusive single-state interpretation

- `explicitlySignedOut`
  - the user has explicitly signed out
  - result: authenticated cached catalog is not available

- `confirmedSessionExpired`
  - the backend successfully responds and confirms that the session is expired or invalid
  - result: require reauthentication and do not continue authenticated cached reading

- `songMissingFromActiveSnapshot`
  - the requested song is not present in the active local snapshot
  - result: show an unavailable state for that song

This slice may continue reusing the current reader-level unavailable and retryable error surfaces where appropriate, but it must not collapse all local-first read states into a generic loading or empty-state experience.

## Testing Requirements

TDD is mandatory.

### Unit Tests

Cover:

- active snapshot selection behavior
- state mapping for fresh, cached offline, refreshing, and refresh-failed modes
- sign-out behavior removing access to authenticated cached data
- hard-replace snapshot behavior when a newer full catalog omits previously visible songs

### Widget Tests

Cover:

- persistent status visibility for online, offline, refreshing, and refresh-failed states
- unavailable state when no cached catalog exists
- cached song list rendering from the active local snapshot
- cached song reader rendering from the active local snapshot
- sign-out removing access to previously visible cached catalog UI state

### Integration Tests

Cover:

- authenticated backend fetch creating a full local catalog snapshot
- offline relaunch using the cached catalog on native-capable targets or equivalent non-browser persistence test seams
- song reading from cached local source without backend connectivity
- explicit sign-out disabling authenticated cached access
- cached catalog becoming unavailable immediately after explicit sign-out
- successful backend refresh replacing the active catalog with a newer full snapshot

### Backend-Backed Verification

Cover:

- the current authenticated backend reader verification path remains green
- backend refresh still respects organization-scoped visibility through RLS
- the local-first read slice does not reintroduce client-owned authorization decisions

## Success Criteria

- A user can continue reading the latest successfully fetched full visible song catalog snapshot without usable connectivity.
- Native Flutter targets can relaunch into that cached authenticated catalog without usable connectivity.
- The app never exposes a partially refreshed catalog as the active catalog.
- The UI clearly communicates whether the app is online, offline, refreshing, or showing cached stale state.
- The slice remains read-only and preserves the existing backend authorization boundary.
- The repository moves materially closer to the documented offline-first product direction without widening into write sync or planning workflows.
