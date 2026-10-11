# Plan: The Different-User Wipe Deletes Only the Work It Counted

- Spec: `docs/specs/2026-10-11-reauth-wipe-recount.md` (RW1–RW4, AC1–AC8)
- Branch: `fix/reauth-wipe-recount` (from `main` at `d5fd3de`)
- Execution: subagent-driven. Implementer Sonnet (medium effort), task review
  Haiku. One adversarial Opus whole-diff review before the PR.

## Rules for every task

- Paths below are relative to `apps/lyron_app/` unless they start with
  `docs/`.
- Tests first. Run the new test and watch it fail for the stated reason
  before touching `lib/`.
- After every task run the **full** suite and the analyzer, never a subset:
  `flutter test` and `flutter analyze` in `apps/lyron_app/`. Both must be
  clean before the task's commit.
- **Stop and report** (do not improvise) if:
  - an existing test fails and the change is not listed under the spec's
    "Intentional test changes";
  - a code excerpt quoted here does not match the real file;
  - the full suite reports a Riverpod error during a provider build;
  - the change would need a new purge, a new `PurgeReason`, an ADR-035
    change, or a restructuring of the sign-out or reauth flows.
- Reviewers: do not review the commit trailer lines.

## Task 0 — red suite, spec, plan (done at the design gate)

`test/integration/cross_user_local_first_leak_test.dart`:

- fixture gains a song-write gate (`_GatedSongMutationStore`, user A only)
  and an optional pending-count gate (`gatePendingCount: true` wraps the
  production `DriftPendingLocalWorkReader` in a `PendingLocalWorkCounter`
  that pauses after both real reads);
- `seedPendingPlanningForA` (default `true`, unchanged behaviour);
- helpers `pendingSongCount`, `startImport` (the real controller; the
  platform file picker channel `miguelruivo.flutter.plugins.filepicker` is
  mocked) and `importState`;
- group "the different-user wipe deletes only counted work" with (a) and (b),
  both `skip: 'red until Task 3'`.

## Task 1 — `ImportRunTracker`, never stuck (RW3 seam; AC8, AC9 unit part)

**Test first** (`test/presentation/song_library/chordpro_import_controller_test.dart`):

- In group "the run link on every end path", give `_SettableImportController`
  an optional `ImportRunTracker? runTracker` passed to `super`, and build the
  probe with a tracker the test holds.
- New tests:
  - for every running state, `setImportState(running)` makes
    `tracker.isRunning` `true`, and every end state then makes it `false`
    (reuse the existing `runningStates` × `endStates` loop shape);
  - the throwing-listener path: after the `ImportDone` that throws in a
    listener, `tracker.isRunning` is `false`;
  - **dispose:** `setImportState(ImportCommitting())`, then dispose the
    controller (close the subscription and `container.invalidate(probeProvider)`,
    or dispose the container) → `tracker.isRunning` is `false`. A
    `setImportState(ImportAnalysing())` on the disposed instance (it throws a
    debug `StateError`; wrap it in `expect(..., throwsStateError)`) leaves
    `tracker.isRunning` `false`;
  - **per instance:** two controllers on one tracker; A running, B goes from
    running to idle → still running; A ends → idle;
  - through the real provider (group "a commit through the real provider"):
    - while `ImportCommitting`, `container.read(importRunTrackerProvider).isRunning`
      is `true`;
    - after `commit.complete(emptyResult)` it is `false`;
    - after `commit.completeError(...)` (`ImportFailed`) it is `false`;
  - **escaped exception:** a `startImport` whose analysis returns a result
    whose `duplicates` getter throws. The picker channel
    `miguelruivo.flutter.plugins.filepicker` is mocked as in the integration
    fixture. The returned future fails, the state is `ImportFailed` with
    `AppStrings.songImportInterruptedMessage`, the tracker is idle, and the
    provider is released once unlistened;
  - **picker cancel:** the picker channel answers `null` → `ImportIdle`, and
    the tracker is idle;
  - `commitWithResolutions` is refused while a commit is running (the state
    stays `ImportCommitting`, the service is called once).

**Implementation:**

