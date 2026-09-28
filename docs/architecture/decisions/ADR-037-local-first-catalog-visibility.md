# ADR-037: Local-First Catalog Visibility

**Status:** Accepted (design-gate approved 2026-09-28; implemented on
`fix/offline-catalog-local-first-visibility`, including a planning-side
mirror of the same fix, an ownership guard so a stale different-user context
can never surface, and reauth-routing for the manual Sync control — see the
spec's own commit history for the full list of adversarial-review findings
closed before merge)
**Amends:** D3 of
`docs/architecture/decisions/ADR-035-local-data-purge-contract.md`'s
companion spec (`docs/specs/2026-08-19-local-data-durability-contract.md`,
D3) and, implicitly, ADR-020's non-destructive-state policy by tightening
*when* the read context is established, not by loosening what may destroy it.
**Context spec:**
`docs/specs/2026-09-28-offline-catalog-local-first-visibility.md`

## Context

D3 (2026-08-19) established that `SongCatalogController` and
`PlanningSyncController` gain an offline-authenticated entry path —
`handleOfflineAuthenticated()` — that sets the read `context` from
`LastKnownIdentity` with no network call. As written, D3 wired this as a
one-shot gap-filler invoked only at the `signedIn → sessionExpired` auth
*transition* (`song_catalog_providers.dart:124-127`). Everywhere else,
`context` remained an output of the network refresh path
(`_refreshCatalogBody`), and roughly nine branches inside that path reset
`context` to null on some auth or network outcome.

Field investigation (2026-09-28) found this insufficient in two ways:

1. **F-A.** On a real device with an expired access token and poor/no
   connectivity, the network refresh itself can hang for minutes (no HTTP
   timeout on the pinned `gotrue`/`supabase` stack), during which the
   one-shot gap-filler has already run (or never had a chance to, if the
   session was still nominally `signedIn`) and the catalog is invisible the
   whole time.
2. **F-B through F-F.** Several of the nine reset branches fire on ordinary,
   non-catastrophic events — a lifecycle resume while `sessionExpired`, a
   single 401, a misclassified connectivity error — none of which the
   original ADR-020/ADR-035 policy intended as purge-equivalent events. The
   read path was, in practice, still gated on live network/auth success far
   more often than D3's stated intent.

## Decision

Tighten D3 into an explicit, narrower invariant, enforced on **every**
branch of the refresh path, not only the one-shot transition:

> The catalog `context` shown to the user comes from local data
> (`LastKnownIdentity` + the local snapshot). Only four things may change
> it: a D1 purge, an explicit sign-out, a fresh online authenticated
> resolution naming a different organization, or a different-user sign-in.
> Network/auth outcomes set status fields only.

Concretely:

- The local-first establishment logic (formerly only
  `handleOfflineAuthenticated`) runs at the **start** of every refresh
  attempt where `context` is null — signed-in or not — not only at the
  auth-transition edge. `handleOfflineAuthenticated()` becomes a thin
  wrapper over the same logic.
- Every `clearContext`/`initial()` site inside `_refreshCatalogBody` that
  does not correspond to one of the four causes above is converted to a
  status-only update (`sessionStatus`/`connectionStatus`/`refreshStatus`
  change, `context` and `hasCachedCatalog` untouched).
- Error classification that gates these branches (`_isAuthorizationFailure`
  vs. connectivity) is corrected so a connectivity failure can never be
  misrouted into the authorization-failure branch.
- A client-side HTTP timeout (15 s) bounds how long any single network
  attempt can hang, so status transitions from "resolving" to
  "offline/failed" promptly instead of never, but this is a UX/latency fix
  — it does not by itself change what a failure is allowed to do to
  `context`; the invariant above is what changes that.

D1/D5 purge logic (ADR-035) and `AppAuthController._stateForSession`'s
`signedOut`-vs-`sessionExpired` decision (ADR-020/D2) are unchanged. This
ADR only narrows what the *catalog controller's own refresh path* is allowed
to do to a `context` it does not own the deletion policy for.

