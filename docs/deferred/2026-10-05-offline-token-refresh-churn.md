# gotrue Keeps Retrying the Token Refresh Offline

**Slice:** fix/offline-first-startup-gate (found by the 2026-10-05 offline
startup investigation, scratch-probe measured; deliberately left out of that
slice)
**Related:**
- `docs/specs/2026-10-05-offline-first-startup-gate.md` (G-A, G-E, Non-goals)
- `docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md`
  ("Amendment: two-tier HTTP timeout")
- `docs/deferred/2026-09-28-client-abandoned-committed-write-lf-t5b.md`

**Files:**
- `apps/lyron_app/lib/src/infrastructure/observability/tracing_http_client.dart`
  (`_tokenRefreshTimeout`, 120 s)
- `apps/lyron_app/lib/src/application/sync/foreground_sync_listener.dart`
- pinned `gotrue-2.27.2/lib/src/gotrue_client.dart`: `startAutoRefresh`,
  `_autoRefreshTokenTick`, `_refreshAccessToken`
- pinned `supabase-2.16.2/lib/src/supabase_client.dart`: `_getAccessToken`

## Problem

With an expired access token and no working network:

- gotrue's auto-refresh ticker fires every 10 s and starts a new refresh loop
  whenever none is in flight. Each loop retries for 10–12.5 s.
- A 62 s probe (offline, in the foreground) measured 21 HTTP attempts. A
  refresh was in flight about 62% of the time.
- Every PostgREST or RPC call awaits `getSession()` first. Every sync, every
  resume-triggered sync and every manual Sync therefore waits 10–12.5 s
  before it can even fail.
- On a connection that opens but never answers, a single `/auth/v1/token`
  attempt can take up to the 120 s backstop.

## Why it was deferred

After the offline-first startup gate slice, nothing on screen waits for the
network. What remains is sync latency, wasted requests, and battery. These are
real, but not visibility or correctness. Each fix touches token-refresh
timing, where ADR-037's R1/I1 history shows the risk is high:

- abandoning a refresh after the server has rotated the token can revoke the
  whole session (reuse-interval rule);
- a hung refresh blocks every request, because `_getAccessToken` awaits it.

## Options

### (a) Pause auto-refresh while known offline

- Call `stopAutoRefresh()` when the platform reports no connectivity, and
  restart it on regain.
- `connectivity_plus`-style signals cannot see "connected but no internet",
  so this only helps the plain airplane-mode case.

### (b) Circuit breaker in front of `getSession()`

- After N consecutive failed refreshes, sync paths skip network work for a
  backoff window instead of awaiting another full loop.
- It must never skip the user's explicit Sync tap.

### (c) Shorter `/auth/v1/token` backstop

- Lower the 120 s backstop toward the 60 s general backstop.
- Requires re-deriving ADR-037's R1/I1 trade-off (token rotation versus a
  dead socket). Not to be done casually.

## Trigger

Pick this up when one of these happens:

- a battery or data-usage complaint from an offline device;
- a field report that sync feels slow after reconnecting;
- a `gotrue` upgrade that changes the refresh loop.

## Requirements for the slice that picks this up

- Measure first, with the scratch-probe method from the 2026-10-05 spec: a
  real `GoTrueClient`, an expired JWT, and a failing HTTP client.
- No change may abandon an in-flight refresh after the server could have
  rotated the token.
- The startup path must still never wait on any of this (2026-10-05 spec
  invariant).
