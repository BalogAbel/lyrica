# Local Data Durability Contract — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** A downloaded song catalog survives on the device until one of four
enumerated purge reasons destroys it deliberately. No connectivity condition,
token lifetime, empty server response, or local write failure may remove or hide
it.

**Architecture:** Four phases, each a separate pull request, in dependency order.
Phase 1 stops the bleeding (the reported symptom) by making cold start
offline-authenticated end to end. Phase 2 makes the contract structural rather
than incidental, with no behaviour change. Phase 3 hardens the write path.
Phase 4 adds the one genuinely destructive path that remains, with its own
confirmation flow.

**Tech Stack:** Dart / Flutter, Riverpod 3, Drift, `flutter_test`.

**Spec:** `docs/specs/2026-08-19-local-data-durability-contract.md`

---

## Phase boundaries, and why they are not merged

- **Phase 1 and 2 stay apart.** Phase 2 rewrites every purge call site
  mechanically with no behaviour change. Folding the behaviour change of Phase 1
  into that diff would hide the part that most needs review inside the part that
  needs it least.
- **Phase 2 and 3 stay apart.** Phase 2 moves callers; Phase 3 changes what some
  of them do. Combined, a bad merge in the mechanical half would be invisible.
- **Phase 4 stays alone.** It is the only phase that adds a path which really
  deletes data, and its tests should be readable on their own.
- **Phase 1 is itself a merge** of what was initially scoped as two PRs (read path
  and auth state). Neither half delivers user value alone: fixing the read path
  does not help if the wipe already ran, and fixing the auth state leaves the UI
  empty. They also share one prerequisite — a synchronously readable
  `LastKnownIdentity` — which would otherwise be built twice.

## Non-Goals, restated because this plan invites them

- Do **not** change any hosted Supabase Auth setting, or attempt to extend the
  refresh-token TTL. D2 makes it irrelevant to durability.
- Do **not** add web durability guarantees or browser E2E infrastructure
  (`docs/deferred/2026-06-29-web-offline-e2e.md`).
- Do **not** refactor `SongCatalogController._refreshCatalog`'s state machine.
  Only its entry conditions and its snapshot-write decision change.
- Do **not** add multi-account support. Confirmed out of scope; the existing
  `user_id` partitioning is sufficient.
- Do **not** loosen an existing sign-out test to make a new path pass. If an
  offline-authenticated path can resurrect access after explicit sign-out, the
  design is wrong, not the test.

---

# Phase 1 — Offline-authenticated cold start (D2, D3)

**Branch:** `fix/offline-authenticated-cold-start`

Closes F1 and F2. On its own this phase resolves the reported symptom.

## Task 1.1 — Synchronously readable last-known identity

**Files:** `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`,
`apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

- [x] Write failing tests first:
  - A `null` session event arriving **before** the identity load completes is not
    evaluated against an unknown identity: it is buffered and resolved once the
    identity is known, yielding `sessionExpired` when an identity exists.
  - With the identity loaded and present, a `null` stream event from
    `initializing` yields `sessionExpired`, not `signedOut`.
- [x] Implement: load `LastKnownIdentity` into an in-memory field during
  construction, before the `watchSession()` subscription goes live. Buffer stream
  events until that load settles.
- [x] Keep the store as the durable source; the in-memory copy is a read cache.
  **Correction (Phase 2 closeout):** the "live-sync deferred to Phase 2"
  framing below was wrong — it was not deferrable. Post-Task-1.6 verification
  (commit 3231139) found an in-session token-expiry regression caused by
  exactly this gap: `LastKnownIdentity` is loaded once at construction but
  external writers (`auth_providers.dart`, `planning_providers.dart`) mutate
  the durable store later in the same process without updating the in-memory
  cache. Phase 1 closed it with `AppAuthController.noteLastKnownIdentity(...)`,
  called from every identity-store write/clear site (six call sites: five in
  `auth_providers.dart`, one in `planning_providers.dart`). Phase 2 (Task 2.3)
  absorbs those six call sites behind the `LocalDataLifecycle` gate as part of
  routing every purge primitive through one seam — the gate now owns "mutate
  the durable identity" and "sync the in-memory cache" as one indivisible
  operation instead of two call sites that can drift apart.

## Task 1.2 — `signedOut` requires an explicit act (D2)

**Files:** `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`,
`apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

- [x] Write failing tests first, one per row of the D1 forbidden list that
  reaches this function:
  - `null` session from `initializing` + identity present → `sessionExpired`
  - `null` session from `sessionExpired` + identity present → stays
    `sessionExpired`
  - `null` session + **no** identity → `signedOut` (nothing to protect)
  - `signOut()` in progress (`_isSigningOut`) → `signedOut`
  - a `null` event during `restoreSession()`'s await cannot replace the restored
    state with a more destructive one
- [x] Implement: remove the `_state.status == AppAuthStatus.signedIn` condition
  from `_stateForSession`. New rule: `signedOut` iff `_isSigningOut` **or** no
  `LastKnownIdentity`; otherwise `sessionExpired`.
