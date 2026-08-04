# Offline-Capable Discard and the Slug Read Path — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make dropping local intent work without the network, make an offline
retry say so, and resolve a plan slug with one mutation read instead of two.

**Architecture:** `SongMutationSyncController.discardMine` becomes local-first —
delete the local song for a pending create or a remote-deleted conflict, clear
the mutation row otherwise (the cached snapshot *is* the restore) — followed by a
best-effort catalog refresh whose failure is swallowed. `PlanningLocalReadRepository`
resolves slugs against pending creates and the store's indexed lookup, reading the
mutation set once.

**Tech Stack:** Dart / Flutter, Drift, Riverpod 2, `flutter_test`.

**Spec:** `docs/specs/2026-07-30-lf7-offline-discard-and-lf9-slug-read.md`

---

## File Structure

**Modify:**

| path | change |
|---|---|
| `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart` | `discardMine` becomes local-first |
| `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart` | retry surfaces a connectivity failure |
| `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart` | show the retry failure (only if the controller change requires it) |
| `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart` | single-read slug resolution |
| `docs/architecture/architecture.md`, `docs/testing/testing-strategy.md`, `docs/architecture/repository-review-2026-06-22.md` | documentation |

**Tests:** extend the existing suites — do not start new parallel harnesses.
Locate them first: song controller tests under
`apps/lyron_app/test/application/song_library/`, planning controller tests under
`apps/lyron_app/test/application/planning/`, and the adversarial offline suite at
`apps/lyron_app/test/offline/adversarial/`.

All commands run from the repository root using the repo convention
`(cd apps/lyron_app && flutter test <path>)`.

---

### Task 1: Offline song discard drops the mutation without the network

**Files:**
- Modify: `apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart`
- Test: the existing song mutation sync controller test file (find it first)

- [x] **Step 1: Write the failing tests**

Find the existing test file and its fake remote repository. Add tests that use a
fake whose `fetchSong` always throws
`SongMutationSyncException(SongMutationSyncErrorCode.connectivityFailure, ...)`
— match the existing fakes' construction style rather than inventing a new one.

Four tests, each asserting one thing the current code gets wrong:

1. `discardMine` on a pending **update** while offline completes without
   throwing, and afterwards `readSongMutationBySongId` returns `null` — the
   mutation is really gone.
2. After that same offline discard, the record is **not** in
   `SongSyncStatus.conflict`. Read back whatever the store exposes and assert the
   absence of the conflict state explicitly. This is the exact regression in the
   current code: a discard attempt currently marks the record conflicted.
3. `discardMine` on a pending **create** while offline deletes the song locally —
   nothing remains in the mutation table and nothing remains readable as a song.
4. A best-effort refresh that throws does not undo the discard: with a refresh
   callback that always throws, `discardMine` still completes and the mutation is
   still gone.

- [x] **Step 2: Run and confirm they fail**

```bash
(cd apps/lyron_app && flutter test test/application/song_library/)
```

Report the real failure output. Tests 1–3 should fail against the current
fetch-first implementation.

- [x] **Step 3: Rewrite `discardMine`**

Replace the body with a local-first sequence. Keep `_requireSong` and the
`isRemoteDeletedConflict` shortcut. The shape:

```dart
  Future<void> discardMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    final record = await _requireSong(
      context,
      songId: songId,
      includeConflicts: true,
    );

    // Discarding is dropping local intent, so it must never need the network
    // (LF-7). The song's pending edit lives in its own table, which means the
    // cached snapshot still holds the last known server copy: dropping the
    // mutation row IS the restore. Fetching the server record only buys
    // freshness, and freshness is the refresh path's job.
    if (record.isRemoteDeletedConflict ||
        record.effectiveSyncStatus == SongSyncStatus.pendingCreate) {
      // Never existed remotely (or is already gone there): remove it locally.
      await _store.deleteSong(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
      );
    } else {
      await _store.clearSongMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
      );
    }

    // Best effort only: pick up the freshest server copy when there is a
    // connection. The discard has already happened and is never undone by a
    // failure here -- and a discard must never leave a conflict status
    // behind, because being conflicted is a sync outcome, not something the
    // user asked for by throwing their edit away.
    final refreshCatalog = _refreshCatalog;
    if (refreshCatalog == null) {
      return;
    }
    try {
      await refreshCatalog(context);
    } on SongMutationSyncException {
      // Offline or the backend refused: the local discard still stands.
    }
  }
```

