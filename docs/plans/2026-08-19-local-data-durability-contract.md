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
  Live-sync on every external write/clear is deferred to Phase 2 (D7's single
  gate) — writes today happen only outside this class
  (`auth_providers.dart`), and centralizing them is Phase 2's job, not
  Phase 1's. Not a gap for Phase 1's acceptance criteria: they are all
  cold-start scenarios, where the cache is populated fresh at construction
  from the durable store before it is ever read.

## Task 1.2 — `signedOut` requires an explicit act (D2)

**Files:** `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`,
`apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

- [ ] Write failing tests first, one per row of the D1 forbidden list that
  reaches this function:
  - `null` session from `initializing` + identity present → `sessionExpired`
  - `null` session from `sessionExpired` + identity present → stays
    `sessionExpired`
  - `null` session + **no** identity → `signedOut` (nothing to protect)
  - `signOut()` in progress (`_isSigningOut`) → `signedOut`
  - a `null` event during `restoreSession()`'s await cannot replace the restored
    state with a more destructive one
- [ ] Implement: remove the `_state.status == AppAuthStatus.signedIn` condition
  from `_stateForSession`. New rule: `signedOut` iff `_isSigningOut` **or** no
  `LastKnownIdentity`; otherwise `sessionExpired`.
- [ ] Constrain the `_authGeneration` guard in `restoreSession()` so a stream
  event may not downgrade a restored `sessionExpired` to `signedOut`.
- [ ] Existing explicit-sign-out tests must stay green **without modification**.
  If they cannot, STOP and report.
- [ ] `flutter test test/application/auth/` green.

## Task 1.3 — Catalog context from local data alone (D3)

**Files:** `apps/lyron_app/lib/src/application/song_library/song_catalog_controller.dart`,
`apps/lyron_app/lib/src/application/song_catalog_providers.dart`,
`apps/lyron_app/test/application/song_library/song_catalog_controller_test.dart`

- [ ] Write a failing test: a controller in `sessionExpired`, with a stored
  snapshot for `LastKnownIdentity`'s `(userId, organizationId)` and a remote
  repository that throws on every call, exposes a non-null `context` and the
  cached summaries.
- [ ] Implement `handleOfflineAuthenticated()`: establish `context` from
  `LastKnownIdentity` when a local snapshot exists for that pair. No network
  call, no session check.
- [ ] Wire it into the `sessionExpired` branch of `handleAuthStateChanged`
  alongside the existing `handleSessionExpired()`.
- [ ] Verify `songLibraryListProvider` yields the cached songs in this state.

## Task 1.4 — Planning mirror

**Files:** `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`,
`apps/lyron_app/lib/src/application/planning_providers.dart`, plus tests under
`apps/lyron_app/test/application/planning/`

- [ ] Same shape as 1.3 for the planning projection: `sessionExpired` resolves a
  read context from `LastKnownIdentity` without network access.

## Task 1.5 — Cold-start integration test

**Files:** `apps/lyron_app/test/integration/`

- [ ] Acceptance 1: offline cold start, expired access token, valid refresh token
  → songs visible, zero deletions.
- [ ] Acceptance 2: offline cold start, auth stream emits `signedOut` → zero
  deletions, `sessionExpired`, songs visible.
- [ ] Acceptance 3: persisted session removed while `LastKnownIdentity` survives
  → zero deletions, songs visible.
- [ ] Acceptance 7: advanced-clock multi-day offline span → songs visible on
  every cold start.

## Task 1.6 — Documentation

- [ ] Write `docs/architecture/decisions/ADR-035-local-data-purge-contract.md`
  carrying D1–D8. Mark it as enforcing ADR-020 rather than superseding it.
- [ ] Correct `docs/deferred/2026-08-02-refresh-token-ttl-lf-t2.md`: its claims
  that `_stateForSession` never maps to data loss and that no read path gates on
  session validity were false. Record what was actually true, and close it as a
  durability concern (it remains a sync-resumption note only).
- [ ] Update `docs/architecture/architecture.md` with the purge-contract seam.
- [ ] Add a release note: expired refresh tokens no longer bounce the user to
  sign-in; they stay offline-authenticated and sync resumes after re-auth.

---

# Phase 2 — `LocalDataLifecycle` gate and audit trail (D7)

**Branch:** `refactor/local-data-lifecycle-gate`

No behaviour change. This is what keeps a fifth purge path from being added by
accident later.

## Task 2.1 — The gate

**Files:** new `apps/lyron_app/lib/src/application/storage/local_data_lifecycle.dart`,
new test alongside

- [ ] Write failing tests first: each `PurgeReason` performs its documented set of
  deletions and writes exactly one audit record; a failure in one store's
  deletion is reported and does not silently claim success.
- [ ] Implement `PurgeReason { userSignOut, accountDeleted, differentUserSignIn,
  membershipRevokedConfirmed }` and a `LocalDataLifecycle` that owns every purge.

## Task 2.2 — Audit store

**Files:** `apps/lyron_app/lib/src/offline/` (new `local_data_events` table +
migration), tests under `apps/lyron_app/test/offline/`

- [ ] Table: timestamp, reason, `userId`, affected row counts per store.
- [ ] Drift schema bump with an explicit `onUpgrade` delta, matching the existing
  migration contract.
- [ ] Eviction events are recorded here too, under a distinct non-purge kind.

## Task 2.3 — Route every call site through the gate

**Files:** `song_catalog_controller.dart`, `planning_sync_controller.dart`,
`auth_providers.dart`, `planning_providers.dart`

- [ ] Move all `deleteCatalogsForUser`, `deletePlanningDataForUser` and
  `LastKnownIdentityStore.clear()` calls behind `LocalDataLifecycle`.
- [ ] Preserve the existing `differentUserSignIn` semantics exactly, including
  the ordering and failure handling documented in `auth_providers.dart` — that
  code encodes prior review findings and must not be simplified here.

## Task 2.4 — Architecture test

**Files:** `apps/lyron_app/test/architecture/`

- [ ] Assert `LocalDataLifecycle` is the sole caller of every purge primitive
  (source scan). The test must fail if a new direct call appears.
- [ ] Acceptance 8.

## Task 2.5 — Diagnostics screen

**Files:** `apps/lyron_app/lib/src/presentation/account/`

- [ ] Render the `local_data_events` log: when, why, how much. Read-only.

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
