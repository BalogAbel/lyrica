# Local Data Durability Contract

> Status: Implemented. All four phases have landed — Phase 1 (PR #73),
> Phase 2 (PR #74), Phase 3 (PR #75), Phase 4's D8 (PR #76), and Phase 4's D5
> on `fix/membership-revocation-confirmation`. D5 shipped re-scoped: the
> read-only quarantine was attempted, reviewed, discarded, and dropped
> permanently; the two-confirmation purge gate is what survives. See D5.0 and
> the Phase 4 closeout in the plan.
>
> Decisions to be recorded durably in
> `docs/architecture/decisions/ADR-035-local-data-purge-contract.md`.
>
> Enforces: [ADR-020](../architecture/decisions/ADR-020-non-destructive-session-and-offline-authenticated-state.md),
> [ADR-008](../architecture/decisions/ADR-008-local-first.md).
> Amends: [ADR-028](../architecture/decisions/ADR-028-local-storage-budget-and-eviction-policy.md).
> Corrects: `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`.

## Goal

Once a song catalog has been downloaded to a device, it stays readable until one
of a small, enumerated set of events destroys it deliberately. No connectivity
condition, no token lifetime, no server hiccup, and no local write failure may
remove or hide it.

Concretely, the acceptance condition:

> An Android tablet that has synced once, is then taken offline and left unused
> for an arbitrary period, shows its full song catalog on every subsequent cold
> start, forever, with no network access.

Web is explicitly **best-effort** for this goal (see Non-Goals).

## Problem

Reported 2026-08-19: on an Android tablet, if the app is not launched for one to
two days and is then started offline, the song catalog is empty. Sometimes the
window is shorter. The user must go online and sign in again to get the songs
back.

ADR-020 already forbids this. It committed to a policy matrix in which local data
is destroyed "**only** on explicit sign-out or authoritative membership
revocation — never on connectivity-driven or unknown session loss," and
`docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md` asserts that policy is
fully realised in code, stating that `AppAuthController` maps a `null` session to
`sessionExpired` "never to data loss" and that "nothing in the read path checks
live session validity."

**Both assertions are false against the current code.** ADR-020's intent was
implemented as a set of individually-correct branches rather than as an enforced
invariant, and four independent paths escape it. That is the root cause: the
policy has no structural owner, so every subsequent change had to re-derive it,
and four of them did not.

The four escapes, in descending order of contribution to the reported symptom:

### F1 — `signedOut` conflates "the user signed out" with "the auth SDK gave up"

[`app_auth_controller.dart:216`](../../apps/lyron_app/lib/src/application/auth/app_auth_controller.dart#L216)
(`_stateForSession`) maps a `null` session to `sessionExpired` **only when the
current status is already `signedIn`**:

```dart
if (fromStream && !_isSigningOut && _state.status == AppAuthStatus.signedIn) {
  return AppAuthState(status: AppAuthStatus.sessionExpired, ...);
}
return const AppAuthState(status: AppAuthStatus.signedOut);
```

When the status is `initializing` — i.e. during cold start, before
`restoreSession()` has settled — or already `sessionExpired`, a `null` session
event yields `signedOut`. And `signedOut` is destructive on three fronts:

- [`song_catalog_providers.dart:91`](../../apps/lyron_app/lib/src/application/song_catalog_providers.dart#L91)
  → `handleExplicitSignOut()` →
  [`song_catalog_controller.dart:361`](../../apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart#L361)
  `deleteCatalogsForUser`
- [`planning_providers.dart:298`](../../apps/lyron_app/lib/src/application/planning_providers.dart#L298)
  → planning projection deletion
- [`auth_providers.dart:121-123`](../../apps/lyron_app/lib/src/application/auth_providers.dart#L121)
  → `identityStore.clear()`, which removes the very record that would have made
  the *next* cold start non-destructive

The auth SDK emits `null`-session events during startup for several reasons that
have nothing to do with the user signing out. Verified against the pinned
versions (`supabase_flutter` 2.17.2, `gotrue` 2.27.2):

| Source | Condition |
| --- | --- |
| `supabase_flutter/src/supabase_auth.dart:126` | `notifyAllSubscribers(initialSession)` with no session — emitted when there is no persisted session **or** when `setInitialSession` threw |
| `gotrue/src/gotrue_client.dart:1236` | `setInitialSession` on a truncated/corrupt persisted session JSON → `_signOut(local, sessionMissing)` → `signedOut` event |
| `gotrue/src/gotrue_client.dart:1624` | `_doRefresh` failing with a non-retryable error (invalid or already-used refresh token) → `_removeSession()` + `signedOut` event |

The third row is reachable in ordinary use: if the process is killed mid-refresh
after the server has rotated the refresh token but before the new one is
persisted, the next launch redeems an already-used token against an
already-expired session, which is exactly the non-retryable branch.

Compounding it, [`app_auth_controller.dart:28`](../../apps/lyron_app/lib/src/application/auth/app_auth_controller.dart#L28)
`restoreSession()` loses a race it cannot win: the stream subscription is
installed before `restoreSession()` awaits, and **every** stream event bumps
`_authGeneration` (line 190). A `null` event arriving during the await therefore
discards the correctly-computed `sessionExpired` state and leaves the
stream-computed `signedOut` in place.

Net effect: a single mistimed `null` event on a cold start wipes the local
catalog, the planning projection, and the identity record — and offline the user
has no way to recover any of it.

Verified against the pinned versions (`supabase_flutter` 2.17.2, `gotrue`
2.27.2): an expired access token with a valid refresh token, offline, does
**not** produce a null session. `setInitialSession` installs the persisted
(expired) session unconditionally — `currentSession` stays non-null — and the
background auto-refresh's offline failure is a retryable
`AuthRetryableFetchException`, which `_doRefresh` explicitly does not treat as
a reason to clear the session. The app therefore stays `signedIn`, and this
specific condition is already handled by the pre-existing connectivity-failure
fallback in `SongCatalogController._refreshCatalog` (cached organization id,
ADR-016), not by this spec's D2/D3 changes. The field failure this spec
addresses therefore requires the persisted session to be lost or rejected
outright — the most likely real trigger is the non-retryable refresh-failure
row above (rotated / already-used refresh token), because it also calls
`_removeSession()`, and `supabase_flutter` deletes the persisted session on a
`signedOut` event — making the broken state self-perpetuating across
subsequent launches, which matches the reported recurrence.

### F2 — the read path is gated on a live session, not on the local database

[`song_library_providers.dart:185`](../../apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart#L185)
returns songs only when `catalogSnapshotState.context != null`. That `context` is
set exclusively inside `SongCatalogController._refreshCatalog()`, which
[returns immediately when there is no live session](../../apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart#L130).
In the `sessionExpired` state the provider listener calls only
`handleSessionExpired()` ([`song_catalog_providers.dart:93`](../../apps/lyron_app/lib/src/application/song_catalog_providers.dart#L93));
`refreshCatalog()` is never invoked.

Consequence: **on a cold start in the offline-authenticated state, every song is
present in SQLite and the UI is empty.** This is data loss from the user's
perspective with no row deleted, it is independent of F1, and fixing F1 alone
does not address it.

This directly contradicts the deferred document's claim that "no read path and no
edit path in the app gates on live session validity."

### F3 — a successful-but-empty server response overwrites a good cache

[`song_catalog_controller.dart:286-300`](../../apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart#L286)
calls `replaceActiveSnapshot(...)` unconditionally after a successful
`listSongs()`, including when the result is empty. The store's write is correctly
transactional, so the swap is atomic — but an atomic swap to an empty catalog is
still an empty catalog. Any transient condition that makes RLS return zero rows
(a membership row briefly inactive, an organization change landing mid-flight)
legitimately empties the local cache.

Separately, [`_deleteUserSnapshots`](../../apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart#L1699)
deletes **all** of the user's snapshots across every organization, not just the
one being replaced, so refreshing one organization discards the others' caches.

### F4 — `verifiedEmpty` performs an immediate, irreversible total purge

A single empty result from `current_organization_ids()` reaches
[`planning_providers.dart:56`](../../apps/lyron_app/lib/src/application/planning_providers.dart#L56)
`handleVerifiedEmptyMembership`, which deletes the song catalog, the planning
data, and the identity record in one step with no confirmation and no recovery.

The RPC's grants are sound — `execute` is revoked from `public`/`anon` and
granted only to `authenticated` (`supabase/migrations/202605160007_auth_boundary_hardening.sql`),
so an expired JWT produces a `403`, not an empty list. The exposure is therefore
narrow. But the blast radius is total and unrecoverable, and the operation is
predicated on one unverified response.

### F5 — eviction is triggered by any failure and is unscoped when it runs

[`local_storage_write_recovery.dart:48`](../../apps/lyron_app/lib/src/application/storage/local_storage_write_recovery.dart#L48)
treats **any** non-`Error` `Exception` from a guarded write as storage pressure.
A transient `SQLITE_BUSY` qualifies.

When it fires, [`song_catalog_evictor.dart:45`](../../apps/lyron_app/lib/src/application/storage/song_catalog_evictor.dart#L45)
issues `DELETE FROM cached_catalog_sources` with no user filter, no organization
filter, no ordering, and no size target — deleting every song's content for every
user on the device. Offline, the titles remain and the songs become unreadable.
This matches the reported "sometimes in a shorter window" variant.

ADR-028 scoped eviction to "the one thing that can be given up under storage
pressure," which is correct as policy; the defect is that the trigger does not
establish storage pressure and the deletion is not proportionate to it.

### F6 — Android auto-backup is unconfigured

`apps/lyron_app/android/app/src/main/AndroidManifest.xml` sets neither
`android:allowBackup="false"` nor data-extraction rules, so a cloud restore or
device-to-device transfer can reinstate SharedPreferences (the Supabase session)
and the SQLite files inconsistently.

## Decisions

### D1 — Four purge reasons, and nothing else

Local user data may be destroyed for exactly these reasons:

| `PurgeReason` | Trigger | Confirmation |
| --- | --- | --- |
| `userSignOut` | The user activated the sign-out control | none |
| `accountDeleted` | The user deleted their account | none |
| `differentUserSignIn` | A different `userId` signs in on this device | dialog when pending work exists (existing behaviour) |
| `membershipRevokedConfirmed` | Two consecutive fresh, online, authenticated empty-membership resolutions | no pending work, or the user confirmed |

Everything else is forbidden. In particular — restating the paths that exist
today, so a future reader can tell intent from accident:

- any `null`-session event from the auth stream, for any reason, including
  `initialSession`, `signedOut`, a corrupt persisted session, and an expired or
  already-used refresh token
- Supabase token expiry in any form; it maps to `sessionExpired`, never
  `signedOut`
- a successful but empty `listSongs()` response
- a **single** `verifiedEmpty` membership resolution
- any exception raised by a guarded local write
- any phase of cold start

**Storage eviction is not a purge reason.** It is a separate mechanism with its
own trigger and its own proportionality rule (D6), and it may never remove
anything a purge reason would not.

Confirmed with the product owner 2026-08-19: explicit sign-out **keeps** its
destructive behaviour, and there is no multi-account use of a single device, so
`differentUserSignIn` remains a real but rare path and the existing `user_id`
partitioning is sufficient without further work.

### D2 — `signedOut` requires an explicit act; everything else is `sessionExpired`

`_stateForSession` drops its `_state.status == AppAuthStatus.signedIn` condition.
The replacement rule, stated positively:

> A `null` session maps to `signedOut` **only** when the app itself initiated the
> sign-out (`_isSigningOut`), or when no `LastKnownIdentity` exists — i.e. there
> is no user whose data could be protected. In every other case it maps to
> `sessionExpired`.

This requires `LastKnownIdentity` to be readable **synchronously** at the moment
a stream event is handled. The identity is therefore loaded into memory during
controller construction, before the stream subscription goes live; events
arriving before the load completes are buffered rather than evaluated against an
unknown identity. `restoreSession()`'s generation guard is additionally
constrained so that a stream event can never replace a restored state with a
*more* destructive one.

The user-visible consequence is intentional and should be stated in release
notes: when the refresh token genuinely expires, the user is no longer bounced to
the sign-in screen. They stay offline-authenticated, keep reading and editing,
and sync resumes after they re-authenticate from the re-auth banner. This is
ADR-020's stated intent; only now is it actually reachable.

This also closes `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md` as a data-
durability concern: the refresh-token TTL bounds *sync*, never *local data*.
Confirmed with the product owner: the configured TTL is unknown and does not need
to be known.

### D3 — Reads are served from the local database, not from a live session

`SongCatalogController` gains an offline-authenticated entry path: in
`sessionExpired`, it establishes `context` from `LastKnownIdentity`'s `userId`
and `organizationId` whenever a local snapshot exists for that pair — with no
network call and no session check. The planning side mirrors it.

This is deliberately redundant with D2: even if a purge path were ever
reintroduced, or a device arrives in a state this spec did not anticipate, the
read path itself no longer depends on anything that can expire.

### D4 — Snapshot replacement is conditional and organization-scoped

- An empty incoming snapshot **must not** replace a non-empty stored one. The
  refresh reports `failed` with a distinct "implausible empty response" status
  and writes an audit record. Emptiness is accepted only when a second,
  independent resolution also reports empty.
- `_deleteUserSnapshots` narrows from `(userId)` to `(userId, organizationId)`.
- Replacement adopts an explicit blue/green shape: rows are written under
  `snapshotVersion + 1`, reads follow an active-version pointer, and the previous
  version is deleted only after the pointer moves. On native SQLite the existing
  transaction already provides this guarantee; making it explicit is what carries
  it to IndexedDB on web, where the transactional guarantee does not hold.

Confirmed with the product owner 2026-08-19: it is acceptable for a genuinely
deleted song to remain visible locally until the second confirmation arrives.

### D5 — `verifiedEmpty` is confirmed twice before it purges, and never quarantines

An empty membership resolution is the server's claim that the signed-in user
belongs to no organization. Acting on one such claim is F4. D5 makes the purge
require two of them, separated in time, and nothing else.

#### D5.0 — The read-only quarantine is dropped

An earlier revision of this decision also placed the device in a read-only
quarantine between the two confirmations: reads allowed, local edits blocked, a
banner explaining why. **That is dropped, permanently.**

Backend RLS is already what stops a revoked member from writing: the `songs`
policies require `has_capability(organization_id, 'canEditSongs')`, which
requires an active membership row, so a revoked member's queued mutation is
rejected server-side regardless of what the client permits. Authorization lives
in the backend (AGENTS.md rule 5). The quarantine therefore never protected the
data; it only prevented a revoked member from making local edits that could
never have synced.

Against that narrow benefit stands a concrete harm. A *false* quarantine entry —
one transient empty resolution, or two independent listeners racing on a single
sign-in edge — locks a member in good standing out of editing, and clearing it
requires a second *online* resolution the device may be unable to obtain. On a
stage or rehearsal device, the exact device this whole contract exists to
protect, that lockout is a worse outcome than the edits it would have prevented.

Consequently, D5 introduces **no** read-only mode, **no** banner, and **no**
`MembershipQuarantinedException`. Reading and editing are unchanged in every
state this decision can reach; ADR-020's offline-authenticated read *and* edit
access is untouched. The only user-visible artefact D5 may produce is the
confirmation dialog in D5.4, and only immediately before a purge.

#### D5.1 — The marker

A nullable `membershipRevokedAt` timestamp is persisted on the single
`LastKnownIdentity` row. It is a counter with two states — absent (no empty
resolution outstanding) and present (exactly one empty resolution outstanding) —
and nothing else in the app reads it. It survives process restarts, which is
required: the second confirmation legitimately arrives on a later cold start.

This deliberately generalises Phase 3's `pendingEmptyConfirmationAt` mechanism
(D4) rather than inventing a second shape. What is reused is the property that
made Phase 3's version correct: **the marker is read and set in one atomic store
operation that returns the decision**, never as a read in application code
followed by a later write. What cannot be reused is the storage location —
Phase 3's marker lives on a `(userId, organizationId)` snapshot row, and an
empty *membership* resolution has no organization to key by and must be
recordable on a device that holds no snapshot at all.

#### D5.2 — Which resolutions count

A resolution counts toward the gate only when it is **fresh, online and
authenticated**: a live `current_organization_ids()` round trip made under a
valid session on this launch, returning `ActiveOrganizationVerifiedEmpty`.

Explicitly never counted, and never permitted to write the marker:

- `ActiveOrganizationUnknownConnectivityFailure`
- `ActiveOrganizationUnknownNonConnectivityFailure`
- a resolution that threw and was caught (the `null` case)
- any cached or fallback organization resolution (ADR-016)
- any offline-authenticated (`sessionExpired`) path
- any expired-session or re-auth path

A fresh, online, authenticated `ActiveOrganizationSelected` — a genuinely
non-empty resolution — **clears** the marker, with an audit record. No other
event clears it. In particular, a connectivity failure neither sets nor clears
it; it leaves the marker exactly as it found it.

**Both edges are audited.** Setting the marker writes a `local_data_events`
record, exactly as clearing it does. That record is the diagnostic showing that
a purge nearly happened, and it is the first thing anyone will look for if a
data-loss report arrives; without it, the only trace of a device that reached
one confirmation and then recovered is the absence of a purge row, which proves
nothing. Neither edge is a purge, so neither carries a `PurgeReason`; both use
their own audit `kind`, alongside D4's `empty-snapshot-rejected` precedent.

#### D5.3 — Separation between the two confirmations

The two confirmations must be genuinely independent observations, not one
observation seen twice. Two independent listeners already react to a single
sign-in edge, and each can issue its own RPC; two empty answers to those two
calls are two server round trips but only one underlying event, and treating
them as two confirmations would reduce the gate to a single confirmation in
ordinary operation.

The second confirmation therefore counts only if it arrives at least
**`membershipConfirmationCooldown` = 60 seconds** after the marker was set,
where "60 seconds" is measured on a **monotonic** clock, not on wall-clock time.

- **Within one process**, the gap is measured with a `Stopwatch` started when the
  marker was set, injectable so it is deterministically testable. A device clock
  adjustment cannot shorten it.
- **Across a process restart**, no cooldown check applies at all: two resolutions
  from two separate launches, under two separate auth cycles, are independent
  events by construction. The persisted `membershipRevokedAt` records *that* the
  marker is set and *when* — it is a timestamp for the audit trail and for a
  human reading the row, never an operand in a duration comparison.

This repository already treats the device clock as unanchored — it is why
`localRevision` exists instead of an `updatedAt` comparison (ADR-030, LF-T6).
An NTP correction at boot can jump the wall clock forward past 60 seconds, and
that error falls in the unsafe direction: the cooldown would appear elapsed when
no time has passed. A monotonic source cannot fail that way.

An empty resolution arriving inside the cooldown is a no-op: it does not purge,
and it does not move the marker.

Delay costs nothing here — during the cooldown the data stays fully readable and
editable, and the revoked member's writes are already rejected by RLS — while
the alternative failure mode is a total, unrecoverable local purge.

#### D5.4 — The purge and its confirmation

On a second counted confirmation, the purge (`membershipRevokedConfirmed`) runs
only when there is **no pending local work**, or the user **explicitly
confirmed** the loss.

- Pending work count is read at decision time. Zero → purge without a dialog.
- Nonzero, or unknown because the count could not be read → the user is asked,
  through ADR-029's existing `ReauthPromptController`/`ReauthPromptHost`. No
  second dialog owner is introduced. Unknown is treated as nonzero, never as
  zero (matching ADR-029's existing rule).
- The dialog names what is lost, including the pending count.
- Cancelled or dismissed → nothing is deleted, the marker stays set, an audit
  record is written. A later counted confirmation may ask again.

The purge deletes the song catalog, the planning data, and the identity row for
that `userId`, each through `LocalDataLifecycle` with
`PurgeReason.membershipRevokedConfirmed`, each with its audit record.

#### D5.5 — Concurrency model (normative)

The gate's correctness is a concurrency property, so the model is part of the
decision rather than an implementation detail.

1. **One global serialization chain.** `LastKnownIdentity` is a single global row
   (`rowId = 1`) and D1 excludes multi-account use of a device. Every identity
   and marker mutation, for every user, is serialized on one FIFO chain. Keying
   the chain by `userId` is forbidden: two users' writes would target the same
   row under different keys and serialize nothing.
2. **No user interaction inside the chain.** The confirmation dialog is awaited
   strictly outside it. The chain is entered once to read the decision inputs
   and exited; it is re-entered to apply the decision.
3. **Premises are re-validated on re-entry.** The world may have changed while
   the dialog was open. On re-entry the purge proceeds only if the identity row
   still exists, still belongs to the acting `userId`, still carries the *same*
   `membershipRevokedAt` value the decision was made against, and the pending
   work count is still no greater than the count the user confirmed. Any
   mismatch aborts the purge without deleting anything — a concurrent
   non-empty resolution must be able to cancel a pending purge.
4. **No value read before an await is written after it.** Any state captured
   before an await is re-read or re-validated before it is used to write.
5. **No caller may act on another user's row.** Every marker and identity
   mutation verifies the stored row belongs to the calling `userId` before
   acting, and is a no-op otherwise. A caller may never create an identity row
   for a user that does not own the stored one.
6. **No unbounded wait inside the chain.** Only local store operations run
   under it.

#### D5.6 — A permanently unauthorized queued mutation stops and says so

A mutation queued before authorization was revoked can never sync: the backend
rejects it permanently, not transiently. Any queued mutation that receives a
permanent authorization rejection must stop being retried and must be surfaced
to the user; it must never retry indefinitely and must never fail silently.

**Permanent and transient authorization failures must be told apart here**, even
though elsewhere in the app they are deliberately not:

| Response | Meaning | In the mutation queue |
| --- | --- | --- |
| `403`, PostgreSQL `42501`, or a `permission denied` message | The server knows who you are and you lack the right | Permanent. Terminal, `authorizationDenied`, no further retry, surfaced. |
| `401` | The token is missing, malformed, or expired | **Not** permanent. Re-authentication can make the same mutation succeed. Stays retryable. |

`SongCatalogController._isAuthorizationFailure`
(`song_catalog_controller.dart`) collapses `401`, `403`, `42501` and
`permission denied` into one branch. That is correct *there*, because the
decision it feeds is the same either way — fall back to the cached organization
id. It is not correct in the mutation queue, where treating a `401` as terminal
would discard the user's queued work on an ordinary token expiry.

The `permission denied` message pattern is matched alongside the codes, because
PostgREST does not always return a structured PostgreSQL error code.

This is deliberately general — it is scoped to any permanent authorization
rejection a queued mutation can receive, not to membership revocation — and it
is what makes dropping the quarantine (D5.0) safe from the user's point of view:
the edits a revoked member makes are not silently lost, they are reported.

### D6 — Eviction is triggered by storage pressure and is proportionate to it

- **Trigger:** a concrete storage-exhaustion signal (`SQLITE_FULL`, `disk I/O
  error`, web `QuotaExceededError`) **or** a measured footprint above the budget.
  Any other exception surfaces as `LocalStorageWriteFailure` with an audit record
  and evicts nothing.
- **Budget:** 2 GB, set with the product owner 2026-08-19 on the understanding
  that real catalogs are orders of magnitude smaller. The budget exists to make
  the mechanism inert in practice while keeping a defined ceiling.
- **Proportionality:** evict in least-recently-read order, only until the target
  is met, and touch the active `(userId, organizationId)` last.
- **Recoverability:** the affected snapshot is marked `sourcesEvicted` so the next
  successful online refresh restores what was dropped.

### D7 — One gate, one audit trail

`deleteCatalogsForUser`, `deletePlanningDataForUser`, and
`LastKnownIdentityStore.clear()` become reachable only through a single
`LocalDataLifecycle` seam that requires a `PurgeReason`. An architecture test
enforces that no other call site exists. Every purge and every eviction writes a
`local_data_events` record (timestamp, reason, `userId`, affected row counts),
surfaced on a diagnostics screen.

This is the decision that makes the contract durable rather than merely correct
today: the compiler and one test, not reviewer memory, keep a future feature from
opening a fifth path.

### D8 — Android backup is deterministic

Set `android:allowBackup="false"`, or supply data-extraction rules that keep the
session store and the SQLite databases in the same backup set. A half-restored
device must not be representable.

## Non-Goals

- **Web durability guarantees.** D2, D3 and D4's conditional-swap rule apply on
  web because they are platform-independent logic, but IndexedDB durability,
  eviction under browser storage pressure, and the blue/green pointer's behaviour
  there remain best-effort. No acceptance test asserts a web offline horizon.
- **Changing the refresh-token TTL** or any hosted Supabase Auth setting. D2
  makes it irrelevant to data durability.
- **Reworking `SongCatalogController`'s refresh state machine.** Only its
  entry conditions and its snapshot-write decision change.
- **Introducing multi-account support.** Confirmed out of scope.
- **Server-side soft delete or undo.** D5's confirmation gate is local
  only, and it defers a purge rather than making one reversible.

## Acceptance

1. Cold start, offline, expired access token, valid refresh token → songs
   visible, zero deletions.
2. Cold start, offline, gotrue emits `signedOut` → zero deletions,
   `sessionExpired`, songs visible.
3. Persisted session removed from SharedPreferences while `LastKnownIdentity`
   survives → zero deletions, songs visible.
4. `listSongs()` returns empty with HTTP 200 → cache untouched, refresh reports
   the implausible-empty status.
5. `verifiedEmpty` once → no deletion, marker recorded, reading and editing
   unchanged. A second counted `verifiedEmpty` after the cooldown, with no
   pending work → purge executes with a `membershipRevokedConfirmed` audit row.
   With pending work → the purge waits for the user's confirmation.
6. A guarded write throws `SqliteException(BUSY)` → no eviction.
7. Simulated multi-day offline span with an advanced clock → songs remain
   visible on every cold start.
8. Architecture test: `LocalDataLifecycle` is the sole caller of every purge
   primitive.
