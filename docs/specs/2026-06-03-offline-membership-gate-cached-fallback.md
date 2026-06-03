# Offline Membership Gate: Cached Organization Fallback

- Status: Proposed
- Date: 2026-06-03
- Scope: Mobile (`apps/lyron_app`) application layer — membership resolution feeding `MembershipGate`.

## Goal

A signed-in user who previously synced a catalog must still see their offline-cached songs after relaunching (or foregrounding) the app without network. Today the app shows "Could not verify access" and no songs.

## Current State (the bug)

Two independent "active organization" resolution paths exist; only one is offline-correct.

- **Catalog + planning controllers — offline-correct.** On connectivity failure they fall back to the cached organization id via `SongCatalogStore.readLatestCachedOrganizationId(userId:)` and serve the cached catalog (`song_catalog_controller.dart:115-124`; `activePlanningContextControllerProvider.latestOrganizationReader`, `providers.dart:485-489`).
- **`MembershipGate` — NOT offline-correct.** It renders from `activeMembershipControllerProvider.last`, set by `membershipRefreshEffectProvider.refreshMembership()` (`providers.dart:171-198`), which calls `resolveActiveOrganizationResolution` via `activeOrganizationResolutionProvider` — **no cache fallback**. Offline → `ActiveOrganizationUnknownConnectivityFailure` → gate shows `AppStrings.membershipConnectivityFailureMessage` and never builds `SongListScreen`.

Because the gate never builds the screen, the catalog controller's correct offline path is never reached. The router redirect (`app_router.dart:72-77`) compounds this: `last is! ActiveOrganizationSelected` bounces other routes to home, which is the failing gate.

## Design

Give the membership resolution the same cached-organization fallback the catalog/planning controllers already use. Centralize so both the refresh effect and the gate's Retry button benefit.

### `membershipResolutionProvider` (new, `providers.dart`)

Wrap `activeOrganizationResolutionProvider`. On `ActiveOrganizationUnknownConnectivityFailure` only, look up the latest cached organization id for the signed-in user; if present, resolve as `ActiveOrganizationSelected(cachedOrgId)`. Otherwise pass the original resolution through unchanged.

Reuses existing: `SongCatalogStore.readLatestCachedOrganizationId` (`song_catalog_store.dart:100`), `ActiveOrganizationResolution.selected`, `appAuthControllerProvider`, `songCatalogStoreProvider`.

- `membershipRefreshEffectProvider.refreshMembership()` reads `membershipResolutionProvider` instead of `activeOrganizationResolutionProvider`.
- `MembershipGate` Retry button (`membership_gate.dart:34-37`) reads `membershipResolutionProvider`.

## Behaviour Matrix

| Resolution | Cached org for user | Result |
| --- | --- | --- |
| `Selected` / `VerifiedEmpty` / non-connectivity failure | n/a | passed through unchanged |
| `UnknownConnectivityFailure` | present | `Selected(cachedOrgId)` → gate renders song list |
| `UnknownConnectivityFailure` | absent / no session | unchanged failure → existing message |

## Non-Goals

- No change to `activeOrganizationReaderProvider` (catalog/planning path); already offline-correct.
- No router change; once membership is `Selected`, redirect passes.
- A signed-in user who never synced (no cached org) and is offline still sees the connectivity message — intended; nothing to show offline.
- Backend authorization unchanged — this only relaxes a client-side gate to render already-cached, already-authorized data (AGENTS.md rule 5).

## Testing

- Unit: `membershipResolutionProvider` — connectivity failure + cached org → `Selected`; + no cached org → unchanged failure; non-failure resolution → passed through; no session → unchanged.
- Widget/integration: with cached catalog + offline org lookup, `MembershipGate` renders `SongListScreen`, not the connectivity message.