1. New `lib/src/application/song_library/import_run_tracker.dart`:

   ```dart
   /// RW3 (docs/specs/2026-10-11-reauth-wipe-recount.md): whether a ChordPro
   /// import run is in a phase that writes pending work in the background
   /// (`isImportRunning`, SO7 of
   /// docs/specs/2026-10-07-sign-out-pending-work-guard.md).
   ///
   /// The import controller is a presentation-layer notifier; this is the
   /// application layer's view of its runs, so the different-user wipe can
   /// refuse to start while one may be writing. Keyed by the reporting
   /// controller instance: each instance adds and removes only itself, and a
   /// disposed instance removes itself, so "running" can never outlive the
   /// instance that reported it.
   class ImportRunTracker {
     final _running = <Object>{};

     bool get isRunning => _running.isNotEmpty;

     void report(Object owner, {required bool running}) {
       if (running) {
         _running.add(owner);
       } else {
         _running.remove(owner);
       }
     }
   }
   ```

2. `lib/src/application/song_catalog_providers.dart`, after
   `appForegroundStateProvider`:

   ```dart
   /// RW3: app-scoped, never autoDispose -- the different-user wipe reads it
   /// while no import screen may be mounted.
   final importRunTrackerProvider = Provider<ImportRunTracker>((ref) {
     return ImportRunTracker();
   });
   ```

   plus the import of `import_run_tracker.dart`.

3. `lib/src/presentation/song_library/chordpro_import_controller.dart`:
   - the constructor gains `this._runTracker,` after `this._keepAlive,`, with
     the field `final ImportRunTracker? _runTracker;`;
   - the state setter becomes:

     ```dart
     @override
     set state(ChordProImportState value) {
       // ...existing SO7 comment, plus: RW3 -- the tracker follows the same
       // transitions, settled before the listeners run for the same reason,
       // and a disposed instance never reports running again.
       final running = isImportRunning(value);
       if (running) {
         _runLink ??= _keepAlive?.call();
       } else {
         _runLink?.close();
         _runLink = null;
       }
       _runTracker?.report(this, running: running && mounted);
       super.state = value;
     }
     ```

   - `dispose()` override: `_runTracker?.report(this, running: false);` then
     `super.dispose();`;
   - `startImport`: the SO7 refusal stays first; the rest of the body moves
     to `Future<void> _runImport()`, called as
     `try { await _runImport(); } finally { _endRun(); }`;
   - `commitWithResolutions`: first
     `if (isImportRunning(state)) return;` (one run at a time, as
     `startImport`), then the existing body inside
     `try { ... } finally { _endRun(); }`;
   - new:

     ```dart
     /// RW3: whatever ended the run -- a normal end, a caught failure, a
     /// picker cancel, a throw nothing caught, or a dispose -- leaves no
     /// running phase behind, so neither SO7's sign-out refusal nor the
     /// different-user wipe's refusal can stay engaged after the run.
     void _endRun() {
       if (!mounted) {
         _runTracker?.report(this, running: false);
         return;
       }
       if (isImportRunning(state)) {
         state = const ImportFailed(AppStrings.songImportInterruptedMessage);
       }
     }
     ```

4. `lib/src/shared/app_strings.dart`, next to the other `songImport*`
   strings: `static const songImportInterruptedMessage =
   'The import stopped before it finished.';`
5. `lib/src/presentation/song_library/song_library_providers.dart`,
   `chordProImportControllerProvider`: add
   `runTracker: ref.watch(importRunTrackerProvider),` (the barrel
   `application/providers.dart` it already imports exports
   `song_catalog_providers.dart`).

Commit: `feat(import): report import runs to an app-scoped tracker (RW3)`.

## Task 2 — the wipe receives its decision count (RW1, AC7)

**Test first** (`test/application/auth/reauth_resolution_test.dart`):

- New tests in group `resolveReauth`:
  - zero pending: the wipe callback receives `0`;
  - pending 3, confirmed: the wipe receives `3`;
  - unknown (`priorPendingCount` returns `null`), confirmed: the wipe receives
    `null` (record with a `var received = -1;` sentinel so `null` is
    observable).
- The ten existing `wipePriorAndProceed: () async ...` callbacks become
  `wipePriorAndProceed: (_) async ...` (the spec's only intentional test
  change). They fail to compile until the signature changes; that is the red
  step for this task.

**Implementation** (`lib/src/application/auth/reauth_resolution.dart`):

- parameter: `required Future<bool> Function(int? countedPendingWork)
  wipePriorAndProceed,`
