# Refresh-Token TTL Is the Real Offline Ceiling (LF-T2)

**Status:** Closed as a data-durability concern, 2026-08-21. See "Correction"
and "Update" below — the refresh-token TTL bounds *sync*, never *local data*,
and the two claims in this document that asserted local-data safety was
already true are corrected in place. The document otherwise stands.

**Slice:** offline-durability-phase4 (S15)
**Finding:** `LF-T2` (`docs/architecture/repository-review-2026-06-22.md`)
**Files:**
- `apps/lyron_app/lib/src/infrastructure/auth/supabase_auth_repository.dart:20`
  (`onAuthStateChange` → `null` session mapping; this is where a refresh failure
  surfaces)
- `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart:168-206`
  (`_stateForRestoredSession`, `_stateForSession` — as of Phase 1 of
  `docs/specs/2026-08-19-local-data-durability-contract.md`, both map a `null`
  session to `AppAuthStatus.sessionExpired`, never to data loss; see
  "Correction" below — this document originally claimed that as already true,
  and it was not)
- `apps/lyron_app/lib/src/application/auth/last_known_identity.dart` (the durable
  identity seam that lets cold start recognize a known user without a live session)
- `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart:255-263`
  (`handleSessionExpired` — resets transient sync state only, keeps the projection)
- `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart:322-325`
  (`handleSessionExpired` — same non-destructive shape on the catalog side)
- `docs/architecture/decisions/ADR-020-non-destructive-session-and-offline-authenticated-state.md`
- `supabase/config.toml:35` (`jwt_expiry = 3600` — this is the **access**-token TTL
  only; the refresh-token TTL is a hosted Supabase Auth project setting, not a
  value this repository's local `config.toml` carries)

## Problem

Supabase's gotrue client refreshes the short-lived access token (`jwt_expiry`,
`3600`s locally) automatically using a longer-lived refresh token. When the
refresh token itself can no longer be redeemed — because it has exceeded its own
TTL, or because the project's inactivity/session-timebox policy has expired it —
`onAuthStateChange` emits a `null` session
(`supabase_auth_repository.dart:20`) with no client-side retry path: there is
nothing the app can do locally to mint a new refresh token, since that operation
requires reaching the auth backend. This is the "hard wall" the original finding
named: no matter how generous the client's local-first design is, real continuous
offline operation cannot outlast the refresh token's TTL, because at that point
the auth SDK itself gives up.

## What LF-T1 / ADR-020 Already Cover

Before ADR-020, a `null` session — for any reason, including this one — was
treated as authoritative and destructive: it wiped the local catalog and
planning projections (`LF-T1`). LF-T1's fix, which this finding's own text names
as covering "decouple local access from live session validity", changed that:
`AppAuthController` now maps a `null` session to `AppAuthStatus.sessionExpired`
rather than `signedOut` whenever a live session or a durable `LastKnownIdentity`
record says who the user is (`app_auth_controller.dart:168-206`). Both
`PlanningSyncController.handleSessionExpired` and
`SongCatalogController.handleSessionExpired` reset only transient sync state and
leave the projection/cache/pending-mutation data untouched
(`planning_sync_controller.dart:255-263`,
`song_catalog_controller.dart:322-325`). No screen other than the re-auth banner
and the sign-in screen branches on `sessionExpired`
(`presentation/auth/reauth_banner.dart`, `presentation/auth/sign_in_screen.dart`).

## Correction (2026-08-21)

This document, as originally written, claimed the paragraph above already
meant "no read path and no edit path in the app gates on live session
validity" — stated as a present-tense fact about the code at the time. **That
claim was false when written.** The Local Data Durability Contract
(`docs/specs/2026-08-19-local-data-durability-contract.md`, finding F1) traced
the actual code and found `AppAuthController._stateForSession` mapped a
`null` session to the destructive `signedOut` — not `sessionExpired` — in two
cases this paragraph did not account for: during cold start, before
`restoreSession()` had settled (`initializing`), and when the app was already
`sessionExpired`. Both are ordinary, non-error states, not edge cases, and
`signedOut` in turn drove `handleExplicitSignOut()` to delete the catalog, the
planning projection, and the identity record — the exact "empty catalog after
an offline day or two" symptom this document's own scenario describes.
Separately, `songLibraryListProvider`'s read gate depended on
`SongCatalogController`'s `context`, which was never populated in
`sessionExpired` at all (F2) — so even a correctly-computed `sessionExpired`
state left the UI showing nothing, independent of F1.

