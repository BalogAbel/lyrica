# ADR-035: Local Data Purge Contract

- Status: Accepted
- Date: 2026-08-21
- Spec: `docs/specs/2026-08-19-local-data-durability-contract.md`
- Plan: `docs/plans/2026-08-19-local-data-durability-contract.md`
- Relates to: ADR-020 (non-destructive session and offline-authenticated
  state), ADR-008 (local-first), ADR-016 (active-organization-resolution
  semantics), ADR-028 (local storage budget and eviction policy)
- Scope: `AppAuthController` (`_stateForSession`), `SongCatalogController`,
  `PlanningSyncController`, and — for the decisions this ADR records but Phase
  1 has not yet built — the future `LocalDataLifecycle` gate, snapshot-write
  path, and membership-revocation quarantine.

## Context

ADR-020 committed to a policy: once a device has synced a song catalog, local
data is destroyed **only** on explicit sign-out or authoritative membership
revocation, never on connectivity-driven or unknown session loss. That intent
was implemented as a set of individually-correct branches rather than as an
enforced invariant, and it had no single structural owner. Four independent
code paths escaped it (catalogued as F1–F4 in the spec above, with F5/F6
covering related storage-eviction and Android-backup gaps). The dominant
contributor, reported 2026-08-19: an Android tablet left offline for a day or
two showed an empty song catalog on the next cold start, recoverable only by
going online and signing in again.

**This ADR enforces ADR-020; it does not supersede it.** ADR-020 set the
policy. This ADR is the record of what makes that policy structural and
actually reachable in code, decision by decision, across the four phases of
`docs/plans/2026-08-19-local-data-durability-contract.md`. It amends ADR-028
(the eviction trigger and its proportionality) and corrects
`docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`, whose two specific
false-at-the-time claims are fixed in place there rather than repeated here.

## Decision

Local user data may be destroyed for exactly four reasons, and nothing else:

| `PurgeReason` | Trigger | Confirmation |
| --- | --- | --- |
| `userSignOut` | The user activated the sign-out control | none |
| `accountDeleted` | The user deleted their account | none |
| `differentUserSignIn` | A different `userId` signs in on this device | dialog when pending work exists (existing behaviour) |
| `membershipRevokedConfirmed` | Two consecutive fresh, online, authenticated empty-membership resolutions | no pending work, or the user confirmed |

Explicitly forbidden as purge triggers, restated so a future reader can tell
intent from accident: any `null`-session event from the auth stream for any
reason (including a corrupt persisted session or an expired/already-used
refresh token); Supabase token expiry in any form; a successful-but-empty
`listSongs()` response; a single `verifiedEmpty` membership resolution; any
exception raised by a guarded local write; and any phase of cold start.
Storage eviction is a separate mechanism with its own trigger and its own
proportionality rule — it is not a purge reason, and it may never remove
anything a purge reason would not.

The full contract spans eight decisions, D1–D8. As of this ADR, three are
implemented; five are decided and scheduled, not yet built. This ADR records
all eight so the decision is durable, and is explicit below about which half
is which.

### Implemented in Phase 1 (this slice)

**D1 — the four-purge-reason enumeration above, as a stated contract.**
Nothing in Phase 1 changes the code paths that already respect it (explicit
sign-out, account deletion, different-user sign-in, verified-empty
membership); Phase 1 closes the paths that were violating it by accident.

**D2 — `signedOut` requires an explicit act; everything else is
`sessionExpired`.** `AppAuthController._stateForSession`
(`apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`) dropped
its old `_state.status == AppAuthStatus.signedIn` guard. A `null` session now
maps to `signedOut` only when the app itself initiated the sign-out
(`_isSigningOut`) or no `LastKnownIdentity` exists — i.e. there is no user
whose data could be protected. Every other case, including a `null` arriving
during cold start (`initializing`) or while already `sessionExpired`, maps to
`sessionExpired` instead of being wrongly treated as an explicit sign-out.
This requires `LastKnownIdentity` to be synchronously readable at the moment a
stream event is handled: the identity is loaded into memory at controller
construction, before the stream subscription goes live, and events arriving
before that load settles are buffered and replayed against the now-known
identity rather than evaluated against an unknown one.

**D3 — reads are served from the local database, not from a live session.**
`SongCatalogController.handleOfflineAuthenticated()` and
`PlanningSyncController.handleOfflineAuthenticated()`
(`apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`,
`apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`)
give each controller an offline-authenticated entry path: in
`sessionExpired`, each establishes its read context from
`LastKnownIdentity`'s `userId`/`organizationId` whenever a matching local
snapshot (catalog) or projection (planning) exists for that pair — with no
network call and no live session check. Both are deliberately redundant with
D2: even if a purge path were ever reintroduced, or a device reaches a state
this spec did not anticipate, the read path itself no longer depends on
anything that can expire.