- zero path: `if (!await wipePriorAndProceed(count)) {`
- confirm arm: `await wipePriorAndProceed(count)`
- doc comment: one paragraph — the wipe receives the count the decision was
  made on (0 without a prompt, the prompt's count including `null` on
  confirm) and must not delete more than that (RW2, spec reference).

`lib/src/application/auth_providers.dart`, the two `resolveReauth` calls:

- null-identity branch: `wipePriorAndProceed: (_) async => false,`
- identity branch:
  `wipePriorAndProceed: (countedPendingWork) =>
  wipePriorAndProceedFor(identity, countedPendingWork),`
- `wipePriorAndProceedFor(LastKnownIdentity identity)` gains
  `int? countedPendingWork` as its second positional parameter, unused until
  Task 3.

Commit: `refactor(reauth): pass the decision count to the wipe (RW1)`.

## Task 3 — recount before the deletion; decline cancels (RW2, RW4; AC1, AC2, AC5, AC6)

**Test first:**

- Unskip (a) and (b) in `cross_user_local_first_leak_test.dart` and extend
  their assertions per AC1/AC2: after the final settle,
  `fixture.auth.state.status == AppAuthStatus.sessionExpired`,
  `fixture.auth.state.currentUserId == _userA`, the identity row is A's;
  for (a) also `pendingPlanningMutationCount(_userA) == 1`.
