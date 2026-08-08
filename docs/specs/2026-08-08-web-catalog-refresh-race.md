# Web Song Catalog Never Loads (Refresh Trigger Race)

> Status: Implemented
>
> Decisions recorded durably in
> `docs/architecture/decisions/ADR-031-session-scoped-catalog-refresh.md`.

## Goal

The song catalog loads on Flutter web. Today it never does: the library screen
shows "No cached song catalog is available yet." forever and `GET /rest/v1/songs`
is never issued, while every other authenticated read (`current_organization_ids`,
`plans`, `sessions`) succeeds in the same page load.

## Problem

Reproduced 2026-08-08 on a `flutter build web` bundle against local Supabase,
with the demo user's session present in `localStorage`. Console instrumentation
(added temporarily, then reverted) produced this ordering:

```
authState=AppAuthStatus.initializing session=null
refreshCatalog enter
session=null                      <- bail: sessionStatus = expired
authState=AppAuthStatus.signedIn session=4e589aa7-...
signedIn branch
refreshCatalog DEDUP              <- the real refresh is swallowed
```

Three facts compose into the failure:

1. **`songCatalogControllerProvider` refreshes unconditionally at construction.**
   The provider body ends with `unawaited(controller.refreshCatalog())` *after*
   `handleAuthStateChanged(authController.state)` has already run. When the
   provider is built while `AppAuthController` is still `initializing`, that
   trailing call runs a refresh with no session. The two planning providers do
   not have this trailing call — they rely on `handleAuthStateChanged` alone,
   which is why planning loads and songs do not.

2. **`SongCatalogController.refreshCatalog` coalesces on presence, not identity.**
   `if (_refreshFuture != null) return _refreshFuture` treats "some refresh is in
   flight" as "the refresh you asked for will happen". That is false when the
   in-flight refresh started under a *different* session identity. The refresh
   that started with `session == null` bails immediately at its first gate, but
   its future is still registered when the auth stream's `signedIn` event lands
   in the same turn, so the signed-in trigger returns the doomed future instead
   of dispatching real work.

3. **Nothing retriggers.** The only recovery path is the 5-minute
   `Timer.periodic` in `_updateRefreshScheduler`, and it is gated on
   `AppForegroundState.isForeground`. `WidgetsBindingAppForegroundState` samples
   `WidgetsBinding.instance.lifecycleState` **once, in its constructor**. If that
   sample is a non-`resumed` value — observed on web when the tab is not the
   focused one at load — the timer is never created, and no later
   `didChangeAppLifecycleState` arrives to correct it. Observed in the repro: no
   refresh after six minutes.

Native wins the race by accident: auth restore completes before the catalog
screen mounts, so the construction-time refresh already has a session. The
defect is platform-independent logic; web merely loses the race every time.

## Decisions

**D1 — Refresh coalescing is scoped to session identity.** `refreshCatalog()`
records the session identity (`AppAuthSession.userId`, nullable) the in-flight
refresh started under. A later call under the *same* identity keeps today's
behaviour and returns the in-flight future — the existing sign-out overlap
guarantees depend on that. A later call under a *different* identity must not be
swallowed: the controller schedules exactly one follow-up refresh to run when the
in-flight one settles, and the caller's future completes only after that
follow-up. At most one follow-up is queued per in-flight window, so a burst of
triggers cannot fan out into a refresh storm.

**D2 — The catalog provider does not refresh outside a known auth state.**
`songCatalogControllerProvider` drops its trailing unconditional
`unawaited(controller.refreshCatalog())`. `handleAuthStateChanged` — invoked once
at construction and again from the auth listener — is the single trigger, exactly
as in `planning_providers.dart`. A refresh under `initializing` has no
information to act on and can only produce a misleading `expired` session status.

**D3 — The recovery timer does not depend on a construction-time lifecycle
sample.** `WidgetsBindingAppForegroundState` treats *any* lifecycle value read
before the first `didChangeAppLifecycleState` callback as foreground, not just
`null`. Once the framework reports a real transition, the existing logic governs.
The periodic refresh is a recovery net; it must not be disarmed by a value
sampled before the binding has settled.

## Non-Goals

- No Riverpod 3 migration (`docs/deferred/2026-07-30-riverpod-3-migration.md`).
- No `chromedriver` web e2e lane (`docs/deferred/2026-06-29-web-offline-e2e.md`).
  The regressions here are reproducible as native widget/unit tests; adding
  browser test infrastructure is a separate slice.
- No change to what the catalog fetches, to RLS, or to the offline snapshot
  format. This slice only fixes *when* a refresh is dispatched.

## Verification

- Unit tests on `SongCatalogController` for D1: a refresh started with a null
  session followed by a refresh under a real session must reach the remote
  repository. Existing sign-out overlap tests stay green unchanged.
- A provider-level test for D2: building `songCatalogControllerProvider` while
  auth is `initializing` issues no refresh; the subsequent `signedIn` transition
  issues exactly one.
- A unit test for D3: a controller constructed while the reported lifecycle state
  is not `resumed` still schedules the periodic refresh once a session exists.
- Manual: `flutter build web` served locally with a real session loads the four
  seeded songs, and `GET /rest/v1/songs` appears in the network log.
