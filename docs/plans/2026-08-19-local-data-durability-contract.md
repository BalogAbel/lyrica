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
two-confirmation quarantine gate (Phase 4).

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

- [ ] Write a failing test: `listSongs()` returning `[]` with a non-empty stored
  snapshot leaves the cache untouched and reports the implausible-empty status.
- [ ] Write a failing test: two consecutive independent empty resolutions do
  replace the snapshot.
- [ ] Implement, with an audit record on rejection. Acceptance 4.

## Task 3.2 — Organization-scoped snapshot deletion (D4)

**Files:** `apps/lyron_app/lib/src/offline/song_catalog/song_catalog_store.dart`,
`test/offline/song_catalog/`

- [ ] Write a failing test: refreshing organization A leaves organization B's
  cached snapshot intact for the same user.
- [ ] Narrow `_deleteUserSnapshots` from `(userId)` to `(userId, organizationId)`.

## Task 3.3 — Explicit blue/green swap (D4)

**Files:** `song_catalog_store.dart`, tests alongside

- [ ] Write rows under `snapshotVersion + 1`; reads follow an active-version
  pointer; the previous version is deleted only after the pointer moves.
- [ ] Test: a write interrupted before the pointer moves leaves the previous
  snapshot fully readable.
- [ ] Note in code why this is redundant on native SQLite and load-bearing on
  IndexedDB.

## Task 3.4 — Eviction trigger and proportionality (D6)

**Files:** `local_storage_write_recovery.dart`, `song_catalog_evictor.dart`,
`test/application/storage/`

- [ ] Write a failing test: a guarded write throwing `SqliteException(BUSY)`
  performs no eviction and surfaces `LocalStorageWriteFailure`. Acceptance 6.
- [ ] Write a failing test: eviction under a real pressure signal stops once the
  size target is met and leaves the active `(userId, organizationId)` intact.
- [ ] Implement: trigger on `SQLITE_FULL` / `disk I/O error` /
  `QuotaExceededError`, or a measured footprint above the 2 GB budget. Evict in
  least-recently-read order to the target only.
- [ ] Mark affected snapshots `sourcesEvicted` so the next successful refresh
  restores them.
- [ ] Update ADR-028 with the amended trigger and proportionality rules.

---

# Phase 4 — Membership-revocation quarantine (D5, D8)

**Branch:** `feat/membership-revocation-quarantine`

Closes F4 and F6. The only phase that adds a genuinely destructive path.

## Task 4.1 — Quarantine on first empty resolution

**Files:** `planning_providers.dart`, `song_catalog_controller.dart`, store
migration for `membershipRevokedAt`, tests

- [ ] Write a failing test: one `verifiedEmpty` resolution deletes nothing and
  records the quarantine marker.
- [ ] Implement read-only quarantine: data remains readable, writes are blocked,
  a banner explains why.

## Task 4.2 — Confirmed purge

**Files:** same, plus `LocalDataLifecycle`

- [ ] Write a failing test: two consecutive fresh online empty resolutions with no
  pending work purge via `membershipRevokedConfirmed` and write the audit row.
- [ ] Write a failing test: pending work present → the purge waits for user
  confirmation. Acceptance 5.
- [ ] Reuse the existing confirmation host rather than adding a second dialog
  owner (ADR-029).

## Task 4.3 — Clearing quarantine

- [ ] Any subsequent non-empty membership resolution clears the marker and
  restores normal operation, with an audit record.

## Task 4.4 — Android backup determinism (D8)

**Files:** `apps/lyron_app/android/app/src/main/AndroidManifest.xml`

- [ ] Set `android:allowBackup="false"`, or add data-extraction rules keeping the
  session store and the SQLite databases in one backup set.
- [ ] Note the choice and its consequence (no cloud restore of local catalogs) in
  ADR-035.

---

## Verification before each merge

- [ ] `flutter analyze` clean.
- [ ] `flutter test` green, including the acceptance tests introduced so far.
- [ ] The relevant acceptance items from the spec pass, run and observed — not
  assumed.
- [ ] Documentation updated in the same PR as the code it justifies
  (AGENTS.md rule 4).