- [x] Constrain the `_authGeneration` guard in `restoreSession()` so a stream
  event may not downgrade a restored `sessionExpired` to `signedOut`. (Verified
  unnecessary: fixing `_stateForSession`'s predicate collapsed the race —
  existing generation sequencing already handles ordering. No extra guard
  added; see commit 412ec88.)
- [x] Existing explicit-sign-out tests must stay green **without modification**.
  If they cannot, STOP and report. (Verified byte-identical by two independent
  reviews.)
- [x] `flutter test test/application/auth/` green. (85/85.)

## Task 1.3 — Catalog context from local data alone (D3)

**Files:** `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`,
`apps/lyron_app/lib/src/application/song_catalog_providers.dart`,
`apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`

- [x] Write a failing test: a controller in `sessionExpired`, with a stored
  snapshot for `LastKnownIdentity`'s `(userId, organizationId)` and a remote
  repository that throws on every call, exposes a non-null `context` and the
  cached summaries.
- [x] Implement `handleOfflineAuthenticated()`: establish `context` from
  `LastKnownIdentity` when a local snapshot exists for that pair. No network
  call, no session check.
- [x] Wire it into the `sessionExpired` branch of `handleAuthStateChanged`
  alongside the existing `handleSessionExpired()`.
- [x] Verify `songLibraryListProvider` yields the cached songs in this state.
  (Verified transitively via the controller test — the provider's existing
  pass-through on `context` needed no code change.)

Commit 8d63824. Follow-up: this task's `flutter test test/application/`
sweep surfaced 2 pre-existing tests in `providers_test.dart` that broke as a
latent consequence of Task 1.2's D2 change (fixture gap: `AppAuthController`
built with no identity store, same category Task 1.2 already fixed
elsewhere but missed in this file). Fixed in commit fc52c70 — fixture-only,
no assertions changed. Full `test/application/` tree (369 tests) green.

## Task 1.4 — Planning mirror

**Files:** `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`,
`apps/lyron_app/lib/src/application/planning_providers.dart`, plus tests under
`apps/lyron_app/test/application/planning/`

- [x] Same shape as 1.3 for the planning projection: `sessionExpired` resolves a
  read context from `LastKnownIdentity` without network access. Commit
  a98b4e5. `PlanningSyncController.handleOfflineAuthenticated()` mirrors
  `SongCatalogController`'s; captures (does not advance) `_boundaryGeneration`
  to detect a concurrent `handleActiveContextChanged` establishing a real
  boundary while the local read is in flight. Reviewed clean.

## Task 1.5 — Cold-start integration test

**Files:** `apps/lyron_app/test/integration/`

- [x] Acceptance 1: offline cold start, expired access token, valid refresh token
  → songs visible, zero deletions. **Correction (commit e8636b1):** verified
  against the pinned `gotrue`/`supabase_flutter` source that this exact
  condition never produces a null session — `currentSession` stays non-null,
  the app stays `signedIn`, and the pre-existing `_refreshCatalog`
  connectivity-failure fallback (ADR-016) is what actually protects this
  case, not Tasks 1.1-1.4's new machinery. The test is now a regression
  guard for that pre-existing path, not evidence of new-code correctness.
  See the added note in the spec's F1 section.
- [x] Acceptance 2: offline cold start, auth stream emits `signedOut` → zero
  deletions, `sessionExpired`, songs visible.
- [x] Acceptance 3: persisted session removed while `LastKnownIdentity` survives
  → zero deletions, songs visible.
- [x] Acceptance 7: advanced-clock multi-day offline span → songs visible on
  every cold start. (No wall-clock check exists anywhere in the read path
  post-D2, so proven instead via 3 full relaunch cycles against the same
  persisted stores.)

Commits 9738dd8, e8636b1. Two review rounds: first found the zero-deletions
decorator undercounted delete-shaped methods (fixed) and questioned
Acceptance-1's premise (led to the correction above); second round clean.

## Task 1.6 — Documentation

- [x] Write `docs/architecture/decisions/ADR-035-local-data-purge-contract.md`
  carrying D1–D8. Mark it as enforcing ADR-020 rather than superseding it.
- [x] Correct `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`: its claims
  that `_stateForSession` never maps to data loss and that no read path gates on
  session validity were false. Record what was actually true, and close it as a
  durability concern (it remains a sync-resumption note only).
- [x] Update `docs/architecture/architecture.md` with the purge-contract seam.
- [x] Add a release note: expired refresh tokens no longer bounce the user to
  sign-in; they stay offline-authenticated and sync resumes after re-auth.

Commit fc09bfb. Reviewed clean — no overclaiming of Phase 2-4 work, citations
verified against ADR-016/ADR-020 source, LF-T2 correction preserves the
original conclusion.

**Phase 1 complete: Tasks 1.1-1.6 all done, reviewed, committed.**

### Post-Task-1.6 verification found a real regression, now fixed

