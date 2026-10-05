# Offline-First Startup Gate

> Status: Draft (2026-10-05), product decisions confirmed, awaiting plan

**Branch:** `fix/offline-first-startup-gate`
**Roadmap:** slice **S0** in `docs/plans/2026-10-01-delivery-roadmap.md`, a
field-reported bug inserted ahead of S5a. It pulls S6 option (a) forward (see
"Roadmap impact").
**Builds on:** ADR-016, ADR-020, ADR-035 (D5), ADR-037
**Resolves:** option (a) of
`docs/deferred/2026-09-30-capability-gating-offline-cold-start.md`
(option (b) stays in S6)
**New deferred entries:**
`docs/deferred/2026-10-05-membership-revoked-notice.md`,
`docs/deferred/2026-10-05-offline-token-refresh-churn.md`
**Plan:** `docs/plans/2026-10-05-offline-first-startup-gate.md` (not yet
written)

## Problem

Field report (2026-10-05, after PR #79): after a long idle period the app
"cannot start offline" and the user waits 10–15 s before the song list
appears.

The investigation combined a code read of the pinned stack
(`supabase_flutter` 2.18.0, `supabase` 2.16.2, `gotrue` 2.27.2, `retry`
3.1.2) with two scratch probes run outside the repository against the pinned
`gotrue`. The probes used a real `GoTrueClient` with `autoRefreshToken: true`
(as in production), a persisted session whose access-token JWT `exp` was in
the past, and an HTTP client that fails each request after a configurable
latency.

### G-A — the membership gate is network-first (field symptom, measured)

1. The home route is `MembershipGate(child: SongListScreen())`
   (`apps/lyron_app/lib/src/router/app_router.dart:125`). The gate builds
   the song list only for `ActiveOrganizationSelected`
   (`apps/lyron_app/lib/src/presentation/auth/membership_gate.dart:18-54`).
2. `ActiveMembershipController` starts as
   `ActiveOrganizationUnknownConnectivityFailure`
   (`apps/lyron_app/lib/src/application/auth/active_membership_controller.dart:5-6`).
   The first frame of the home route is therefore the failure screen, "Could
   not verify access. Check your network.", with a Retry button.
3. Only `membershipRefreshEffectProvider`
   (`apps/lyron_app/lib/src/application/auth_providers.dart:767`) moves it
   on, using the result of the `current_organization_ids` RPC. The cached
   organization fallback (ADR-016,
   `apps/lyron_app/lib/src/application/active_organization_resolver.dart:44-56`)
   runs only **after** that RPC has failed.
4. With an expired access token the RPC cannot fail fast.
   `SupabaseClient._getAccessToken`
   (`supabase-2.16.2/lib/src/supabase_client.dart:277-294`) awaits
   `auth.getSession()` before every PostgREST/RPC request. For an expired
   session, `getSession()` joins the refresh that `Supabase.initialize`
   already started through `recoverSession`
   (`supabase_flutter-2.18.0/lib/src/supabase.dart:164-169`).
5. `GoTrueClient._refreshAccessToken`
   (`gotrue-2.27.2/lib/src/gotrue_client.dart:1389-1428`) retries for as
   long as elapsed time plus `200 * 2^(attempt-1)` ms stays under 10 s. The
   `retry` package actually sleeps `200 * 2^attempt` ms, twice what that
   predicate assumes, so the loop overshoots its own budget.

Measured `getSession()` settle time with an expired session (scratch probe):

| Network shape | Settles after | HTTP attempts |
|---|---|---|
| Airplane mode (DNS fails instantly) | 12.43 s | 6 |
| Wi-Fi without internet (DNS fails after 5 s) | 10.41 s | 2 |
| Unroutable (10 s connect timeout) | 10.00 s | 1 |

Every offline shape lands in the 10–12.5 s band, plus app launch time. That
matches the report.

**Why only after a long idle period.** `jwt_expiry` is 3600 s
(`supabase/config.toml:35`). Within an hour of the last refresh,
`getSession()` returns immediately, the RPC fails fast on DNS, and the cached
fallback opens the gate at once.

**Why PR #79 did not fix it.** PR #79 made the catalog and planning
*contexts* local-first, but the gate in front of them stayed network-first.
Its HTTP timeouts bound a single attempt, not gotrue's retry loop.

**Worst case (derived, not measured on a device).** `/auth/v1/token` has a
120 s response backstop
(`apps/lyron_app/lib/src/infrastructure/observability/tracing_http_client.dart:56`).
On a network where the connection opens but no response arrives, the first
attempt alone exceeds the 10 s budget. The gate then waits up to ~120 s.

### G-B — `sessionExpired` cold start never opens the gate (code read)

`membershipRefreshEffectProvider` resolves only on a transition **to**
`signedIn` (`auth_providers.dart:779`). The resolver's `readUserId` reads
`state.session?.userId` (`auth_providers.dart:731`), which is `null` in
`sessionExpired`, so the cached fallback cannot run either. A cold start
straight into `sessionExpired` leaves the gate on its initial failure state
indefinitely. The re-auth banner lives inside `SongListScreen`, behind the
gate, so the user also never sees the way out.

This contradicts `docs/specs/2026-06-28-non-destructive-session-and-offline-relaunch.md`
(line 62) and `docs/architecture/architecture.md` (the ADR-020 paragraph).
Both claim that the gate resolves through the cached organization id in
`sessionExpired`.

### G-C — a normal online sign-in flashes the failure screen (code read)

Because the initial state is a failure (G-A step 2), every first resolution
renders "Could not verify access. Check your network." until the RPC
returns, even online.

### G-D — one `verifiedEmpty` hides data that D5 deliberately keeps (code read)

On the first fresh `verifiedEmpty`, the gate switches to
`InviteRequiredScreen`. ADR-035 D5 needs two fresh empty resolutions at
least 60 s apart, plus no pending work or an explicit confirmation, before
anything is purged. It states that during that window "the data stays fully
readable and editable", and that the purge confirmation dialog is D5's only
user-visible artefact. The gate breaks that promise. The data is not
deleted, but it is unreachable: the hidden-not-deleted defect class that
ADR-037 closed for the catalog.

The same applies to `ActiveOrganizationUnknownNonConnectivityFailure`: one
non-connectivity error replaces a working song list with "Could not verify
access. Please sign out and sign in again."

### G-E — uncaught auth-stream errors every 20 s offline (measured)

`AppAuthController` subscribes to `watchSession()` without `onError`
(`apps/lyron_app/lib/src/application/auth/app_auth_controller.dart:19`).
gotrue adds an `AuthRetryableFetchException` to `onAuthStateChange` at the
end of every failed refresh loop. The auto-refresh ticker (10 s) starts a
new loop whenever none is in flight.

Probe, 62 s offline in the foreground: 3 uncaught errors (at 12.4 s, 32.4 s
and 52.4 s) and 21 HTTP attempts. On native there is no guarded zone, so
each error reaches `PlatformDispatcher.onError`, where Sentry's
`OnErrorIntegration` records it as unhandled, level `fatal`. That pollutes
crash-free metrics and fills Sentry's bounded offline cache, which can push
real crash reports out of it.

### G-F — capabilities are in memory only (code read)

`CapabilityResolver`
(`apps/lyron_app/lib/src/application/auth/capability_resolver.dart`) keeps
resolved capabilities in memory and fetches them again on every cold start
through `get_my_capabilities`. That RPC sits behind the same `getSession()`
wait.

- `IfCapability` fails open only after that call errors
  (`apps/lyron_app/lib/src/presentation/shared/if_capability.dart:72`), so
  "Add song" and the other gated affordances appear ~10–12 s late offline.
- The song list's Import item reads `hasCapabilitySync`
  (`apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart:294`).
  A failed resolve never populates it, so the item stays hidden for the whole
  offline session.

The wider problem is recorded in
`docs/deferred/2026-09-30-capability-gating-offline-cold-start.md`.

### G-G — staleness is invisible (code read)

The header sync control
(`apps/lyron_app/lib/src/presentation/sync/unified_sync_header_control.dart`)
colours its dot from pending local work only. Offline with nothing pending it
shows a green "Synced". Freshness appears only in the tooltip, as raw
identifiers (`AppStrings.unifiedSyncFreshnessOfflineCached` is the literal
`'offline_cached'`). Nothing shows when the data was last refreshed, although
both stores persist it (`CachedCatalogSnapshots.refreshedAt`,
`PlanningProjectionOwners.refreshedAt`).

Once the gate shows the last known state immediately (SG1), the user can be
looking at old data without any sign of it.

### G-H — why the tests never saw any of this

- Every app-level test overrides `membershipRefreshEffectProvider` with a
  no-op and pre-seeds `ActiveMembershipController`
  (`apps/lyron_app/test/app/lyron_app_test.dart`).
- The cold-start integration tests replace `activeOrganizationReaderProvider`
  and `catalogSessionVerifierProvider` with fakes that answer instantly
  (`apps/lyron_app/test/integration/offline_authenticated_cold_start_test.dart`).

No test exercises the real gate together with gotrue's real refresh latency.

## Invariant

ADR-037's invariant is extended from the read contexts to everything the
startup path shows:

> What the user sees comes from the last known local state. A network
> outcome may change it only when it is a fresh, authenticated, **successful**
> response. Failures of any kind (connectivity, timeout, 5xx, a failed token
> refresh, a non-connectivity error) set status only. They never hide data,
> close the gate, or remove an affordance the last known state granted.

The four causes ADR-037 allows for a context change stay the only causes for
the gate leaving the home route for a user with a last known organization:

- a D1 purge;
- an explicit sign-out;
- a fresh online resolution naming a different organization (the gate stays
  open; the contexts switch);
- a different-user sign-in.

## Product decisions (confirmed 2026-10-05)

1. **`verifiedEmpty` closes the gate only after the D5 purge has run.**
   Until then the user keeps the home route, with two exceptions (SG2).
2. **Edit affordances work offline from the last known role.** The backend
   stays the authority (AGENTS.md rule 5).
3. **A visible "last synced" indicator is required.**
4. **First run without a last known organization shows a loading state.**
   After 15 s with no answer, the connectivity message with Retry appears.

## Decisions

### SG1 — the gate decision comes from the last known identity

The gate decision is a pure function of local state, evaluated
synchronously. No widget awaits the network before deciding.

**Inputs:**

- the current user: `session.userId` in `signedIn`,
  `lastKnownSession.userId` in `sessionExpired`;
- the known organization: `LastKnownIdentity.organizationId` when the
  identity's `userId` equals the current user, otherwise none;
- the live resolution for the current user (SG3), or none yet;
- whether a pending invite token exists;
- whether the first-run timer (SG4) has elapsed.

**Decision:**

| Known organization | Live resolution | Pending invite token | Shows |
|---|---|---|---|
| present | anything except `verifiedEmpty` | any | home |
| present | `verifiedEmpty` | no | home (SG2) |
| present | `verifiedEmpty` | yes | `RedeemProgressScreen` (SG2) |
| absent | `selected` | any | home |
| absent | `verifiedEmpty` | no | `InviteRequiredScreen` |
| absent | `verifiedEmpty` | yes | `RedeemProgressScreen` |
| absent | none yet, timer running | any | loading (SG4) |
| absent | none yet and timer elapsed, or `unknownConnectivityFailure` | any | connectivity message with Retry |
| absent | `unknownNonConnectivityFailure` | any | non-connectivity message |

**Constraints:**

- **Identity changes must reach the gate.** A purge (ADR-035 D1, D5) clears the identity
  (`LocalDataLifecycle.clearIdentity` → `noteLastKnownIdentity(null)`,
  `apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart:356-379`).
  That is how the gate learns a purge happened. The notification must not go
  through `AppAuthController.notifyListeners`: `capabilityResolverProvider`
  invalidates on every notification from that controller
  (`auth_providers.dart:868`).
- **The router redirect uses the same decision.** Today it reads
  `membershipController.last is! ActiveOrganizationSelected`
  (`app_router.dart:76,93`); it must ask whether the decision is "home"
  instead. Otherwise the gate and the redirect can disagree.
- **No asynchronous store read.** The decision reads only the identity. The
  identity is loaded before auth leaves `initializing`, so it is available
  on the first home frame. An identity that exists without an organization
  (the F-D cases in the 2026-09-28 spec) falls through to the
  absent-organization rows. The existing cached fallback
  (`resolveWithCachedFallback`) still covers that case after a live failure.
- **G-B closes as a consequence.** In `sessionExpired` the current user comes
  from `lastKnownSession`, so a known organization opens the gate with no
  network and no session.

### SG2 — `verifiedEmpty` waits for the purge (product decision 1)

With a known organization, a live `verifiedEmpty` does not change the gate.
D5 runs exactly as ADR-035 specifies: the marker, the 60 s monotonic
cooldown, the second fresh confirmation, and the pending-work dialog.

When the purge runs, it clears the identity, and the known organization
becomes absent. The gate's own live resolution is not enough at that point.
It runs only on sign-in edges, so it can still hold an older `selected`: the
second D5 confirmation usually comes from a catalog or planning refresh. The
gate therefore registers a purge handler on
`VerifiedEmptyMembershipCleanupCoordinator`, which fires only after a purge
genuinely ran. That handler records `verifiedEmpty` for the purged user, and
the decision table then selects `InviteRequiredScreen`.

**Exceptions:**

1. **No known organization** (first sign-in, or after a purge): switch
   immediately. There is nothing to protect.
2. **A pending invite token exists:** show `RedeemProgressScreen`
   immediately, as today. Redemption starts only while that screen is
   mounted (`apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart:26`).
   Keeping the user on the home route would strand the invite of a member
   who was removed and is now joining another organization. This is an
   explicit user action, the screen is transient, and it deletes nothing.

**Accepted cost.** A genuinely revoked member keeps seeing cached data until
the purge runs: at least the 60 s cooldown plus the next fresh resolution
online, and indefinitely offline. Their writes are rejected by RLS and
surface as `authorizationDenied` (#77). A member who declines the purge
dialog because of pending work stays on the home route with no further
signal. The informational notice for that case is deferred
(`docs/deferred/2026-10-05-membership-revoked-notice.md`).

**Side effect.** `songCatalogControllerProvider` is `autoDispose`. While
`InviteRequiredScreen` was showing, the catalog's periodic refresh was not
running, so the second D5 confirmation had to come from planning sync or the
next sign-in edge. Keeping the home route mounted lets D5 complete through
its normal refresh paths.

### SG3 — live resolution bookkeeping

- `ActiveMembershipController` starts **unresolved**, not
  `unknownConnectivityFailure` (closes G-C).
- The live resolution is scoped by `userId`. An explicit sign-out or a
  different user resets it to unresolved.
- An `unknown*` result never overwrites a `selected` result for the same
  user. Failures are status, per the invariant.
- A result for a user other than the current one is dropped. That covers a
  resolution started under one user that completes after another has signed
  in.
- The resolution keeps running in the background exactly as today, and the
  cached fallback (ADR-016) stays as the absent-organization path. Neither
  the fallback nor this bookkeeping may set or clear `membershipRevokedAt`
  (ADR-035 D5.2, unchanged).

### SG4 — first run without a known organization (product decision 4)

- While no live result exists, the gate shows a loading state with its own
  copy, never the failure message.
- If no result arrives within **15 s**, the connectivity message with Retry
  appears. The original request keeps running; whichever answer arrives
  first is shown, and a later success replaces the message.
- A live `unknownConnectivityFailure` shows the message immediately, without
  waiting for the timer.

**Why 15 s.** It is above the 10 s native connect timeout, so an unroutable
network reports its real failure before the timer fires. Only a connection
that opens but never answers (up to the 60 s / 120 s response backstops) hits
the timer. This state is mostly reached right after an online sign-in, where
the token is fresh and the answer is fast.

### SG5 — handle auth-stream errors (closes G-E)

`AppAuthController`'s subscription gets an `onError`:

- A connectivity-classified error (`isConnectivityFailure`) is dropped. A
  breadcrumb is optional; it must not become an event.
- Any other error is reported once as a handled error through
  `FlutterError.reportError`, matching the controller's existing reporting
  style.
- Auth state does not change in either case. `cancelOnError` stays `false`.

### SG6 — persist the last known capabilities (product decision 2, closes G-F; PR 2)

This implements option (a) of the capability deferred entry, with that
entry's requirements:

- **Storage.** Persist the last successfully resolved capability set, keyed
  by `(userId, organizationId)`, in the `LastKnownIdentity` database (its
  schema is at version 2). It is cleared inside the same
  `LocalDataLifecycle.clearIdentity` operation that clears the identity.
  Every purge, sign-out and different-user wipe therefore removes it with no
  new `PurgeTarget`, which also avoids the S3 ↔ S6 hotspot (`LocalDataLifecycle`,
  `PurgeTarget`, the pending-work count).
- **Write.** Only after a successful `get_my_capabilities` response, and only
  if the stored identity still matches `(userId, organizationId)`, in the
  same store statement. This is the ADR-035 "single atomic operation" shape,
  so a resolve that completes after a purge cannot write the set back.
- **Read.** `CapabilityResolver` seeds its in-memory answers from the store,
  so `hasCapabilitySync` answers before any network call. `invalidate()`
  clears in-memory state and re-seeds from the store. It never deletes the
  stored set.
- **Failure.** A failed resolve keeps the stored set.
- **Ownership.** A stored set is never applied to a different user or
  organization.
- **No stored set.** `IfCapability`'s documented fail-open remains for first
  launch offline. The Import item keeps its current behaviour of hidden while
  unknown.
- **Security.** Capabilities stay UX-only. The backend RLS and RPC checks
  remain the authority (AGENTS.md rule 5).

### SG7 — visible "last synced" indicator (product decision 3, closes G-G; PR 2)

- The sync popup shows the last successful refresh time separately for songs
  and for plans. The sources are the persisted
  `CachedCatalogSnapshots.refreshedAt` and `PlanningProjectionOwners.refreshedAt`
  for the current `(userId, organizationId)`. The format is relative ("5 min
  ago", "2 days ago"), with no new package dependency.
- When freshness is not `fresh` (`offlineCached`, `stale`), the header control
  shows that without the user opening the popup: a distinct visual state and
  an accessible label. Pending-work colours (green / amber / red) keep their
  current meaning.
- The tooltip and popup use human-readable copy. The raw identifier values
  (`'offline_cached'`, `'stale'`) are no longer shown to users.
- The timestamps are device wall-clock values. They are used for display only
  and never in a comparison or ordering decision (ADR-030).

### SG8 — a test with real gotrue latency (closes G-H)

At least one integration test runs the startup path with:

- a real `SupabaseClient` and `GoTrueClient`;
- a persisted session whose JWT `exp` is in the past;
- an HTTP client that (a) fails instantly and (b) never completes.

It must **not** override `membershipRefreshEffectProvider`,
`activeMembershipControllerProvider`, `activeOrganizationReaderProvider` or
`catalogSessionVerifierProvider`.

It asserts:

- the home route and the cached song list render without advancing time
  past the first frames;
- no uncaught error is raised while the refresh loop fails (SG5);
- in `sessionExpired` with a known organization, the home route and the
  re-auth banner render (G-B).

`docs/testing/testing-strategy.md` records the rule: a fake that answers
instantly does not prove an offline path. At least one test per offline
startup path keeps the real auth client.

## Delivery

Two PRs, in this order. PR 1 comes from this branch. PR 2 starts from `main`
after PR 1 merges, on `fix/offline-first-affordances` (squash merges make
reusing this branch conflict-prone).

- **PR 1 (field symptom):** SG1–SG5 and SG8. This ships the fix for the reported
  10–15 s wait by itself.
- **PR 2 (offline affordances and freshness):** SG6 and SG7.

## Roadmap impact

- The slice runs next, ahead of S5a, because it is a field-reported bug.
- SG6 pulls S6 option (a) forward. S6 keeps option (b) (the rejected-delete
  copy), the org-id telemetry leak, the `sessionExpired` test and the
  centralized scrub hooks.
- Doing SG6 now does not conflict with the "S3 and S6 never in parallel"
  constraint. S3 has not started, and SG6 adds no new `PurgeTarget`.
- `docs/plans/2026-10-01-delivery-roadmap.md` is updated in the same change
  as this spec.

## Non-goals

- **gotrue's offline refresh churn.** The loop restarts about every 20 s
  offline, every sync or network call waits 10–12.5 s, and the 120 s
  token-refresh backstop applies to sync. Once nothing on screen waits for
  the network, these cost latency and battery, not visibility. Deferred to
  `docs/deferred/2026-10-05-offline-token-refresh-churn.md`.
- **An informational "access may have been revoked" notice.** Deferred to
  `docs/deferred/2026-10-05-membership-revoked-notice.md`. ADR-035's rejection
  of a blocking quarantine banner stands.
- **D5 purge semantics** (marker, cooldown, confirmation, concurrency model)
  and the `signedOut`-vs-`sessionExpired` mapping (ADR-020). Both unchanged.
- **S6 option (b) and the telemetry items.** They stay in S6.
- **Package upgrades** of `supabase_flutter`, `supabase` or `gotrue`.
- **Web-specific offline behaviour**
  (`docs/deferred/2026-06-29-web-offline-e2e.md`).

## Acceptance

**PR 1:**

- Offline cold start with an expired token and a known organization: the
  home route with the cached song list is the first post-bootstrap screen,
  with no network wait, for every network shape in the G-A table and for a
  never-completing client (SG8).
- `sessionExpired` cold start with a known organization: home route and
  re-auth banner (G-B).
- Online first sign-in: loading state, then home; the failure message never
  flashes (G-C).
- With a known organization, one or more live `verifiedEmpty` results keep
  the home route until the D5 purge clears the identity, then
  `InviteRequiredScreen` appears. With a pending invite token,
  `RedeemProgressScreen` appears immediately (SG2).
- A live `unknown*` result never replaces a `selected` result for the same
  user, and a result for another user is dropped (SG3).
- No uncaught error while gotrue's refresh fails offline (SG5).
- Tests that encoded the old behaviour are updated to the new decision table,
  not deleted. This includes the gate tests in `lyron_app_test.dart` that
  assert the connectivity message as the first state.
- Full suite and `./scripts/verify.sh` green.

**PR 2:**

- The red tests listed in the capability deferred entry:
  - a resolver seeded from storage answers `hasCapabilitySync` with no
    network call;
  - a failed resolve keeps the stored set;
  - a stored set is never applied to another user or organization;
  - `IfCapability` with no stored set and a failing resolve still shows its
    child.
- A capability write that completes after a purge does not resurrect the set.
- Offline cold start with a stored set: gated affordances, including the
  Import item, are available as soon as the local store read completes,
  without waiting for the network.
- The popup shows both last-synced times. The header shows non-fresh state
  without opening the popup. No raw identifier appears in any user-visible
  text.
- Full suite and `./scripts/verify.sh` green.

## Documentation updates (in the implementation PRs)

- **ADR-040** (new): the startup gate and affordances derive from the last
  known local state. It supersedes the gate half of ADR-016's cached-fallback
  semantics and amends ADR-037's invariant scope.
- **ADR-016 and ADR-037:** status notes pointing to ADR-040.
- **`docs/architecture/architecture.md`:** correct the ADR-020 paragraph's
  claim about the gate in `sessionExpired`, describe the gate decision, and
  (PR 2) capability persistence in the authorization section.
- **`docs/testing/testing-strategy.md`:** the real-auth-client rule (SG8).
- **`docs/specs/2026-06-28-non-destructive-session-and-offline-relaunch.md`
  and `docs/specs/2026-06-03-offline-membership-gate-cached-fallback.md`:**
  correction notes pointing here.
- **`docs/deferred/2026-09-30-capability-gating-offline-cold-start.md`:**
  narrowed to option (b) in PR 2.
