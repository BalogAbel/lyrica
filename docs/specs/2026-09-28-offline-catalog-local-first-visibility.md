# Offline Catalog Local-First Visibility

**Slice:** fix/offline-catalog-local-first-visibility
**Investigation date:** 2026-09-28 (field-confirmed and scratch-test-confirmed)
**Supersedes in part:** D3 of
`docs/specs/2026-08-19-local-data-durability-contract.md` (see status note
added there in this change) and the "network/auth outcome decides `context`"
behaviour ADR-020/ADR-035 left in place.

## Problem

Data is never deleted; it is hidden. `songLibraryListProvider`
(`apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart:185-195`)
returns `[]` whenever
`SongCatalogController.state.context == null` — regardless of what is sitting
in the local database. `context` is set almost exclusively as the *output* of
a network call
(`SongCatalogController._refreshCatalogBody`,
`apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart:185-575`)
or by a single one-shot gap-filler
(`handleOfflineAuthenticated`, same file:601-655) that only runs once, at the
`signedIn → sessionExpired` auth transition
(`apps/lyron_app/lib/src/application/song_catalog_providers.dart:124-127`).

### F-A — field symptom: expired token + bad/no network on a long-idle device

Confirmed by the user: songs "come back on their own, just late."

Sequence: app was idle long enough that the access token is expired. The
device now has poor or no connectivity. Before the organization lookup
(`client.rpc`, `_resolveOrganizationId` at
`song_catalog_controller.dart:206-211`) can even attempt to run, `gotrue`
silently attempts a token refresh. Measured against the pinned
`gotrue-2.27.2` (`~/.pub-cache/hosted/pub.dev/gotrue-2.27.2/lib/src/gotrue_client.dart:1385-1428`,
`fetch.dart:149-210`): every `http.Client` call gotrue or postgrest makes has
**no client-side timeout**. `TracingHttpClient`
(`apps/lyron_app/lib/src/infrastructure/observability/tracing_http_client.dart`),
the wrapper installed in `Supabase.initialize` at
`apps/lyron_app/lib/src/bootstrap/bootstrap.dart:218-221`, passes every
request straight to the OS socket layer, so the only bound on a single
attempt is the OS/DNS give-up time — measured at 12.5 s for a DNS failure and
75 s for an unroutable network, **per call**. The org lookup and the
follow-up `getUser()` (`catalogSessionVerifierProvider`,
`apps/lyron_app/lib/src/application/song_catalog_providers.dart:38-68`) run in
sequence, so a single refresh can hang for minutes.