## Consequences

- The catalog can display stale-but-real cached data for longer than before
  under connectivity/auth trouble — this is intentional; ADR-020 already
  established that staleness is preferable to false emptiness, this ADR
  extends that preference to more of the branches that previously
  contradicted it.
- `UnifiedManualSyncController` can no longer infer "nothing to do" from
  `context == null` under `sessionExpired`, since `context` now normally
  stays populated; it gains explicit auth-status awareness instead
  (`requiresReauth` result), so a `sessionExpired` manual Sync press routes
  to re-authentication rather than silently no-op'ing or silently failing
  network calls against a session that cannot succeed.
- Any future branch added to `_refreshCatalogBody` that wants to hide or
  clear `context` must justify itself against the four-cause invariant
  above, not merely against "this call failed."

## Amendment: two-tier HTTP timeout (2026-09-28, PR #79 review)

The 15s single-timeout shape (Step 1 item 2, as originally accepted) bounded
how long a hung request could stay invisible, but wrapped the *entire*
request — including the window after the server has already committed a
write or rotated a refresh token but before the response finishes
transferring. Abandoning a request in that window client-side is worse than
merely slow: for `/auth/v1/token`, it discards a refresh token the server
already rotated, forcing a needless full re-auth outside gotrue's reuse
grace window; for a write RPC, it turns the client's own later retry into a
false optimistic-concurrency conflict against itself.

Replaced with two tiers, later corrected to three (I1, below):

- **Connect timeout (10s, native only)**: bounds the actual "network up, no
  route" hang the original investigation measured (75s worst case), without
  touching in-flight response time at all. No web equivalent exists
  (`BrowserClient` exposes no connect-timeout knob), so web keeps relying on
  the browser's own TCP/TLS timeout, unchanged from before this amendment.
- **Response backstop (60s)**: bounds how long the app waits for a response
  once connected, for every request except a token refresh.
- **Token-refresh response backstop (120s) — corrected by I1 (2026-09-28,
  post-PR#79 adversarial review)**: `/auth/v1/token` was originally fully
  *exempted* from any response backstop, so an in-flight refresh could never
  be abandoned client-side after the connection was established. That
  exemption was itself a regression, worse than the 15s shape it replaced:
  `dart:io`'s connect timeout only covers connect+TLS, not a stall after the
  request is written, so a dead socket on the token endpoint (NAT drop,
  wifi-to-cellular handoff, no keepalive) would hang forever with no bound
  at all. Worse, gotrue's `GoTrueClient._callRefreshToken` de-dupes
  concurrent refreshes for the same token into one shared `Completer`
  (`_pendingRefreshes`), which `SupabaseClient._getAccessToken` awaits
  *before* any REST/RPC call reaches `TracingHttpClient` — so a single hung
  refresh could block every subsequent call in the app, for every identity,
  indefinitely. `/auth/v1/token` now gets a LONGER but still finite backstop
  (120s, well above the 60s general backstop and above any plausible
  upstream gateway timeout) instead of none: this keeps the original intent
  (don't abandon a refresh moments before/after the server rotates the
  token on an ordinary slow-but-alive connection) while bounding the
  dead-socket/hung-forever case.

This does not eliminate the abandon-after-commit risk for write RPCs
entirely — see `docs/deferred/2026-09-28-client-abandoned-committed-write-lf-t5b.md`
for the residual risk and its trigger condition — it narrows the window
from "any request past 15s" to "a write RPC specifically, past 60s of
connected-but-no-response time," and, for the token-refresh case, from
"any request past 15s" to "past 120s of connected-but-no-response time"
rather than to "never."

`docs/specs/2026-08-19-local-data-durability-contract.md`'s D3 section
carries a forward-reference status note (added alongside this ADR) pointing
here, since this ADR is the fuller statement of what D3 originally gestured
at but did not fully enforce.
