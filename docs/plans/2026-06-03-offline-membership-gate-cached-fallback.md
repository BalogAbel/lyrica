# Implementation Plan: Offline Membership Gate Cached Fallback

- Spec: `docs/specs/2026-06-03-offline-membership-gate-cached-fallback.md`
- Date: 2026-06-03
- Branch: `fix/offline-relaunch-membership-gate`

## Tasks

### Task 1 — `membershipResolutionProvider` with cached-org fallback (TDD)

Add a provider in `apps/lyron_app/lib/src/application/providers.dart` exposing an `ActiveOrganizationResolutionReader` that wraps `activeOrganizationResolutionProvider` and, on `ActiveOrganizationUnknownConnectivityFailure` only, falls back to `songCatalogStoreProvider.readLatestCachedOrganizationId(userId:)` for the current `appAuthControllerProvider` session user, returning `ActiveOrganizationResolution.selected(cachedOrgId)` when a cached id exists.

- Test first (`apps/lyron_app/test/application/...`): the fallback's pure behaviour across the four matrix rows in the spec. Extract the fallback logic into a testable top-level function (e.g. `resolveMembershipWithCachedFallback`) taking the inner resolution + a cached-org reader + userId, so it can be unit-tested without Supabase. The provider wires real dependencies to it.
- Wire `membershipRefreshEffectProvider.refreshMembership()` to read `membershipResolutionProvider`.

### Task 2 — Gate Retry uses new provider

`apps/lyron_app/lib/src/presentation/auth/membership_gate.dart:34-37`: Retry button reads `membershipResolutionProvider`.

### Task 3 — Widget/integration coverage

Extend `test/app/lyron_app_test.dart` (or `test/router/app_router_test.dart`): cached catalog present + offline org lookup → `MembershipGate` renders `SongListScreen` rather than `AppStrings.membershipConnectivityFailureMessage`.

## Verification

- `cd apps/lyron_app && flutter test`
- `dart analyze` clean for touched files.
- Manual: online sign-in (catalog syncs) → airplane mode → relaunch/foreground → song list shows cached songs, no "Could not verify access".

## Documentation

- Spec + this plan committed with the code.
- If the offline-relaunch behaviour is described in `docs/architecture` or testing docs, note the gate fallback there. (`2026-03-26-native-offline-relaunch-verification-hardening.md` is the closest prior art — cross-reference, do not duplicate.)