- `test/application/auth/identity_persistence_wiring_test.dart`, group
  "different-user reauth resolution on the live signedIn edge", modelled on
  "outcome 3" (same overrides, `seedPriorUserData()`):
  - **recount lower:** the song reader returns 3 on the first call and 2 on
    the second; confirm → the wipe ran (`priorSongsStillPresent()` false,
    one identity write for `user-2`, `signedIn` as `user-2`);
  - **recount higher:** 3 then 4; confirm → nothing deleted
    (`priorSongsStillPresent()` true, `clearCount` 0, no writes),
    `authRepository.signOutCalls == 1`, `sessionExpired` with
    `lastKnownSession.userId == 'user-1'`;
  - **recount unreadable:** 3 then throws; confirm → as "recount higher";
  - **confirmed unknown is not recounted:** the planning reader always
    throws; the prompt shows `null`; confirm → the wipe ran (as "recount
    lower");
  - **zero then nonzero, no prompt:** 0 then 1 → no prompt, nothing
    deleted, `sessionExpired` as `user-1`.

**Implementation** (`lib/src/application/auth_providers.dart`, inside
`persistIdentity`'s `signedIn` case):

1. Before `wipePriorAndProceedFor`, a helper:

   ```dart
   // RW2 (docs/specs/2026-10-11-reauth-wipe-recount.md): whether the prior
   // user's pending work is still no more than the count the decision was
   // made on. A confirmed unknown is not compared (the user accepted an
   // unknown amount; D5.5 rule 3 does the same); an unreadable recount of a
   // known count is uncertainty, which never authorises a wipe (D5).
   Future<bool> priorWorkStillAsCounted(
     LastKnownIdentity identity,
     int? countedPendingWork,
   ) async {
     if (countedPendingWork == null) return true;
     try {
       final current = await ref
           .read(pendingLocalWorkCounterProvider)
           .count(userId: identity.userId);
       return current <= countedPendingWork;
     } catch (_) {
       return false;
     }
   }
   ```

2. In `wipePriorAndProceedFor`, between the existing first currentness check
   and `final priorUserId = identity.userId;`:

   ```dart
   final stillAsCounted = await priorWorkStillAsCounted(
     identity,
     countedPendingWork,
   );
   if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
     return false;
   }
   if (!stillAsCounted) {
     // RW4: delete nothing, return to the prior user exactly as Cancel
     // does. `false` reports ReauthSuperseded -- it understates what ran
     // (a cancel), never overstates it.
     if (kDebugMode) {
       debugPrint(
         'lastKnownIdentityPersistenceProvider: different-user wipe '
         'declined: ${identity.userId}\'s pending work changed after it '
         'was counted',
       );
     }
     await cancelToPriorUserFor(identity);
     return false;
   }
   ```

   No await may be added between this block and `lifecycle.purgeSongCatalog`.

Commit: `fix(reauth): recount before the different-user wipe (RW2, RW4)`.

## Task 4 — no wipe while an import is running; never stuck (RW3; AC3, AC4, AC9)

The tracker's lifetime rules (spec RW3, "never stays running") are built and
unit-tested in Task 1. This task wires the guard and proves end to end that
a finished, failed or disposed import never blocks a later wipe.

**Test first** (`cross_user_local_first_leak_test.dart`, same group):

- **AC3:** A has one plan edit; the import is held before its first write;
  B signs in; the prompt names 1; confirm while the import is still held →
  nothing deleted, `sessionExpired` as A; release the import → A has 3
  pending songs and 1 plan edit, identity row A's.
- **AC4:** `seedPendingPlanningForA: false`; the import is held before its
  first write; B signs in → no prompt, nothing deleted, `sessionExpired` as
  A; release the import → A has 3 pending songs, identity row A's.

Both fail after Task 3 (the recount is `<= k` / 0, so the wipe runs).

- **AC9, the guard never sticks.** One test per end path. A has no pending
  work (`seedPendingPlanningForA: false`). The import ends in one of these
  ways:
  - the picker answers `null` (cancel);
  - every row write fails (the song-write gate throws for A instead of
    pausing; the run ends `ImportDone` with errors and writes nothing);
  - the controller is disposed mid-commit (held at the write gate, then
    `container.invalidate(chordProImportControllerProvider)` after the
    subscription is closed; release the gate and expect the run's future to
    fail with the debug `StateError`; A's rows written after the disposal
    are orphans, which is R10).

  After each, `container.read(importRunTrackerProvider).isRunning` is
  `false`. B then signs in, and the wipe runs: A's identity row is gone, B
  is `signedIn`, and a zero count means no prompt.

  The fixture's song-write gate gains a `failFor(userId)` mode for the second
  case.

**Implementation** (`lib/src/application/auth_providers.dart`):

1. In `lastKnownIdentityPersistenceProvider`, next to
   `final lifecycle = ref.read(localDataLifecycleProvider);`:
   `final importRuns = ref.read(importRunTrackerProvider);`
2. In `priorWorkStillAsCounted`, first line:
   `if (importRuns.isRunning) return false;` (check 1, before the recount),
   and extend its comment with RW3.
3. In `wipePriorAndProceedFor`, the decline condition becomes
   `if (!stillAsCounted || importRuns.isRunning) {` (check 2, synchronous,
   immediately before the deletion), and the debug message names both
   reasons.

Commit: `fix(reauth): no different-user wipe while an import runs (RW3)`.

## Task 5 — documentation

- `docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md`:
  - header line `Amended: 2026-10-11`;
  - section "Amendment 2026-10-11: the wipe deletes only counted work"
    (RW1–RW4, the rejected "ask again", the accepted count-not-identity
    comparison);
  - Testing bullets for the new tests.
- `docs/architecture/architecture.md`: one sentence in the reauth paragraph.
  The wipe recounts immediately before deleting and declines as a cancel,
  deleting nothing, if the prior user's pending work grew past the count its
  decision used or while a ChordPro import is running.
- Delete `docs/deferred/2026-10-09-reauth-wipe-uncounted-import-rows.md`.
- `docs/plans/2026-10-01-delivery-roadmap.md`: status note, this PR is done
  (number filled when opened), next S0 PR 2.
- `docs/deferred/2026-10-09-sign-out-guard-residuals.md`: no change unless
  the review adds residuals there.

Commit: `docs(reauth): ADR-029 amendment for the wipe recount`.

## After Task 5

1. One adversarial Opus (high) whole-diff review, with this question:
   "Show an event sequence that deletes pending work without confirmation
   or in a larger amount than confirmed, or in which one user's action
   affects another user's data. Consider any phase of the import, a user
   switch, reauth confirm and cancel, sign-out, the offline state, and a
   purge."
2. Exit criteria: only these block the PR:
   - pending work deleted without confirmation;
   - a cross-user effect;
   - a view with no way out.

   At most **one** fix round. Non-blocking findings found after it go to the
   spec's Residuals, not into another round.
3. If CI's dependency audit fails on an upstream version, fix it in a
   separate `chore(deps)` commit with a targeted
   `flutter pub upgrade <package>`.
4. Open the PR. Do not merge it.
