# ADR-035: Local Data Purge Contract

- Status: Accepted
- Date: 2026-08-21
- Spec: `docs/specs/2026-08-19-local-data-durability-contract.md`
- Plan: `docs/plans/2026-08-19-local-data-durability-contract.md`
- Relates to: ADR-020 (non-destructive session and offline-authenticated
  state), ADR-008 (local-first), ADR-016 (active-organization-resolution
  semantics), ADR-028 (local storage budget and eviction policy)
- Scope: `AppAuthController` (`_stateForSession`), `SongCatalogController`,
  `PlanningSyncController`, `LocalDataLifecycle`
  (`apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart`),
  the `local_data_events` audit store
  (`apps/lyron_app/lib/src/offline/local_data_events/`), and — for the
  decisions this ADR records but Phases 3–4 have not yet built — the
  snapshot-write path and membership-revocation quarantine.

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
sign-out, different-user sign-in, verified-empty membership); Phase 1 closes
the paths that were violating it by accident. (Account deletion is listed in
D1 as its own reason, but Phase 2 found it is not yet its own *code path* —
see the Phase 2 section below.)

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

### Implemented in Phase 2 (this slice)

**D7 — one gate, one audit trail.** `LocalDataLifecycle`
(`apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart`) is
now the sole caller of the three purge primitives
(`SongCatalogStore.deleteCatalogsForUser`,
`PlanningLocalStore.deletePlanningDataForUser`,
`LastKnownIdentityStore.clear()`), plus `LastKnownIdentityStore.write()` (not
itself destructive, but paired with the same in-memory-cache-sync obligation
— see below). It exposes four methods: `purgeSongCatalog`, `purgePlanningData`,
and `clearIdentity` each require a `PurgeReason`; `writeIdentity` does not
(writing a new identity is not destructive, so D7's "no purge without naming
a reason" rule does not apply to it). Every one of the six call sites
identified during Phase 1 closeout (five in `auth_providers.dart`, one in
`planning_providers.dart` — see the corrected Task 1.1 bullet in the plan)
now goes through one of these four methods; the durable identity mutation and
the in-memory `AppAuthController` cache sync (`noteLastKnownIdentity`) are a
single indivisible operation inside the gate instead of two call sites that
proved, in Phase 1, they can drift apart.

`apps/lyron_app/test/architecture/local_data_lifecycle_gate_test.dart`
enforces sole-caller-ship by source-scanning `lib/` for the four call
patterns, allow-listing only the gate itself and each primitive's own
definition site. It was verified to actually fail (a temporary violating call
outside the allow-list was introduced, observed red, then reverted) — this is
Acceptance 8. The scan is plain-text/regex, not AST-based: `.clear()`/`.write()`
are common method names on unrelated types, so those two patterns are scoped
to lines whose receiver expression textually contains "identityStore". This
has a known, accepted gap — a future call site that assigns the identity
store to a differently-named local variable on one line and calls
`.clear()`/`.write()` on a later line would not be caught (the two
delete-primitive patterns don't share this weakness; their method names are
globally unique in this codebase). Tightening this to a real AST check is a
reasonable follow-up if a violation ever needs the scan strengthened, not a
blocker for this phase.

**Audit store: a dedicated database, not a table in an existing one.** The
`local_data_events` table (`apps/lyron_app/lib/src/offline/local_data_events/`)
lives in its own Drift database (`lyron_local_data_events.sqlite`),
structurally separate from the song-catalog, planning, and
last-known-identity databases. The constraint driving this: a purge audit
record must outlive the data it describes, so it cannot live anywhere a
purge reason deletes from. A dedicated database makes this true by
construction — no purge primitive's delete statement can reach a table in a
different database file, today or after any future change to those
primitives — rather than true only because nothing currently happens to
delete from that table. Every purge and (once Phase 3 wires a caller)
eviction writes one row: timestamp, `kind` ('purge'/'eviction'), `target`,
`reason` (nullable — always populated for a purge, always null for an
eviction, since no `PurgeReason` applies to eviction), `userId` (nullable),
`rowsAffected` (nullable).

`rowsAffected` is nullable and is `null` on every row Phase 2 writes. The
three purge primitives (`deleteCatalogsForUser`, `deletePlanningDataForUser`)
return `Future<void>`, not a row count, even though their Drift
implementations compute one internally for the storage-footprint callback.
Changing that return type to surface the count would touch
`SongCatalogStore`/`PlanningLocalStore`'s public interface, which test
doubles in this codebase implement directly
(`_FailingDeleteSongCatalogStore`, `_BlockingPlanningLocalStore`, and
others) — a signature change would force edits to those test files just to
keep them compiling, which this phase's own guardrail treats as a behaviour
change ("every existing test must pass without modification"). The schema
carries the column so a later phase can populate it without a migration;
Phase 2 accepts "unknown" over touching primitive signatures for an
audit-only improvement.

**A known gap surfaced, not fixed, by this phase: `accountDeleted` and
`userSignOut` are indistinguishable in code today.**
`AppAuthController.deleteAccount()` sets the same `_isSigningOut` flag and
converges to the identical `AppAuthState(status: signedOut)` as
`signOut()` — nothing downstream of `AppAuthState` (including every call
site this phase moved behind the gate) can tell them apart. Every call site
that could plausibly be either reason currently passes
`PurgeReason.userSignOut`. `PurgeReason.accountDeleted` is fully defined per
D1 and ready to receive real call sites the moment `AppAuthState` grows a
discriminator; adding that discriminator is out of this phase's scope (it
touches auth-state shape, not purge routing) and is left for whichever future
work next touches `deleteAccount()`. This conflation now persists into every
`local_data_events` row written for either trigger, unversioned — PR #74's
review flagged that once the discriminator lands, historical rows will not
be retroactively distinguishable. That is the correct, honest state for
this phase to leave the audit trail in: it should record what the code
actually knew at the time, not a reason it could not tell.