Running the FULL `flutter test` (not just `test/application/`, which every
task's own verification had been scoped to) surfaced one genuine regression
in a pre-existing widget test outside that narrower scope, plus one related
gap a review then found on top of the fix:

- **Commit 3231139** — `test/integration/song_reader_flow_test.dart` (predates
  this branch, untouched by it) started failing: an in-session token-expiry
  event was misclassified as `signedOut` instead of `sessionExpired`, bouncing
  the user to sign-in. Root cause: `AppAuthController`'s in-memory
  `LastKnownIdentity` cache (Task 1.1) is loaded once at construction and was
  never updated when `auth_providers.dart`'s `lastKnownIdentityPersistenceProvider`
  writes the identity to the durable store from outside the controller, later
  in the same process — a within-session write/read race Task 1.1's own
  "deferred to Phase 2" framing had wrongly assumed was out of Phase 1's reach.
  Fixed by adding `AppAuthController.noteLastKnownIdentity(...)`, called from
  every identity-store write/clear site.
- **Commit df71d78** — review of 3231139 found a sixth, unpaired writer
  (`VerifiedEmptyMembershipCleanupCoordinator.handleVerifiedEmptyMembership`,
  planning_providers.dart) with the same staleness class in the opposite
  direction. Closed the same way.

Full `flutter test` (1384 passed, 18 skipped — pre-existing real-backend
integration tests needing a local Supabase stack, unrelated to this branch,
0 failed) and `flutter analyze` (clean) both verified green after both fixes.

**Lesson for later phases:** scope every task's own verification to
`flutter test` in full, not a narrower subdirectory — the acceptance-criteria
tests and the `test/application/` sweep both missed this because neither
exercises a real widget tree wired through the full provider graph the way
`test/integration/` does.

---

# Phase 2 — `LocalDataLifecycle` gate and audit trail (D7)

**Branch:** `refactor/local-data-lifecycle-gate`

No behaviour change. This is what keeps a fifth purge path from being added by
accident later.

## Task 2.1 — The gate

**Files:** new `apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart`,
new test alongside

- [x] Write failing tests first: each `PurgeReason` performs its documented set of
  deletions and writes exactly one audit record; a failure in one store's
  deletion is reported and does not silently claim success.
- [x] Implement `PurgeReason { userSignOut, accountDeleted, differentUserSignIn,
  membershipRevokedConfirmed }` and a `LocalDataLifecycle` that owns every purge.

Commit 8a1f5ed. Reviewed clean. `LocalDataLifecycle` depends on an abstract
`LocalDataEventsRecorder` (real Drift implementation is Task 2.2) via
constructor injection, so its own tests use a fake recorder. Also defines
`PurgeTarget` (which store an event targets) and a fourth, non-gated method
`writeIdentity` (writing a new identity is not destructive, so D7's
name-a-reason rule does not apply to it).

## Task 2.2 — Audit store

**Files:** `apps/lyron_app/lib/src/offline/` (new `local_data_events` table +
migration), tests under `apps/lyron_app/test/offline/`

- [x] Table: timestamp, reason, `userId`, affected row counts per store.
- [x] Drift schema bump with an explicit `onUpgrade` delta, matching the existing
  migration contract. **Note:** this is a brand-new database at schema
  version 1 with no prior version to upgrade from, so it follows
  `LastKnownIdentityDatabase`'s own v1 template (`onCreate` only) rather than
  literally including an `onUpgrade` delta — there is nothing yet for one to
  do. The migration *contract* (explicit `MigrationStrategy`, documented
  schema version) is matched; an actual delta lands whenever this schema
  first changes.
- [x] Eviction events are recorded here too, under a distinct non-purge kind.
  `DriftLocalDataEventsStore.recordEviction(...)` exists and is tested, but
  nothing calls it yet — no eviction call site exists until Phase 3.

Commit 4d20e4c. Reviewed clean. Lives in its own dedicated Drift database
(`lyron_local_data_events.sqlite`), not a table added to an existing one —
see ADR-035 for why. `rowsAffected` is written as `null` on every Phase 2
row; see ADR-035 for why (the three purge primitives don't expose counts,
and changing their return type would force edits to test doubles that
implement `SongCatalogStore`/`PlanningLocalStore` directly, which the
phase's no-behaviour-change guardrail forbids).

## Task 2.3 — Route every call site through the gate

**Files:** `song_catalog_controller.dart`, `planning_sync_controller.dart`,
`auth_providers.dart`, `planning_providers.dart`

- [x] Move all `deleteCatalogsForUser`, `deletePlanningDataForUser` and
  `LastKnownIdentityStore.clear()` calls behind `LocalDataLifecycle`.
  `LastKnownIdentityStore.write()` moved too (paired 1:1 with the in-memory
  cache sync `noteLastKnownIdentity` — see the corrected Task 1.1 bullet
  above).
- [x] Preserve the existing `differentUserSignIn` semantics exactly, including
  the ordering and failure handling documented in `auth_providers.dart` — that
  code encodes prior review findings and must not be simplified here.
  Verified line-by-line by two independent review passes (a per-task review
  and, at the end of this phase, a dedicated whole-branch behaviour-diff
  review) that `wipePriorAndProceedFor` changed only its three primitive
  calls to gate calls — same `try`/`catch` boundary, same `Future.wait`
  concurrency, same `isCurrent` re-checks, same comments, byte-identical
  otherwise.

Commit de725f3. `flutter test`: 1406 passed / 18 skipped before and after
(identical count — only additive test setup, no assertion changed). Two
gaps surfaced (not fixed, out of this task's scope; recorded in ADR-035):
`accountDeleted` and `userSignOut` are indistinguishable anywhere in
`AppAuthState` today, so both currently use `PurgeReason.userSignOut`; and
the `ActiveOrganizationVerifiedEmpty` identity-clear in
`auth_providers.dart`'s sign-in resolution is labelled
`membershipRevokedConfirmed` as the closest fit, ahead of D5's
two-confirmation purge gate (Phase 4).

## Task 2.4 — Architecture test

**Files:** `apps/lyron_app/test/architecture/`

- [x] Assert `LocalDataLifecycle` is the sole caller of every purge primitive
  (source scan). The test must fail if a new direct call appears.
- [x] Acceptance 8.

Commit bae31af. Reviewed clean (one accepted minor risk noted, see
ADR-035: the plain-text scan's `.clear()`/`.write()` patterns are scoped by
same-line receiver-name matching, so a call split across a renamed local
variable on a separate line would not be caught — the two delete-primitive
patterns don't share this weakness). Proven to actually fail: a temporary
violating call outside the allow-list was introduced, observed red with the
correct file/line/pattern in the failure message, then fully reverted;
confirmed green again on the clean tree.

## Task 2.5 — Diagnostics screen

**Files:** `apps/lyron_app/lib/src/presentation/account/`

- [x] Render the `local_data_events` log: when, why, how much. Read-only.

Commits ccd44ea, 51c4955. Reviewed; 3 minor nits found and the two
substantive ones (kind was only implied via reason-nullness, not shown
explicitly) fixed directly post-review. `flutter test`: 1407 → 1414 passed
(7 new tests), 18 skipped throughout.

**Phase 2 complete: Tasks 2.1-2.5 all done, reviewed, committed.**
`flutter analyze` clean, full `flutter test` green at 1414 passed / 18
skipped (commit d156c5a, after clearing one incidental `flutter analyze`
info-level lint unrelated to any task's own scope).

**Final whole-branch review (opus, the phase's single opus-tier call) found
one real regression, fixed before merge.** Scrutinizing `main..HEAD` against
the sole question "does this diff change observable behaviour anywhere?" —
with line-by-line focus on `wipePriorAndProceedFor` — it found that
`wipePriorAndProceedFor` itself was a verbatim substitution (confirmed
clean), but `LocalDataLifecycle`'s own methods introduced a real behaviour
change: an audit-write failure, occurring AFTER a purge/clear had already
committed, made the whole gate method throw as if the purge had failed. Fixed
in commit 5ba06be (best-effort audit write; `clearIdentity` takes an optional
caller-supplied `userId` instead of reading the identity store internally).
Re-verified: `flutter analyze` clean, `flutter test` green at 1416 passed /
18 skipped, and a follow-up sonnet-tier review of the fix commit itself
approved with zero findings. See ADR-035 for full detail, including three
lower-severity residual risks the same review surfaced and this phase
deliberately defers (audit DB lazy-open inside the destructive path, no
retention policy on `local_data_events`, and a sharper repro for the
architecture test's already-documented `.clear()`/`.write()` scan gap).

---

# Phase 3 — Write-path protection (D4, D6)

**Branch:** `fix/local-write-path-protection`

Closes F3 and F5. Theme: a write must never destroy more than it replaces.

## Task 3.1 — Reject implausible empty snapshots (D4)

**Files:** `song_catalog_controller.dart`,
`test/application/song_library/song_catalog_controller_test.dart`

- [x] Write a failing test: `listSongs()` returning `[]` with a non-empty stored
  snapshot leaves the cache untouched and reports the implausible-empty status.
- [x] Write a failing test: two consecutive independent empty resolutions do
  replace the snapshot.
- [x] Implement, with an audit record on rejection. Acceptance 4.

## Task 3.2 — Organization-scoped snapshot deletion (D4)

**Files:** `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`,
`test/offline/song_catalog/`

- [x] Write a failing test: refreshing organization A leaves organization B's
  cached snapshot intact for the same user.
- [x] Narrow `_deleteUserSnapshots` from `(userId)` to `(userId, organizationId)`.

## Task 3.3 — Explicit blue/green swap (D4)

**Files:** `song_catalog_store.dart`, tests alongside

Re-scoped by ADR-035 ("Task 3.3 — blue/green is a documented invariant plus a
rollback test, not an active-version pointer"): an active-version pointer was
evaluated and rejected for this phase, since `_replaceActiveSnapshot` already
runs its delete and its inserts inside one `_database.transaction()`, which is
already atomic on native SQLite. `snapshotVersion` stays a written-but-
unfiltered column, unchanged; it is not repurposed into a pointer.

- [x] Note in code why the existing single-transaction delete-then-insert
  shape is already blue/green-equivalent on native SQLite, and why it is
  redundant with (not a placeholder for) an active-version pointer, which
  would only be load-bearing on IndexedDB/web (best-effort, no acceptance
  test per the spec's Non-Goals). See the comment on `_replaceActiveSnapshot`
  in `song_catalog_store.dart` and ADR-035.
- [x] Fault-injection test: a write interrupted after the old snapshot's
  summaries/sources/row have been deleted but before the new snapshot's
  insert commits leaves the previous snapshot fully present and
  byte-identical (`test/offline/song_catalog/song_catalog_store_test.dart`,
  "DriftSongCatalogStore blue/green replace atomicity (D4, ADR-035 Task 3.3)"
  group, reusing `test/support/insert_failing_executor.dart`).

## Task 3.4 — Eviction trigger and proportionality (D6)

**Files:** `local_storage_write_recovery.dart`, `song_catalog_evictor.dart`,
`test/application/storage/`

- [x] Write a failing test: a guarded write throwing `SqliteException(BUSY)`
  performs no eviction and surfaces `LocalStorageWriteFailure`. Acceptance 6.
- [x] Write a failing test: eviction under a real pressure signal stops once the
  size target is met and leaves the active `(userId, organizationId)` intact.
- [x] Implement: trigger on `SQLITE_FULL` / `disk I/O error` /
  `QuotaExceededError`, or a measured footprint above the 2 GB budget. Evict in
  least-recently-read order to the target only.
- [x] Mark affected snapshots `sourcesEvicted` so the next successful refresh
  restores them.
- [x] Update ADR-028 with the amended trigger and proportionality rules.

---

# Phase 4 — Membership-revocation purge gate (D5, D8)

**Branch (first attempt, discarded):** `feat/membership-revocation-quarantine`
**Branch (re-scope):** `fix/membership-revocation-confirmation`

Closes F4 and F6. The only phase that adds a genuinely destructive path.

Phase 4 was attempted once as a read-only quarantine, reviewed, and found to
have six real concurrency defects. That implementation was discarded and the
phase re-scoped. The closeout of the first attempt is carried forward verbatim
below, ahead of the re-scoped tasks, because it is the specification for what
must not happen again. Its `file:line` references are against the archived
branch `feat/membership-revocation-quarantine` (HEAD `c70834f`), not against
`main`.

## Phase 4 closeout: Tasks 4.1-4.3 superseded, re-scope required

**Status as of this closeout: Tasks 4.1-4.3's implementation is complete,
reviewed, and committed (`8a87c05` through `7d21efc`, plus fixes), but the
final whole-branch review (opus, `cavecrew-reviewer`) found the underlying
concurrency design does not satisfy D5's two-confirmation guarantee. Do not
build on top of this implementation. A fresh session re-scopes Tasks 4.1-4.3
from the spec; this section is written so that session doesn't need this
conversation's context to act.** Task 4.4 (Android backup) is unaffected and
ships separately (see below). Task 4.5 (knowledge graph refresh) is complete
and unaffected.

### Root cause

Two design choices compound into the failure, neither wrong in isolation:

1. **The identity mutation chain (`LocalDataLifecycle._identityMutationChain`,
   `_inFlightResolutions`) is keyed by `userId`.** But
   `LastKnownIdentityStore` is a single global row (`DriftLastKnownIdentityStore`,
   `rowId: 1` — there is exactly one "last known identity" per device, by
   design, per the spec's confirmed-out-of-scope multi-account decision). Two
   different `userId`s therefore mutate the *same underlying row* through
   *different* lock keys — the keying assumes per-user state the storage
   doesn't have, so it serializes nothing across a user change.
2. **The confirmation dialog (`requestConfirmation`, backed by
   `ReauthPromptController`/`ReauthPromptHost`) is awaited from inside
   `resolveVerifiedEmptyMembership` while that call still holds its
   `_identityMutationChain` slot.** Any other same-key writer — critically,
   `clearMembershipRevocation`, which is exactly the call a concurrent
   *non-empty* resolution makes to say "false alarm, membership is back" —
   queues *behind* the pending confirmation instead of being able to
   invalidate it. The dialog can resolve `true` on a premise the app has
   already disproved online, and nothing re-checks state between the await
   and the purge.

Neither of these is what ADR-029's `ReauthPromptController` pattern does
(D3/Hazard 3 there rechecks currentness after every await boundary before a
destructive action) — the Phase 4 work re-used the *host* (correctly, per
ADR-035 Gap 3) but not that pattern's currentness-recheck discipline.

### The six red findings (genuine paths to a purge with fewer than two real confirmations, or other correctness failures)

All file:line references are against the final state of `feat/membership-revocation-quarantine`
(commit `7d21efc` and earlier; the closeout/graph commits after it touch none
of this code).

1. **`local_data_lifecycle.dart:536-542`** — no re-validation between
   `requestConfirmation` returning `true` and the purge triple running.
   Sequence: gate #2 for user A opens the confirmation dialog and holds A's
   chain slot. Membership is restored server-side. `SongCatalogController`'s
   independent periodic refresh gets a fresh, online, non-empty resolution
   and calls `clearMembershipRevocation(A)` — which queues *behind* the
   held slot instead of cancelling it. User taps confirm. Full purge runs
   under `membershipRevokedConfirmed` for a membership the app has already
   verified, online, is present.
2. **`auth_providers.dart:226` + `:337-339`** — the unknown-failure/
   connectivity-failure branch writes back `membershipRevokedAt` from a
   `priorIdentity` snapshot read *before* the RPC, not from current state.
   Sequence: marker set at T0. A concurrent verified-non-empty resolution
   legitimately clears it at T1. A stale connectivity-failure branch,
   already in flight since before T1, completes at T1.5 and re-writes the
   marker from its T0 snapshot. A single verified-empty resolution after
   that is read as "the second confirmation," even though a genuine
   non-empty sat between the two empties — violates D5's "two *consecutive*"
   requirement.
3. **`local_data_lifecycle.dart:197`** — the per-`userId` keying itself (see
   Root cause #1): two different users' writes to the single global identity
   row are completely unserialized against each other.
4. **`local_data_lifecycle.dart:292`** (`_clearIdentityUnlocked`) — clears
   the identity row unconditionally, with no check that the stored row still
   belongs to the caller's `userId`. Combined with #3's cross-user gap, a
   stale confirmation for user A can delete user B's identity row.
5. **`local_data_lifecycle.dart:581-594`** (the `matchesCaller == false`
   branch) — writes a *new* quarantine identity row when none exists for the
   caller, or overwrites a different user's row when one does. Two
   consequences: (a) after a confirmed purge deletes the row, a live
   session's periodic refresh can resolve verified-empty again (nothing
   stops the refresh timer post-purge), recreate the row via this branch,
   and reach a *second* silent purge (pending count now genuinely `0`) —
   repeating every refresh interval indefinitely; (b) a stale resolution
   captured under user A's identity, evaluated after B has since signed in,
   writes A's data into the single-row store, corrupting B's displayed
   identity.
6. **No call site in `lib/` catches `MembershipQuarantinedException`** — grep
   confirms only the two throw sites exist. ADR-035 Gap 2 promised the
   presentation layer catches it and shows a distinct message; it does not.
   A blocked write during quarantine currently surfaces as an uncaught
   exception — in at least one call site (`song_list_screen.dart:137`) inside
   an `unawaited` future, so it vanishes into the zone with no user-visible
   feedback and the user's edit is silently lost.

### Three yellow risks (lower severity, still real)

- **Deadlock.** The confirmation await is held inside the chain slot with no
  timeout. If the dialog never resolves (app backgrounded before the user
  answers; `ReauthPromptHost` can return early on an unmounted host without
  calling `answer`), every subsequent identity mutation for that `userId` —
  including `wipePriorAndProceedFor`'s `clearIdentity` call on the
  different-user sign-in path — hangs permanently. Only a superseding prompt
  rescues it.
- **Quarantine-entry cache reset contradicts D5's "read-only, not
  read-blocked."** `SongCatalogController`, `PlanningSyncController`, and
  `ActivePlanningContextController` all reset their in-memory context to
  empty/`null` on the *first* (quarantine-only) resolution, not just on a
  confirmed purge. The user sees an empty library and no plans during
  quarantine — visually indistinguishable from the purge D5 exists to defer,
  even though nothing has actually been deleted yet.
- **`ReauthPromptController`'s `StateError` is reachable**, contrary to its
  class doc, because `_inFlightResolutions` only dedups the quarantine
  prompt variant per-`userId` — it does not exclude a concurrent
  `ReauthDifferentUserPrompt` for a different user racing in via the
  cross-user path above.

### Decision: drop the read-only quarantine UX, keep D5's purge gate

The re-scope keeps D5's core requirement — two consecutive fresh, online,
authenticated empty resolutions, with no pending work or explicit
confirmation, before any purge — but drops the *intermediate read-only
quarantine state* (Task 4.1's `membershipRevokedAt`-marker-blocks-writes
design) entirely. The purge gate becomes a two-hit counter that either
purges on the second hit or doesn't; it no longer puts the device into a
distinct, user-visible "quarantined, editing disabled" state between the two
hits.

**Rationale.** A *false* quarantine entry — reachable through any of the six
findings above, or simply through the ordinary variance of two independent
concurrent listeners racing on one sign-in edge — locks a legitimately
member-in-good-standing user out of editing, with no offline way to clear it
(clearing requires a second *online* resolution). On a stage/rehearsal
device, exactly the scenario this whole durability contract exists to
protect, that lockout is worse than the narrow window it was meant to close:
a revoked member editing locally for the brief period before the second
online confirmation lands. Critically, **the quarantine was never what
protected the data** — backend RLS already rejects an unauthorized member's
writes (`has_capability`-gated policies on the songs/plans tables require an
active membership row; a revoked member's sync attempts already fail
authorization server-side, unchanged by anything in this phase). The local
quarantine only ever added a client-side UX affordance and a new way to
lock out a legitimate user; it did not add a security boundary AGENTS.md
rule 5 already requires to live server-side.

### One open item the re-scope must cover

A mutation queued locally before authorization was revoked can now never
sync — the backend will reject it with a permanent `403`/authorization
failure, not a transient one. Nothing in the current sync/retry machinery
distinguishes "will succeed if retried" from "will never succeed, ever,
because the actor's authorization was permanently revoked." The re-scope
must define a stop-and-tell-the-user behaviour for this case: detect a
permanent-authorization-failure response, stop retrying that specific
mutation (do not spin forever), and surface it to the user rather than
failing silently or leaving it queued forever with no explanation. This
generalizes beyond membership revocation — it applies to any permanent `403`
a queued mutation can receive (e.g. a capability grant revoked mid-flight for
an unrelated reason), so the re-scope should design it as a general
"queued mutation received a permanent authorization rejection" handler, not
a membership-revocation-specific one.

---

## Re-scoped Phase 4 tasks

Scope after the re-scope: the read-only quarantine UX is dropped entirely (spec
D5.0, ADR-035). What survives is D5's two-confirmation purge gate. Reading and
editing are unchanged in every state this phase can reach.

The concurrency model is prescribed by spec D5.5 and ADR-035 up front, not
derived task by task. Deviating from it is a stop condition, not a judgment
call.

## Task 4.1 — The marker and the gate

**Files:** `last_known_identity_tables.dart`, `last_known_identity_database.dart`
(v1 → v2 `onUpgrade`), `last_known_identity.dart`,
`drift_last_known_identity_store.dart`, `local_data_lifecycle.dart`,
`auth_providers.dart`, `planning_providers.dart`, tests

- [x] Write the negative tests first: one `verifiedEmpty` resolution deletes
  nothing; a second one inside the cooldown deletes nothing; a second one after
  a session change, an organization change, or an intervening non-empty
  resolution deletes nothing; the marker survives a process restart without
  becoming a second confirmation on its own.
- [x] Write a failing test: advancing the wall clock past the cooldown does not
  satisfy it. The in-process cooldown is measured on an injectable `Stopwatch`,
  never on `DateTime.now()` differences (spec D5.3, ADR-035). Across a process
  restart no cooldown check applies at all.
- [x] Write a failing test: an offline, connectivity-failure, unknown-failure or
  expired-session resolution neither sets nor clears the marker.
- [x] Add `membershipRevokedAt` (nullable) to `LastKnownIdentityRows`, with an
  explicit v1 → v2 `onUpgrade` delta and a migration test that populates a v1
  database and asserts no row is lost. Never `createAll`.
- [x] Add `LastKnownIdentityStore.resolveEmptyMembership({userId, now})`: one
  atomic operation that reads the row, verifies it belongs to `userId`, and
  either records the marker or reports that the cooldown-separated second
  confirmation has been reached. Generalises Phase 3's `resolveEmptySnapshot`
  shape (ADR-035); it does not reuse Phase 3's column, and the ADR states why.
- [x] Add `LastKnownIdentityStore.clearMembershipRevocation({userId})`, ownership
  checked, reporting whether a marker was actually cleared (so no spurious audit
  rows on ordinary sign-ins).
- [x] Route every counted resolution through `LocalDataLifecycle` on its single
  global serialization chain. No `userId` keying.
- [x] A freshly verified non-empty resolution clears the marker with an audit
  record; nothing else clears it.
- [x] Both marker edges write a `local_data_events` record — setting as well as
  clearing — under their own audit `kind`, with no `PurgeReason` (neither is a
  purge). Test both.

Delivered as commits `c27749b`..`44b2547`, plus `1f66148` (a review found the
in-process marker tracking was reset before the identity write committed, so a
failed write collapsed the two-confirmation gate to one).

## Task 4.2 — Confirmation and purge

**Files:** `local_data_lifecycle.dart`, `auth_providers.dart`,
`planning_providers.dart`, `reauth_prompt_controller.dart`,
`reauth_prompt_host.dart`, a new dialog, tests

- [x] Write a failing test: two counted confirmations with no pending work purge
  via `membershipRevokedConfirmed` and write the audit rows.
- [x] Write a failing test: pending work present → the purge waits for the user's
  confirmation, and the confirmation names what is lost. Acceptance 5.
- [x] Write a failing test: a non-empty resolution arriving while the
  confirmation dialog is open cancels the purge.
- [x] Write a failing test: pending work appearing while the dialog is open
  aborts the purge rather than discarding it implicitly.
- [x] Implement: decision inputs read inside the chain, dialog awaited outside
  it, premises re-validated on re-entry, purge executed inside it.
- [x] Reuse ADR-029's `ReauthPromptController`/`ReauthPromptHost`; do not add a
  second dialog owner.
- [x] Fix `auth_providers.dart`'s `persistNewIdentity` `ActiveOrganizationVerifiedEmpty`
  branch, which today clears the identity under
  `PurgeReason.membershipRevokedConfirmed` on a single resolution, and
  `VerifiedEmptyMembershipCleanupCoordinator.handleVerifiedEmptyMembership`,
  which today purges everything on a single resolution. Both become callers of
  the gate.
- [x] Phase 2's architecture test stays green with its allow-list unwidened.

Delivered as commits `96eb4f9`, `037ae99`, `2efecf9`, `a4b1500`. A review
added the missing try/catch around the purge triple: every caller is a
fire-and-forget listener, so a throw part way through left a half-purged device
with nothing reported.

## Task 4.3 — Permanently unauthorized queued mutations

**Files:** `supabase_song_mutation_repository.dart`,
`supabase_planning_mutation_repository.dart`, the two mutation sync
controllers, the unified sync surface, tests

- [x] Write a failing test: a queued mutation rejected with a permanent
  authorization failure is not retried again and is visible to the user with a
  reason that says it can never succeed.
- [x] Write a failing test: a queued mutation rejected with `401` stays
  retryable and is not made terminal — an ordinary token expiry must not discard
  the user's queued work.
- [x] Classify permanent authorization rejections as terminal: `403`, `42501`,
  and a `permission denied` message (PostgREST does not always return a
  structured PostgreSQL error code). Confirm no retry path re-sends them.
  Do **not** fold `401` in — `SongCatalogController._isAuthorizationFailure`
  collapses all four correctly for its own decision, and that collapse must not
  be copied here (spec D5.6, ADR-035).
- [x] Surface them; do not fail silently and do not leave them queued forever
  with no explanation.
- [x] General to any permanent authorization rejection, not specific to
  membership revocation.

Delivered as commits `8a2212f`..`79092bc`. The real defect turned out not to
be the classification alone: the song sync controller wrote the record's own
pending status back on an `authorizationDenied` failure, which
`readPendingSongs` then picked up again — the literal retry-forever loop the
closeout predicted. The `permission denied` match is narrowed to the full
PostgreSQL phrase so an unrelated error quoting those two words is not
misclassified as permanent.

## Task 4.4 — Android backup determinism (D8)

**Files:** `apps/lyron_app/android/app/src/main/AndroidManifest.xml`

- [x] Set `android:allowBackup="false"`, or add data-extraction rules keeping the
  session store and the SQLite databases in one backup set.
- [x] Note the choice and its consequence (no cloud restore of local catalogs) in
  ADR-035.

Landed independently of D5 as PR #76 (`android:allowBackup="false"`; no
data-extraction rules file was needed). Recorded in ADR-035's D8 section.

## Task 4.5 — Refresh the committed knowledge graph

**Files:** `graphify-out/`

`graphify-out/` was last rebuilt in PR #72, before Phases 2-4 introduced their
seams. The refresh performed during the first Phase 4 attempt indexed the
discarded quarantine implementation and lives only on the archived branch, so it
describes code that will never exist.

- [x] Run `graphify . --update` per `docs/workflows/ai-development.md:50`.
- [x] Spot-check `graphify explain "LocalDataLifecycle"` and
  `graphify query "what deletes local song catalog data"` against the post-slice
  architecture.
- [x] Commit separately from the code — it is a multi-megabyte generated
  artifact and mixing it in makes the code commit unreviewable.
- [x] Sanity-check the node count before and after: `references/update.md`'s own
  reference script passes changed files into `prune_sources` as well as deleted
  ones, which silently deletes every changed file's freshly-inserted nodes. Pass
  only genuinely deleted files. The first attempt produced a 4178-node graph
  instead of ~10000 this way, with no error or warning from the tool.


## Phase 4 re-scope outcome

The re-scope closed all six red findings and all three yellow risks from the
first attempt. The final whole-branch review (opus) then found two further red
findings and eight yellows on the re-scoped work, and a re-review of those
fixes found five more. All are closed; the notable ones, because they are the
kind that come back:

- A freshly verified non-empty resolution cleared the marker only on the
  sign-in edge, not on either controller's periodic live re-check. That let
  `empty -> genuine non-empty -> empty` purge, which is two *non-consecutive*
  empties — the first attempt's finding 2 re-entering through a different door.
  The freshness distinction the fix needs (`organizationLookupWasConnectivityFailure`)
  already existed in both controllers; an earlier survey had wrongly concluded
  it did not.
- Both marker clears were then written fire-and-forget. Because
  `clearMembershipRevocation` propagates store failures, a dropped failure left
  the marker set with no audit and no retry — silently reinstating the same
  sequence. They are awaited and reported now.
- Suppressing the conflict affordances for a permanently unauthorized row
  removed **Discard mine** along with **Keep mine**, stranding the row in the
  sync list forever. Discard is purely local and needs no authorization, so
  only Keep mine is suppressed.
- Two code comments justified a load-bearing guard with control flow that does
  not hold, which would have led a future reader to delete the guard.

A late review point, worth recording because the reasoning generalises: the
structural argument for "editing is unchanged" — zero `MembershipQuarantined`
or read-only hits anywhere in `lib/` and `test/` — is sound *evidence* and
worthless as a *guard*. You cannot block editing with code that does not
exist, but nothing fails when someone adds it. And the `membershipRevokedAt`
column now sitting in the schema is a standing invitation to ask "shouldn't
writes be blocked while this is set?". Acceptance 5's editing half is
therefore pinned by two real tests that set the marker and assert the edit
still queues, named `a set membership-revocation marker does not block local
editing (D5.0)`. This is the same failure mode as ADR-020 being correct on
paper and wrong in code, which is what the whole slice exists to close.

The lesson the first attempt already recorded held again: every round of this
work produced at least one defect in the "value read before an await, written
after it" or "fire-and-forget a call that can fail" family.

---

## Verification before each merge

- [x] `flutter analyze` clean.
- [x] `flutter test` green, including the acceptance tests introduced so far.
- [x] The relevant acceptance items from the spec pass, run and observed — not
  assumed.
- [x] Documentation updated in the same PR as the code it justifies
  (AGENTS.md rule 4).