While this is in flight the UI shows the false empty-state string
(`AppStrings.songListEmptyStateMessage`, "No cached song catalog is available
yet.", `apps/lyron_app/lib/src/shared/app_strings.dart:95`) even though the
local database has a perfectly good snapshot, and the manual Sync button is a
no-op: `UnifiedManualSyncController._runOnce`
(`apps/lyron_app/lib/src/application/sync/unified_manual_sync_controller.dart:101-105`)
reads `activeCatalogContextProvider`, which is null, and returns
`UnifiedManualSyncRunResult.clean()` without doing anything.

### F-B — any `inactive → resumed` while `sessionExpired` wipes `context` (reproduced on a scratch harness, not yet seen in the field)

`AppAuthState` in `sessionExpired` carries `lastKnownSession`, not `session`
(`apps/lyron_app/lib/src/application/auth/app_auth_controller.dart:330-361`);
`SongCatalogController._authSessionReader` reads `.session`, so it reads
`null`. `foregroundSyncListenerProvider`
(`apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart:203-213`)
fires `unifiedManualSyncControllerProvider.syncNow()` on every
`inactive → resumed` transition (screen lock, notification shade, app
switch), which calls `refreshSongCatalog` →
`SongCatalogController.refreshCatalog()` →
`_refreshCatalogBody()`. Its very first branch
(`song_catalog_controller.dart:191-200`) is:

```dart
final session = _authSessionReader();
if (session == null) {
  _verifiedEmptyMembershipSeen = false;
  _setStateIfCurrent(generation, const CatalogSnapshotState.initial()...);
  return;
}
```

This is a **pure local branch — no network call at all** — and it
unconditionally resets `context` to null. `handleOfflineAuthenticated()` does
not re-run (it is only invoked once, at the auth transition), so the catalog
stays hidden until the user explicitly signs back in. The equivalent
planning path
(`PlanningSyncController._refreshPlanning`,
`apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart:155-166`)
already guards `session == null` with a plain early return that leaves
`_state` untouched — it does not reset to `initial()`. Catalog is the
inconsistent, destructive one; planning is already the correct shape.

### Latent bugs (not yet field-observed; found by code reading and confirmed against the pinned library source)

- **F-C.** A non-connectivity, non-auth error from the org lookup, while
  `context` is already null, resets to `initial()`
  (`song_catalog_controller.dart:233-246`, the `else` branch of the org-lookup
  `catch`). Harmless *by itself* (context was already null) but becomes a real
  loss once local-first (below) can have already populated `context` moments
  earlier in the same call — this branch has to stop assuming "context null"
  is still true.
- **F-D.** `persistNewIdentity`
  (`apps/lyron_app/lib/src/application/auth_providers.dart:231-303`), in its
  `ActiveOrganizationUnknownConnectivityFailure` /
  `ActiveOrganizationUnknownNonConnectivityFailure` / `null` branch
  (lines 289-300), unconditionally writes
  `LastKnownIdentity(..., organizationId: null)`. This closure
  (`flushSameUser: persistNewIdentity` at lines 530 and 545) is also the path
  taken on an ordinary **same-user** `signedIn` re-edge (token refresh,
  foreground resume, re-sign-in) whose membership resolution happens to come
  back unknown (offline, or a non-connectivity error). It overwrites a
  previously-known, good `organizationId` with `null`, which later starves
  the local-first path (below) of the one thing it needs.
- **F-E.** `SongCatalogController._isAuthorizationFailure`
  (`song_catalog_controller.dart:681-694`) does `if (error is AuthException)
  return true;`. `AuthRetryableFetchException` — gotrue's own connectivity/
  transient-failure type (`gotrue-2.27.2/lib/src/types/auth_exception.dart:55`,
  thrown from `fetch.dart:43,50,190` for network errors, 5xx, and any
  exception `http.Client` throws) — **extends** `AuthException`, so it is
  misclassified as an authorization failure. In the `listSongs` catch block
  (`song_catalog_controller.dart:534-573`) the authorization check runs
  *before* the connectivity check, so a transient network failure during
  `listSongs()` takes the `clearContext: true` branch and calls
  `_resetSessionLifecycle()` (which stops the refresh timer), instead of the
  `offlineCached` branch that would have kept `context` and the cached data
  visible.
- **F-F.** `_sessionVerifier()` returning `CatalogSessionStatus.expired`
  (`song_catalog_controller.dart:397-410`), or an authorization failure from
  `listSongs()` (540-553), both call `clearContext: true` while the app is
  still `AppAuthStatus.signedIn` per `AppAuthController`. Nothing re-sets
  `context` afterward except a fully successful future refresh — so a single
  401/expired-verifier response during an otherwise-normal session hides the
  catalog until the next successful network round-trip, exactly the same
  symptom as F-A, without even the connectivity excuse.

## Invariant (binding for both steps)

> The catalog `context` shown to the user comes from local data
> (`LastKnownIdentity` + the local snapshot), and only these four things may
> change it:
>
> 1. a D1 purge (ADR-035),
> 2. an explicit sign-out,
> 3. a fresh, online, authenticated resolution that names a **different**
>    organization,
> 4. a different-user sign-in.
>
> Network or auth outcomes (connection state, session state, refresh
> failures) set **status fields only** (`connectionStatus`, `sessionStatus`,
> `refreshStatus`) — never `context`, never `hasCachedCatalog`.

Ownership rule: `identity.userId == session.userId` when a live session
exists; `identity.userId` alone when `sessionExpired` (no live session to
compare against). A different user's local snapshot must never surface.
Establishing `context` locally is explicitly **not** a membership
resolution: it must never set or clear `membershipRevokedAt`
(D5.2,
`docs/architecture/decisions/ADR-035-local-data-purge-contract.md`). D1/D5
purge logic itself is unchanged by this spec.

## Decisions

### Step 1 — local-first context establishment (closes F-A)

1. **Local-first before network.** `_refreshCatalogBody` gains a shared
   local-first path, run before the org-lookup RPC and also on the
   currently-immediate-return null-session branch, not only once at the auth
   transition. It is the generalization of today's
   `handleOfflineAuthenticated`: when `context` is null, resolve a candidate
   `organizationId` as `LastKnownIdentity.organizationId` (if the identity's
   `userId` matches — the live session's `userId` when signed in, or the
   identity's own `userId` when `sessionExpired`), falling back to
   `store.readLatestCachedOrganizationId(userId:)`. If a non-empty local
   snapshot exists for the resulting `(userId, organizationId)`, `context`
   and `hasCachedCatalog: true` are set immediately, with
   `connectionStatus: offlineCached`, before any network call runs. The
   network refresh then proceeds exactly as today and only ever *improves*
   status (`connectionStatus: online`, fresher data) — it no longer decides
   whether `context` exists in the first place.
2. **HTTP timeout.** `TracingHttpClient.send` (bootstrap-wired,
   `tracing_http_client.dart`) wraps `_inner.send(request)` in
   `.timeout(Duration(seconds: 15))`. Verified against the pinned
   `gotrue-2.27.2` source: `GotrueFetch._handleRequest`'s `catch (e)`
   (`fetch.dart:188-191`) converts **any** exception the injected
   `http.Client` throws — including a `TimeoutException` — into
   `AuthRetryableFetchException`, which `isConnectivityFailure`
   (`apps/lyron_app/lib/src/shared/connectivity_failure.dart:6-12`) already
   classifies as a connectivity failure. `TimeoutException` is also already
   in `isConnectivityFailure`'s own direct type check, so a postgrest-path
   timeout (org lookup RPC, `listSongs`) classifies correctly with no new
   plumbing. 15 s is chosen to sit below the measured 75 s unroutable-network
   give-up and above ordinary mobile-network round-trip variance; it is a
   per-request bound, not a total-operation bound (org lookup + `getUser()`
   can still take up to ~30 s combined worst case, down from minutes).
3. **UI gating.** The `songListEmptyStateMessage` string only renders when
   the local-first path has genuinely found nothing (`context == null` *and*
   no cached organization id at all) — not merely while resolution is in
   flight. `songListLoadingMessage` covers the in-flight window. Concretely:
   the empty-state widget keys off `hasCachedCatalog`/`context`, not off
   `refreshStatus`, so a `context` established by local-first already
   suppresses the false-empty message regardless of what the network is
   doing.
4. **Design-gate question — `OnlineTransitionDetector` on cold start.**
   `OnlineTransitionDetector.updateCatalog`
   (`apps/lyron_app/lib/src/application/sync/online_transition_detector.dart:24-32`)
   only fires `onTransitionToOnline` when `_previousCatalogOnline` was
   already non-null and `false`; the very first observed state
   (`previous == null`) never fires. Today, cold start's first observed
   state is typically `unavailable`/`initial`, which then flips to `online`
   once the first refresh succeeds — firing `syncNow()` once. With
   local-first, the first observed state becomes `offlineCached` instead
   (still not `online` per `_catalogIsOnline`), and the *same* single flip
   to `online` fires once the network catches up. **No new cold-start sync
   fire is introduced** — this is traced through the existing code, not
   speculative, and needs no further handling.

### Step 2 — invariant on every branch (closes F-B..F-F)

1. Null-session refresh in `_refreshCatalogBody` stops resetting to
   `initial()`. It runs the same local-first path as the signed-in branch
   (using `LastKnownIdentity` alone, since there is no live session to
   compare against), sets `sessionStatus: expired`, and otherwise behaves
   like `PlanningSyncController._refreshPlanning`'s existing null-session
   guard: preserve, don't destroy.
2. Every remaining `clearContext: true` / `CatalogSnapshotState.initial()`
   site inside `_refreshCatalogBody` that is not one of the four invariant
   causes becomes status-only:
   - org-lookup authorization failure (today: `initial()`,
     lines 213-221) → `sessionStatus: expired`, context preserved.
   - post-verify `sessionStatus == expired` (F-F, lines 397-410) →
     `sessionStatus: expired`, `connectionStatus` reflects cache
     availability, context/`hasCachedCatalog` preserved.
   - `listSongs` catch, authorization branch (F-F, lines 540-553) → same
     status-only shape.
   `handleExplicitSignOut` (explicit sign-out) and the confirmed-purge branch
   of the verified-empty-membership handler are the only two survivors of
   `initial()`/`clearContext` inside this controller; a different-user
   sign-in clears the prior user's data via `LocalDataLifecycle.purgeSongCatalog`
   at the `auth_providers.dart` layer, not via this controller.
3. **Classification order (F-E).** Fix centrally in
   `_isAuthorizationFailure`: exclude `AuthRetryableFetchException` before
   the `is AuthException` check (it is gotrue's connectivity/transient type,
   not an authorization failure), rather than reordering every call site.
   This also fixes the org-lookup catch, which has the same
   authorization-checked-before-connectivity ordering bug.
4. **`persistNewIdentity` (F-D).** In the unknown-resolution branch
   (`auth_providers.dart:289-300`), when this is a same-user edge (the
   closure's captured `priorIdentity` is non-null and
   `priorIdentity.userId == session.userId`), preserve
   `priorIdentity.organizationId` instead of overwriting with `null`. A
   genuinely new user (no prior identity, or a different user — reached
   through `wipePriorAndProceedFor`, which already erased the prior
   identity first) still gets `organizationId: null`, correctly.
5. **Gap-filler merge.** `handleOfflineAuthenticated` becomes a thin
   wrapper around the same private local-first helper Step 1 adds to
   `_refreshCatalogBody`, so the logic runs on every refresh attempt where
   `context` is null, not only once at the `signedIn → sessionExpired`
   transition.
6. **Manual Sync under `sessionExpired` routes to re-auth, automatic
   triggers never prompt.** With the invariant fix, `context` stays
   populated under `sessionExpired` whenever local data exists, so
   `UnifiedManualSyncController._runOnce` is no longer a no-op by accident —
   it would now attempt real network sync steps against an expired session
   and report spurious failures. `UnifiedManualSyncController` gains an
   auth-status reader; when status is `sessionExpired`, `_runOnce` skips the
   network steps entirely and reports a distinct `requiresReauth` outcome
   instead of running (or of silently failing) sync. Only the **manual**
   Sync button UI (`UnifiedSyncStatusPopup`) reads that flag and navigates
   to sign-in, reusing `ReauthBanner`'s existing route
   (`context.go(Uri(path: AppRoutes.signIn.path, queryParameters: {'from':
   from}))`, `apps/lyron_app/lib/src/presentation/auth/reauth_banner.dart:63-74`).
   The two **automatic** triggers —
   `OnlineTransitionDetector.onTransitionToOnline` and
   `foregroundSyncListenerProvider.onResume` — both call the same
   `syncNow()`, get the same `requiresReauth` result, and do nothing further
   with it: no navigation, no dialog, no data hidden. This satisfies the
   user's explicit requirement — "only kick me to sign-in when *I* press
   Sync."
7. **Planning parity — assessment task, not a resolved decision here.**
   Planning's own null-session guard
   (`_refreshPlanning`, `planning_sync_controller.dart:159-166`) already
   returns early without destroying state — it does not have F-B's
   destructive shape. Whether planning needs its own local-first
   proactive-establishment (mirroring Step 2.5's merge, rather than only the
   one-shot `handleOfflineAuthenticated` it already has) is assessed as an
   implementation-phase task (haiku-scoped). If the gap is small, it is
   folded into this slice; if large, it is written up in
   `docs/deferred/` with a trigger condition, per `AGENTS.md`.

## Non-Goals

- Changing D1/D5 purge semantics or `AppAuthController._stateForSession`'s
  `signedOut`-vs-`sessionExpired` decision (governed by ADR-020/ADR-035,
  untouched here).
- Raising the pinned `supabase_flutter`/`gotrue`/`supabase` package versions.
- Web/IndexedDB-specific offline behaviour (tracked separately,
  `docs/deferred/2026-06-29-web-offline-e2e.md`).
- Extending or rotating the Supabase refresh-token TTL itself
  (`docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`, closed as a
  data-durability concern already — this spec does not reopen it, it only
  makes the *sync-paused* consequence of an expired refresh token visible
  and recoverable instead of indistinguishable from data loss).

## Acceptance

- A provider-level "offline soak" integration test (real wiring, not a
  refresh-token-focused unit test) proves: for as long as a non-empty local
  snapshot exists for the current `(userId, organizationId)`,
  `songLibraryListProvider` never yields `[]`, across `signedIn` and
  `sessionExpired`, across fake lifecycle transitions, manual/automatic sync
  triggers, and a network that never resolves — except immediately after a
  genuine D1 purge.
- Every existing test in the full suite (`./scripts/run-tests.sh` /
  `flutter test` from `apps/lyron_app`) still passes; any test whose
  assertion directly encoded one of F-B..F-F's old destructive behaviour is
  updated to assert the new invariant instead, not deleted.
- `./scripts/verify.sh` is green.

## Review follow-ups R1–R3 (PR #79 review, 2026-09-28)

Three findings from reviewing the implemented PR. All three are fixed on
this same branch, same PR.

### R1 — the response-timeout shape was too blunt

**Problem.** `TracingHttpClient`'s 15s `.timeout(...)` (Step 1 item 2) wraps
the *entire* request, including the time after the server has already
committed a write or rotated a token but before the response body finishes
transferring. Two concrete failure shapes:

- **`/auth/v1/token` (refresh)**: gotrue rotates the refresh token on
  redemption. If the client abandons the request via timeout after the
  server already rotated but before the response arrives, the client still
  holds the OLD (now-consumed) refresh token. A retry with it lands outside
  gotrue's short reuse-interval grace window (10s, gotrue-2.27.2's
  `Constants` — reuse inside the window is tolerated as a benign retry;
  outside it, gotrue treats it as token-reuse and revokes the whole
  session), forcing a needless full re-authentication on a connection that
  was merely slow, not actually broken.
- **A write RPC**: the same abandon-after-commit shape turns a client's own
  later retry of the same logical write into a false optimistic-concurrency
  (`base_version`) conflict against itself.

**Fix — two-tier timeout, not one blunt one (later corrected to three tiers
by I1, see below):**

1. **Connect timeout: 10s**, native only. `TracingHttpClient` gains a
   platform seam (conditional import: `dart:io`'s `HttpClient` wrapped as
   an `IOClient` on native, where `HttpClient.connectionTimeout` is
   settable; a no-op passthrough on web, since `BrowserClient` exposes no
   connect-timeout knob — the browser's own TCP/TLS timeout applies
   instead, unchanged from before this fix). This is what actually bounds
   the measured 75s "network up, no route" hang from the original
   investigation, without touching in-flight response time at all.
2. **Response backstop: 60s**, applied to every request EXCEPT
   `/auth/v1/token` (path-matched on the outgoing request's URL), which
   gets a longer, separate backstop instead — see the I1 correction below.
3. ~~A `/auth/v1/token` request gets the connect timeout only, never the
   response backstop~~ — **corrected by I1 (post-PR#79 adversarial
   review, 2026-09-28)**: this original shape (no response bound at all for
   token refresh) was itself a regression, worse than the 15s blunt timeout
   it replaced. `dart:io`'s connect timeout only covers connect+TLS, not a
   stall after the request is written, so a dead socket on the token
   endpoint (NAT drop, wifi-to-cellular handoff, no keepalive) would hang
   forever. Worse, gotrue-2.27.2's `GoTrueClient._callRefreshToken`
   de-dupes concurrent refreshes for the same token into one shared
   `Completer` (`_pendingRefreshes`, `gotrue_client.dart`), which
   `SupabaseClient._getAccessToken` (`supabase-2.16.1/lib/src/supabase_client.dart`)
   awaits *before* any REST/RPC call reaches `TracingHttpClient.send` at
   all — so one hung refresh could block every subsequent call in the app,
   for every identity, indefinitely, defeating the purpose of adding
   timeouts in the first place. `/auth/v1/token` now gets a LONGER but
   still finite backstop (`_tokenRefreshTimeout`, 120s — well above the 60s
   general backstop and above any plausible upstream gateway timeout)
   instead of none, preserving the original intent (don't abandon a
   refresh moments before/after the server rotates the token on an
   ordinary slow-but-alive connection) while bounding the
   dead-socket/hung-forever case. See ADR-037's "Amendment: two-tier HTTP
   timeout" section for the fuller writeup.
4. **Verified via context7 against the exact pinned stack**
   (`http`, `supabase` 2.16.1, `gotrue` 2.27.2, `supabase_flutter` 2.17.2):
   the custom `httpClient` passed to `Supabase.initialize` flows into both
   `_gotrueHttpClient` (used directly by the constructed `GoTrueClient`)
   and `_authHttpClient` (wraps the same traced client for postgrest/rest
   calls) — confirmed by reading `supabase_client.dart`'s constructor in
   the pinned `supabase-2.16.1` source, not assumed. A connect-timeout or
   response-backstop failure still throws through the same paths already
   proven to classify as connectivity (`TimeoutException` — direct match
   in `isConnectivityFailure`; wrapped by gotrue's `GotrueFetch` into
   `AuthRetryableFetchException` for any exception the client throws,
   itself also directly matched).
5. **Residual risk, documented, not eliminated**: a write RPC that commits
   server-side *after* the 60s response backstop has already abandoned the
   request can still produce a false OCC conflict on the client's own
   retry. This is not a new failure class — an OS-level connection drop
   already produced the identical shape before this fix — and it is the
   same mechanism `docs/deferred/2026-07-31-occ-divergence-lf-t5.md`
   already tracks the mitigations for (the S12 mutation budget bounds how
   much unsynced intent can be affected; the footprint monitor surfaces it
   before it becomes a silent pile of conflicts). A narrower companion
   entry, `docs/deferred/2026-09-28-client-abandoned-committed-write-lf-t5b.md`,
   records the client-abandons-but-server-commits mechanism specifically
   (distinct from LF-T5's general offline-duration divergence) with its own
   trigger condition.

### R2 — planning cross-user gap: already closed by I3, verified and test strengthened

**Original report's claim** (from the PR review this section responds to):
`PlanningSyncController._refreshPlanning` never compares the last-known
identity's `userId` against the live session's `userId`, so during the
different-user re-auth window (user A's data still present, user B's
session live, the `wipePriorAndProceedFor` confirmation dialog still
pending) a `refreshPlanning()` call could establish A's context, fetch org
A's payload under B's token, and overwrite A's local projection before the
user's cancel could prevent it — the `PlanningSyncController` analog of the
catalog-side I3 fix, claimed to be missed because I3 supposedly only
touched `SongCatalogController`.

**Verified against the actual commit history: this claim was incorrect.**
I3 (`d3c7165`) already touched BOTH `SongCatalogController` AND
`PlanningSyncController` in the same commit — `_refreshPlanning` already
carries the guard: if `_state.userId != null && _state.userId !=
session.userId`, state is reset before any fetch or `_replaceProjection`
call can run under the wrong identity, placed before the null-session
early return resolves `userId`/`organizationId`, before local-first, and
before the fetch/replace-projection logic. The implementer assigned to
"fix" this correctly refused to write a duplicate guard once it re-checked
the commit history rather than trusting the review's framing at face value.

**What actually changed for R2**: the guard was already correct, but its
existing regression test only asserted the end state (`state.userId` no
longer `'user-A'`), not that the fetch/`_replaceProjection` calls
themselves never ran for org A — weaker than this section originally
specified. Strengthened (commit `24b4b16`) to directly count remote-fetch
and `_replaceProjection` calls by organization id, and verified by
temporarily disabling the guard: both counts independently go from 1 to 2
for org A under user B's session, confirming the strengthened assertions
actually catch the regression the guard prevents.

### R3 — sessionExpired users had no way back from the sign-in screen while still offline

**Problem.** `ReauthBanner` and the (now reauth-aware, per Task 2.6) manual
Sync button both navigate to `AppRoutes.signIn` under `sessionExpired`.
`SignInScreen` had no route back — a `sessionExpired` user who taps Sync (or
the banner) by mistake, or simply wants to keep reading cached songs while
genuinely offline, is stuck on the sign-in screen: no offline sign-in is
possible, so the only way out is force-quitting and relaunching the app.
The router (`app_router.dart`) already permits `sessionExpired` users to
navigate to ordinary in-app routes (it only forces `AppRoutes.home` from
`bootstrap`, otherwise returns `null`/no redirect) — the missing piece is
purely a button on `SignInScreen` giving that path back.

**Fix.** `SignInScreen`, when `AppAuthStatus.sessionExpired`, shows a
"Continue offline" action alongside the existing sign-in methods, which
navigates to the `from` query parameter (the route the banner/Sync button
captured on the way in) or `AppRoutes.home` if there is none. Not shown
under `signedOut` (there is nothing to "continue" to — no local identity is
established, matching the invariant's own worked examples).