Verify `effectiveSyncStatus` and `SongSyncStatus.pendingCreate` are the real
member names before using them. If `refreshCatalog` can throw something other
than `SongMutationSyncException`, widen the catch to `on Exception` — but never
to bare `catch`, so a programming defect still propagates.

- [x] **Step 4: Run the tests**

```bash
(cd apps/lyron_app && flutter test test/application/song_library/)
(cd apps/lyron_app && flutter test)
```

Existing tests that assert `fetchSong` is called during a discard encode the old
contract. Update them to the new one and say in your report exactly which tests
you changed and why. Do NOT change a test that is asserting something else.

- [x] **Step 5: Commit**

```bash
(cd apps/lyron_app && dart format lib test)
(cd apps/lyron_app && flutter analyze)
git add apps/lyron_app/lib/src/application/song_library/song_mutation_sync_controller.dart apps/lyron_app/test/
git commit -m "fix(song): discard local song intent without the network"
```

---

### Task 2: An offline retry says so

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_mutation_sync_controller.dart`
- Possibly modify: `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`
- Test: the existing planning mutation sync controller test file

Today `retryMutation` marks the record pending, calls `syncPendingMutations`, and
that swallows a connectivity failure. The caller cannot tell a retry that ran
from one that never left the device.

- [x] **Step 1: Write the failing test**

With a remote repository that throws `connectivityFailure`, calling
`PlanningMutationSyncController.retryMutation` must surface that to the caller.
Assert on the observable contract — either a thrown typed exception or a
returned result, whichever fits the existing controller's style. Read the
controller and its tests and pick the shape that matches; state your choice in
the report before implementing.

Also assert what must NOT change: the record stays in the store, marked pending
with a `connectivityFailure` error code, so the row still renders as retryable.
A retry that reports failure must not also discard the user's work.

- [x] **Step 2: Run and confirm it fails**

```bash
(cd apps/lyron_app && flutter test test/application/planning/planning_mutation_sync_controller_test.dart)
```

- [x] **Step 3: Implement**

Change `retryMutation` only — do NOT change `syncPendingMutations`'s swallowing
behaviour for the ordinary background path. A background sync that hits no
network is normal and must stay quiet; an explicit user-initiated retry is what
needs to report. If that means `retryMutation` inspects the record's error code
after syncing rather than catching, that is fine and is probably the smaller
change.

- [x] **Step 4: Surface it in the popup**

In `unified_sync_status_popup.dart`, `_applyToGroup(retry: true)` currently
tracks `hasError` and shows a snackbar. If the controller now reports the
failure, confirm the existing error handling picks it up; extend it only if it
does not. Keep the change minimal — the popup is being restructured in the next
slice and large edits here will collide.

- [x] **Step 5: Verify and commit**

```bash
(cd apps/lyron_app && flutter test)
(cd apps/lyron_app && dart format lib test)
(cd apps/lyron_app && flutter analyze)
git add apps/lyron_app/
git commit -m "fix(sync): report an offline retry instead of failing silently"
```

---

### Task 3: Resolve a plan slug with one mutation read

**Files:**
- Modify: `apps/lyron_app/lib/src/application/planning/planning_local_read_repository.dart`
- Test: the existing repository test file

- [x] **Step 1: Write the failing tests**

Two tests, using a recording fake `PlanningLocalStore` and a recording fake
mutation store (follow whatever fakes the existing test file already has):

1. **Counted reads.** One `getPlanDetailBySlug` call performs exactly **one**
   actionable-mutation read and **no** full plan-summary listing. Count the calls
   on the fakes. This fails today: it does two reads and one full listing.
2. **Offline-created plans stay findable.** A plan that exists only as a pending
   `planCreate` mutation — with its slug in the mutation and nothing in the
   projection — is still returned by `getPlanDetailBySlug` and
   `getPlanSummaryBySlug`. This is the trap: the optimisation must resolve
   against pending creates, not just the store's indexed lookup.

- [x] **Step 2: Run and confirm the counting test fails**

```bash
(cd apps/lyron_app && flutter test test/application/planning/planning_local_read_repository_test.dart)
```

- [x] **Step 3: Implement**

Restructure so the mutation set is read once and threaded through:

- add a private `_getPlanDetailWithMutations(context, planId, mutations)` holding
  the current body of `getPlanDetail`, and make the public `getPlanDetail` read
  the mutations and delegate to it — behaviour unchanged for existing callers;
- add a private `_resolvePlanIdBySlug(context, slug, mutations)` that first scans
  the given mutations for a pending `planCreate` whose slug matches, and
  otherwise calls `PlanningLocalStore.readPlanSummaryBySlug`;
- `getPlanDetailBySlug` reads the mutations once, resolves the id, then calls
  `_getPlanDetailWithMutations` with the same list;
- `getPlanSummaryBySlug` uses the same resolution and returns the merged summary
  without listing every plan.

Do not change `listPlans` or the merge functions themselves.

Note while implementing: a pending `planEdit` cannot change a slug — the edit
draft carries no slug field — so slug resolution only has to consider the
projection and pending creates. If you find that assumption is wrong, stop and
report it rather than working around it.

- [x] **Step 4: Verify and commit**

```bash
(cd apps/lyron_app && flutter test)
(cd apps/lyron_app && dart format lib test)
(cd apps/lyron_app && flutter analyze)
git add apps/lyron_app/
git commit -m "perf(planning): resolve a plan slug with one mutation read"
```

---

### Task 4: Documentation

- [x] **Step 1: `docs/architecture/architecture.md`**

In the Offline Strategy section, record that dropping local intent never requires
the network, for songs and plans alike, and that a discard never leaves a
conflict status behind. Proportionate edit only.

- [x] **Step 2: `docs/testing/testing-strategy.md`**

Record the offline-discard contracts and the slug-read contracts.

- [x] **Step 3: `docs/architecture/repository-review-2026-06-22.md`**

Mark LF-7 and LF-9 fixed with the existing `~~struck~~ **Done (...)**`
convention and update the §6 status blocks in the style already used there.
State two things honestly rather than glossing them:

- LF-7's planning half was already resolved by PR #62/#63; the live violation
  this slice fixed was on the song side, where an offline discard also wrote a
  conflict status onto the record;
- LF-9's slug path has no live caller today — the routes resolve slugs through
  `planningPlanListProvider` and fetch detail by id — so this is a correctness
  fix to an interface method, not a measured performance win.

- [x] **Step 4: Verify and commit**

```bash
./scripts/verify.sh --skip-migrations --skip-backend-write-contracts
git add docs/
git commit -m "docs(sync): record the offline discard and slug read contracts"
```

---

## Self-Review

**Spec coverage:** D1 → Task 1; D2 → Task 2; D3 → Task 3; testing contracts 1–5
→ Task 1, 6 → Task 2, 7–8 → Task 3; documentation → Task 4.

**Deliberately not shown as literal code:** the test bodies in Tasks 1–3. Each
one has to adopt the fakes and construction style of an existing test file that
must be read first, and inventing parallel fakes here would be worse than
describing the contract precisely. Every assertion those tests must make is
enumerated.