Both gaps are closed now, as of Phase 1 of that spec
(`docs/architecture/decisions/ADR-035-local-data-purge-contract.md`, D2 and
D3) — not because the pre-existing `_stateForSession`/`_stateForRestoredSession`
split was already sufficient, which is what this document originally implied.
D2 removed the `_state.status == AppAuthStatus.signedIn` condition that made
`_stateForSession` destructive in `initializing`/`sessionExpired`; D3 gave
`SongCatalogController` and `PlanningSyncController` an
`handleOfflineAuthenticated()` path that establishes read context from
`LastKnownIdentity` against the local database, with no live session check.
The sentence "no read path and no edit path in the app gates on live session
validity" is accurate as a description of the code **today**, as a
consequence of that phase's changes — not as an inherent property of the
split this document originally cited it for.

## What Genuinely Remains

The refresh-token TTL itself is unchanged by LF-T1 or ADR-020, and it cannot be
changed from the client. It is a property of the auth provider's token
lifetime/session policy (refresh-token expiry, rotation, and any
inactivity-timeout or session-timebox setting configured on the hosted Supabase
project's Auth settings) — not something `apps/lyron_app` code can extend,
retry around, or work past. `supabase/config.toml` only pins the local dev
stack's access-token TTL (`jwt_expiry = 3600`); the refresh-token TTL that
actually bounds a real deployment is set on the hosted project and is not
visible in this repository at all. ADR-008's "up to one week offline" target is
a product commitment with no verified relationship to that number: nothing in
this codebase confirms the configured refresh-token TTL is actually ≥ one week.

## What This Review Established About the Actual Loss

The distinction that decides how serious this residual is: **does exhausting the
refresh token TTL while offline cost the user local read access, or only the
ability to sync?**

Established from the code cited above: only **sync**. Once the refresh token can
no longer be renewed, `onAuthStateChange` delivers `null`, the app lands in
`sessionExpired`/offline-authenticated (not `signedOut`), and, as of Phase 1 of
the Local Data Durability Contract (see "Correction" above) — this was not
true when this document was originally written:
- Cached songs and plans remain fully readable — nothing in the read path checks
  live session validity.
- New edits keep working — they queue as local mutations, which require only
  local storage.
- What stops working is **pushing pending mutations to the backend and pulling
  remote changes**, because those are RPC calls that need a valid access token,
  and no valid one can be minted until the user completes an **interactive**
  re-auth (sign-in), not a silent refresh.

That interactive re-auth itself requires connectivity — so the practical
consequence of exhausting the refresh-token TTL while genuinely offline is not
"the app becomes unusable"; it is "sync stays paused, exactly as it already is
for any offline stretch, until the user is back online and re-authenticates."
The one qualitative change past the TTL boundary is that reconnecting alone is
no longer enough — the silent token refresh that would otherwise resume sync
automatically can no longer happen, and the user must pass through the re-auth
banner's sign-in flow once connectivity returns. Local data is not at risk
either way: it survives until explicit sign-out or an authoritative
verified-empty-membership revocation, per ADR-020's policy matrix.

## Update (2026-08-21)

This closes `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md` as a
data-durability concern: the refresh-token TTL bounds *sync*, never *local
data* — per D2 of `docs/specs/2026-08-19-local-data-durability-contract.md`.
The two sections above are corrected in place rather than the conclusion
being restated fresh, because the underlying conclusion does not change: it
is simply more true now than when this document was written, since the read
path it describes no longer has the two gaps (F1, F2) that would have made it
false in the offline-authenticated cases that matter most. What "Deferred
Because" and "Trigger Condition" below still hold as sync-only concerns: the
refresh-token TTL itself is unaddressed, unmeasured, and out of this
repository's control, and closing *that* — if it is ever needed — remains a
Supabase Auth project-configuration action, not a data-durability one.

## Deferred Because

Fixing the hard wall itself means lengthening or rotating the refresh token's
TTL, or otherwise decoupling redemption from a fixed expiry — that is a
configuration or product decision on the Supabase Auth project, not a code
change `apps/lyron_app` can make unilaterally. There is no in-repo lever to
pull: the local `config.toml` does not even carry the setting that would need
to change. Committing to a specific longer TTL, or a rotation scheme, without a
stated need would be speculative hardening for a wall whose real-world height is
currently unmeasured.

## Trigger Condition

Address when either of these holds:

- The product commits to (or is asked to support) a **continuous offline span
  longer than the currently configured refresh-token TTL** on the hosted
  Supabase project. ADR-008's "up to one week" target is the natural candidate:
  if the configured refresh-token TTL is confirmed to be shorter than one week,
  that is concrete evidence the wall sits inside the product's own stated
  offline horizon and needs to move.
- A decision is made to extend or restructure the refresh-token lifetime on the
  Supabase side (longer TTL, rotation policy, or disabling an inactivity/session
  -timebox setting), for this reason or another. At that point the client-side
  half (LF-T1/ADR-020) already in place needs no further change — it already
  treats any `null` session, from any cause, as non-destructive — so closing
  this item is purely a backend/project-configuration action plus confirming
  the configured value against the product's stated offline target.