**One reason-mapping judgment call:** the `ActiveOrganizationVerifiedEmpty`
branch inside `auth_providers.dart`'s sign-in resolution (`persistNewIdentity`)
clears the identity on a single fresh empty-membership resolution — the same
`current_organization_ids()` signal D5/Phase 4's "two consecutive
confirmations, then quarantine" design governs, reached here by a second,
independent code path the spec's F4 section did not name. This phase does not
change when that clear fires (no behaviour change); it labels it
`PurgeReason.membershipRevokedConfirmed` as the closest fit of the four
documented reasons, while it stays true that D5's confirmation requirement is
not yet enforced on this path — Phase 4 is expected to reconcile this branch
with the coordinator-based `VerifiedEmptyMembershipCleanupCoordinator` path
(`planning_providers.dart`), which is the certain, unambiguous
`membershipRevokedConfirmed` handler.

**A real regression the gate introduced, found and fixed before merge.** A
whole-branch review found that `purgeSongCatalog`/`purgePlanningData`/
`clearIdentity` awaited the audit-record write with no try/catch AFTER the
destructive part had already committed: an audit-write failure made the
whole method throw even though the deletion/clear genuinely succeeded. For
`clearIdentity` specifically, this could invert
`wipePriorAndProceedFor`'s documented failure-handling invariant — its catch
block assumes an exception means the clear did not land, and falls back to
treating the device as still signed in as the prior user; an audit-write
failure could trigger that fallback after the clear had already happened,
asserting an offline-authenticated identity for a user whose local trace was
already gone. Fixed (`5ba06be`) with a shared best-effort helper: the audit
write is still attempted, but a failure in it is reported
(`FlutterError.reportError`) and never rethrown, so a purge/clear that
committed can never be misreported as failed by the logging that describes
it afterwards. The same review found `clearIdentity`'s original design (an
internal identity-store `read()` before the `clear()`, added solely to
attribute a `userId` on the audit row) introduced its own new failure mode
and widened a race window; fixed by taking an optional `userId` parameter
from the caller instead, populated at the three call sites that have one in
scope.