### Decided, not yet implemented (Phases 2–4)

The remaining five decisions are settled — confirmed with the product owner
where noted in the spec — and scheduled in
`docs/plans/2026-08-19-local-data-durability-contract.md`. None of them are
built as of this ADR:

- **D4 — conditional, organization-scoped snapshot replacement** (Phase 3).
  An empty incoming snapshot must not replace a non-empty stored one without a
  second independent empty confirmation; `_deleteUserSnapshots` narrows from
  `(userId)` to `(userId, organizationId)`; replacement adopts an explicit
  blue/green write shape.
- **D5 — `verifiedEmpty` quarantines before it purges** (Phase 4). The first
  empty-membership resolution records `membershipRevokedAt` and quarantines
  the data read-only; the purge itself needs a second fresh, online,
  authenticated empty resolution plus no pending work or user confirmation.
- **D6 — eviction is triggered by storage pressure and proportionate to it**
  (Phase 3). Amends ADR-028: eviction fires only on a concrete
  storage-exhaustion signal or a measured footprint over budget, evicts
  least-recently-read first, and marks the affected snapshot recoverable on
  the next online refresh.
- **D7 — one gate, one audit trail** (Phase 2). Every purge primitive
  (`deleteCatalogsForUser`, `deletePlanningDataForUser`,
  `LastKnownIdentityStore.clear()`) becomes reachable only through a single
  `LocalDataLifecycle` seam that requires a `PurgeReason`, enforced by an
  architecture test, with every purge and eviction writing a
  `local_data_events` audit record. This is the decision that makes the
  contract durable rather than merely correct today — the compiler and one
  test, not reviewer memory, keep a future feature from opening a fifth path.
- **D8 — Android backup is deterministic** (Phase 4). Set
  `android:allowBackup="false"`, or supply data-extraction rules that keep the
  session store and the SQLite databases in the same backup set, so a
  half-restored device cannot be representable.

Do not read D4–D8 as implemented from this ADR's existence. They are recorded
here, ahead of their landing, so the full contract has one durable home; each
lands with its own commits and its own review in Phases 2–4.

## Why Acceptance-1 and Acceptance-2 are not redundant

Both acceptance tests defend against "the catalog going empty while offline,"
which invites reading them as duplicates. They are not: they guard two
different code paths.

Acceptance-1 (cold start, offline, expired access token, valid refresh token)
turns out — verified against the pinned `gotrue`/`supabase_flutter` source —
not to exercise this phase's new machinery at all. `setInitialSession`
installs a persisted expired session unconditionally, so `currentSession`
stays non-null; the background refresh's offline failure is retryable and
`gotrue` does not clear the session for a retryable failure. The app therefore
stays `signedIn`, and the scenario is already handled by the pre-existing
connectivity-failure fallback in `SongCatalogController._refreshCatalog`
(cached organization id, ADR-016). Acceptance-1 exists to guard that
pre-existing fallback from a Task-1.2/1.3 regression, not to prove D2/D3.

Acceptance-2 and Acceptance-3 (a `null` session actually reaching the app —
`gotrue` emitting `signedOut`, or the persisted session vanishing from
SharedPreferences while `LastKnownIdentity` survives) are what actually
exercises D2 and D3: they are the cases where a live session is genuinely
gone and the offline-authenticated read path is the only thing standing
between the user and an empty screen. The real field trigger for the reported
bug is more likely a non-retryable refresh failure (a rotated or already-used
refresh token), which does produce a `null` session and, before this phase,
deleted the persisted session client-side too — making the broken state
self-perpetuating across launches. That is the failure mode D2/D3 close.

## Consequences

A user whose refresh token has genuinely expired is no longer bounced to the
sign-in screen. They stay offline-authenticated: cached songs and plans
remain fully readable, edits keep queueing locally, and sync resumes
automatically once they re-authenticate through the re-auth banner. This is
the user-visible behaviour ADR-020 already committed to; Phase 1 is what
makes it actually reachable rather than aspirational.

Until Phase 2 lands D7, the four purge reasons in D1 remain a *stated*
contract, not a *structurally enforced* one: the call sites that respect it
today do so because Phase 1's fixes close the paths that were violating it,
not because a gate forbids a new violation from being added. A reviewer
reading this ADR should treat D1 as binding policy and D7 as the outstanding
work that makes violating it a compile-time or test-time failure instead of a
review miss.

## Non-Goals

Carried unchanged from the spec: no web durability guarantee (D2/D3/D4's
platform-independent logic runs on web, but IndexedDB durability and web
eviction remain best-effort with no acceptance test); no change to the
refresh-token TTL or any hosted Supabase Auth setting (D2 makes it irrelevant
to data durability, not to sync); no rework of
`SongCatalogController`'s refresh state machine beyond its entry conditions
and snapshot-write decision; no multi-account support; no server-side soft
delete or undo (quarantine, D5, is local only).