**A second review (PR #74) found the audit write still lengthened the
critical path, even after it was made best-effort.** `_recordBestEffort` was
still `await`ed before `purgeSongCatalog`/`purgePlanningData`/`clearIdentity`
returned, so `wipePriorAndProceedFor`'s `Future.wait([songDeletion,
planningDeletion])` resolved only once both deletions AND both (already
non-throwing) audit writes had completed — measurably later than the
pre-gate code, which returned as soon as the two raw store deletes finished.
Fixed by dispatching the audit write with `unawaited` instead: the
destructive method's own `Future` now resolves exactly when the
deletion/clear does, matching the pre-gate timing, and the audit write
proceeds in the background on its own already-non-throwing path. (Technical
note for the record: even before this fix, the widened window did not
change any *outcome* — `wipePriorAndProceedFor`'s own comments already
document the exact scenario a wider window makes marginally more likely
[a superseded resolution after the deletions but before the identity clear]
as intentionally safe and self-healing. The `unawaited` fix was made anyway
because it fully closes the gap at negligible cost, rather than resting the
"no behaviour change" claim on that argument.)

The same review found the `readRecent` query sorting on `occurredAt` (not
indexed, and `local_data_events` is deliberately unbounded) forced a
full-table scan and sort on every diagnostics-screen open. Fixed by sorting
on the autoincrement primary key alone (`id DESC`) — strictly monotonic with
insertion order, no precision loss, and satisfiable from the primary-key
index. And the diagnostics screen's error state now reuses the existing
`RetryableErrorState` widget (`presentation/planning/widgets/`) instead of a
bare, unactionable `Text`, matching `plan_list_screen.dart`/
`plan_detail_screen.dart`'s convention.

**Two suggestions from the same review were evaluated and declined:**
merging `purgeSongCatalog`/`purgePlanningData` behind a shared higher-order
helper (the two methods' bodies are nearly identical, but their arities
differ — `shouldContinue` is planning-only — and two short, explicit methods
read more clearly than a parameterized-delete abstraction built for exactly
two callers); and dropping the `local_data_events.kind` column in favour of
inferring purge-vs-eviction from `reason`-nullness at read time (this is the
inverse of a fix already made earlier in this same PR, commit `51c4955`,
after an *earlier* review flagged that exact inference as coincidental
rather than structural — reversing it now would reintroduce the same
fragility one layer down, in the schema instead of the UI).

**Residual, deliberately-deferred hardening**, not required for this phase's
no-behaviour-change bar but worth tracking for whenever the audit trail's
own robustness next gets attention:

- The audit database currently opens lazily on the first purge, inside the
  destructive path. Opening it eagerly at app startup would mean a purge is
  never the first thing to hit a cold-open failure on that file.
- `local_data_events` has no retention or trim policy — it is unbounded
  append-only growth. Not a durability risk (that is the point of the
  table), but a storage-footprint one over a long device lifetime.
- The architecture test's `.clear()`/`.write()` patterns (see above) are
  scoped to same-line receiver-name matching and would not catch a call
  split across a `dart format`-introduced line break on a differently-named
  local variable. Still an accepted gap, now with a concrete repro shape on
  record.

### Decided, not yet implemented (Phases 3–4)

The remaining four decisions are settled — confirmed with the product owner
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
- **D8 — Android backup is deterministic** (Phase 4). Set
  `android:allowBackup="false"`, or supply data-extraction rules that keep the
  session store and the SQLite databases in the same backup set, so a
  half-restored device cannot be representable.

Do not read D4–D6/D8 as implemented from this ADR's existence. They are
recorded here, ahead of their landing, so the full contract has one durable
home; each lands with its own commits and its own review in Phases 3–4.

## Phase 3 mechanism decisions

The plan (`docs/plans/2026-08-19-local-data-durability-contract.md`, Phase 3)
left three mechanisms open rather than specifying them. Two are resolved here,
ahead of implementation; the third (LRU ordering, Task 3.4) was put to the
product owner directly rather than decided unilaterally, because it trades a
real write-path cost against a budget the spec itself describes as designed
to stay unreached in practice — see the plan and this ADR's next revision for
the answer once given.

**Task 3.1 — the "one empty resolution already seen" fact is persisted on the
snapshot row, not held in memory.** `CachedCatalogSnapshots` gains a nullable
`pendingEmptyConfirmationAt` column (Drift schema bump, `onUpgrade` delta from
v3, `onCreate` unaffected). `_replaceActiveSnapshot` checks it before deciding
whether an empty `listSongs()` result is implausible:

- incoming empty, stored non-empty, marker unset → reject the replacement,
  write `local_data_events` with the implausible-empty status, and set the
  marker on the existing row via a lightweight update (no full snapshot
  rewrite).
- incoming empty, stored non-empty, marker set → this is the second,
  independent confirmation. Proceed with the normal full replace (empty
  summaries/sources), which writes a fresh row with the marker defaulted to
  null.
- incoming non-empty, at any marker state → proceed with the normal full
  replace, which likewise writes a fresh row with the marker null.

An in-memory-only flag was rejected: it resets on process restart, and a
genuinely emptied catalog reached only across cold starts (the exact usage
pattern this whole contract is written for) could then never accumulate two
confirmations — the rejection would repeat forever. Persisting on the
snapshot row fixes the clearing rule for free: the row is fully rewritten by
every accepted replace, whether that replace is the second confirmation or an
ordinary non-empty refresh, so there is no separate code path that clears the
marker — an unwritten field defaults to null. "Independent" falls out of the
existing generation/staleness guards in `_refreshCatalog`: each invocation
calls `listSongs()` at most once, so two hits against the marker are
necessarily two separate invocations, not a retry of the same one.

**Task 3.3 — blue/green is a documented invariant plus a rollback test, not
an active-version pointer.** `_replaceActiveSnapshot` already runs its delete
(`_deleteUserSnapshots`, narrowed to `(userId, organizationId)` by Task 3.2)
and its inserts inside one `_database.transaction()` block. On native
SQLite/Drift, that transaction is already atomic: a failure anywhere inside
it rolls back the whole thing, so the previous snapshot is either fully
present or fully replaced, never partial. Building an active-version pointer
(write under `snapshotVersion + 1`, gate every read on a pointer, delete the
old version only after the pointer moves) would require migrating all five
read methods in `song_catalog_store.dart`
(`readActiveSummaries`, `readActiveSummaryBySlug`, `readActiveSummaryById`,
`readActiveSource`, `readLatestCachedOrganizationId`) to filter on the
pointer instead of "current rows for this `(userId, organizationId)`" — a
real increase in surface area and an ongoing tax on every future read-path
change — to provide a guarantee the spec itself says is redundant on the one
platform this phase verifies (native), and explicitly Non-Goal/best-effort on
the one platform where it would matter (web/IndexedDB, no acceptance test).
Paying that cost for an unverifiable benefit is not justified by the plan's
own scope.

Decision: keep the existing single-transaction shape, document why it already
satisfies D4's atomicity requirement on native SQLite (code comment on
`_replaceActiveSnapshot`, plus this ADR entry), and add a fault-injection test
that interrupts the transaction between the delete and the inserts and
asserts the previous snapshot's rows are still fully present afterwards —
proving the rollback, not merely assuming Drift provides it. `snapshotVersion`
stays a written-but-unfiltered column, unchanged from its current status; it
is not repurposed into a pointer by this phase. If IndexedDB durability is
ever taken out of Non-Goals in a future spec, the pointer becomes the right
mechanism then — this decision is scoped to what Phase 3 actually needs to
close F3/F5, not a permanent rejection of the pointer design.

**Task 3.4 — eviction ordering is a cost-free proxy, not true LRU.** There is
no `lastReadAt` (or equivalent) column anywhere in the catalog schema today.
Building real least-recently-read tracking means writing to the database on
every song read — a permanent cost on the hottest path in the app — to serve
an evictor that the 2 GB budget (D6) is deliberately sized to make
near-dead code in practice. Put to the product owner directly (2026-08-22)
rather than decided unilaterally, given that trade-off: **chosen — a cheap
ordering proxy**, not real LRU and not the prior fully-arbitrary order.
`SongCatalogEvictor.evictDroppable()` orders its deletion candidates
non-active-`(userId, organizationId)`-first, then by oldest
`CachedCatalogSnapshots.refreshedAt`/`snapshotVersion` within that ordering,
stopping once the size target is met and always touching the active
`(userId, organizationId)` last (D6's proportionality rule). This uses only
columns that already exist and are already written on every refresh, so it
adds no new write path and no per-read cost, while still approximating D6's
"least-recently-read" intent — data belonging to organizations the device
isn't currently working in, and older refreshes within an organization, are
more likely to be genuinely cold than the active snapshot. Real LRU read
tracking remains available as a future upgrade if the proxy is ever shown to
evict something still in active use; nothing in this decision forecloses it.

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

As of Phase 2, the four purge reasons in D1 are a *structurally enforced*
contract, not merely a stated one: `LocalDataLifecycle` is the only path to
any purge primitive, and the architecture test fails the build if a new
direct call appears. Before Phase 2, the call sites that respected D1 did so
because Phase 1's fixes closed the paths that were violating it, not because
a gate forbade a new violation from being added — a reviewer reading an
earlier revision of this ADR would have seen that distinction; it no longer
applies.

## Non-Goals

Carried unchanged from the spec: no web durability guarantee (D2/D3/D4's
platform-independent logic runs on web, but IndexedDB durability and web
eviction remain best-effort with no acceptance test); no change to the
refresh-token TTL or any hosted Supabase Auth setting (D2 makes it irrelevant
to data durability, not to sync); no rework of
`SongCatalogController`'s refresh state machine beyond its entry conditions
and snapshot-write decision; no multi-account support; no server-side soft
delete or undo (quarantine, D5, is local only).
