# Plan: An Import Run Writes Only Into the Catalog It Analysed Against

- Spec: `docs/specs/2026-10-11-import-run-ownership.md` (IR1–IR4, AC1–AC10)
- Branch: `fix/import-run-ownership` (from `main` at `22864df`)
- Execution: subagent-driven. Implementer Sonnet 5.5 (medium effort), task
  review Haiku 4.5. One adversarial Opus 5.5 (high) whole-diff review before
  the PR.

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
    "Intentional test changes" (the six hand-built awaiting states and the two
    direct `commitWithResolutions` calls, nothing else);
  - a code excerpt quoted here does not match the real file;
  - the full suite reports a Riverpod error during a provider build;
  - the change would need a new purge, a new `PurgeReason`, an ADR-035
    change, or a restructuring of the sign-out or reauth flows.
- Reviewers: do not review the commit trailer lines.

## Task 0 — red suite, spec, plan (done at the design gate)

`test/integration/cross_user_local_first_leak_test.dart`:

- the fixture gains `remote` (a `_RecordingSongRemoteRepository` behind
  `songMutationRemoteRepositoryProvider`), `resolveDuplicates` (calls
  `commitWithResolutions` exactly as `SongListScreen._resolveImportDuplicates`
  does), `syncSongs` (the real `SongMutationSyncController` pass), and
  `startImport(..., holdPickerUntil:)`;
- group "a duplicate resolution never writes into another user's catalog
  (R17)": tests a and b are `skip: 'red until Task 2'`; the two guards are
  green and stay enabled;
- group "an import picked during a sign-out ... (R10, R16)": one test,
  `skip: 'red until Task 2'`.

Run un-skipped on `main` they fail with `Expected: <0>  Actual: <2>`, and the
sync pass sends A's titles to `org-b` (and B's to `org-a`).

## Task 1 — a commit names the context of the run it resumes (IR1; AC5, AC9)

**Test first.**

`test/presentation/song_library/chordpro_import_controller_test.dart`: a new
group inside `main()` after "the run link on every end path", plus two helper
classes below `_SettableImportController`:

```dart
  group('a run is bound to the catalog context it analysed against '
      '(IR1, IR2)', () {
    // Non-const on purpose: an equal but distinct instance must not pass for
    // the run's own.
    final runContext = ActiveCatalogContext(
      userId: 'user-a',
      organizationId: 'org-a',
    );

    late ActiveCatalogContext? live;
    late ImportRunTracker tracker;
    late _RecordingImportService service;
    late _BoundRunController controller;
    Completer<void>? pickerOpen;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      live = runContext;
      tracker = ImportRunTracker();
      service = _RecordingImportService();
      controller = _BoundRunController(
        importService: service,
        contextReader: () => live,
        runTracker: tracker,
      );
      addTearDown(controller.dispose);
      pickerOpen = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_filePickerChannel, (call) async {
            await pickerOpen?.future;
            return [
              {
                'name': 'a.cho',
                'path': null,
                'bytes': Uint8List.fromList(utf8.encode('{title: A}')),
                'size': 10,
              },
            ];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_filePickerChannel, null),
      );
    });

    // What SongListScreen._resolveImportDuplicates hands the controller: the
    // awaiting state's successes and context, and one resolution per
    // duplicate.
    Future<void> answerDialog() {
      final awaiting =
          controller.currentState as ImportAwaitingDuplicateResolution;
      return controller.commitWithResolutions(
        context: awaiting.context,
        successes: awaiting.successes,
        resolvedDuplicates: [
          for (final duplicate in awaiting.result.duplicates)
            ResolvedDuplicate(
              duplicate: duplicate,
              resolution: DuplicateResolution.overwrite,
            ),
        ],
      );
    }

    test('IR1: the awaiting state carries the run\'s context and the commit '
        'passes the instance it was given, not an equal live one', () async {
      await controller.startImport();
      final awaiting = controller.currentState;
      expect(awaiting, isA<ImportAwaitingDuplicateResolution>());
      expect(
        (awaiting as ImportAwaitingDuplicateResolution).context,
        same(runContext),
      );

      live = ActiveCatalogContext(userId: 'user-a', organizationId: 'org-a');
      await answerDialog();

      expect(service.committedWith, hasLength(1));
      expect(service.committedWith.single, same(runContext));
      expect(controller.currentState, isA<ImportDone>());
    });
  });
```

and, after `_SettableImportController`:

```dart
/// Records what the controller hands the import service.
class _RecordingImportService implements ChordProImportService {
  bool reportDuplicates = true;
  final committedWith = <ActiveCatalogContext>[];

  @override
  Future<ImportBatchResult> analyse({
    required ActiveCatalogContext context,
    required List<ImportFileInput> files,
  }) async {
    return ImportBatchResult(
      successes: const [
        ImportSuccess(
          title: 'New',
          source: '{title: New}',
          filename: 'new.cho',
        ),
      ],
      duplicates: reportDuplicates
          ? const [
              ImportDuplicate(
                filename: 'old.cho',
                incomingSource: '{title: Old}',
                incomingTitle: 'Old',
                existingSongId: 'song-old',
                existingTitle: 'Old',
              ),
            ]
          : const [],
      errors: const [],
    );
  }

  @override
  Future<ImportBatchResult> commitImport({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) async {
    committedWith.add(context);
    return const ImportBatchResult(successes: [], duplicates: [], errors: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A real controller over a mutable live context, state readable.
class _BoundRunController extends ChordProImportController {
  _BoundRunController({
    required super.importService,
    required super.contextReader,
    super.runTracker,
  });

  ChordProImportState get currentState => state;
}
```

`test/presentation/song_library/song_list_screen_test.dart`: one widget test
(AC9) next to "sign out is unavailable while a ChordPro import runs (SO7)",
and a recording subclass next to `_StatefulImportController`:

```dart
  testWidgets('the duplicate dialog hands the awaiting run\'s own context to '
      'the commit (IR1)', (tester) async {
    const runContext = ActiveCatalogContext(
      userId: 'user-9',
      organizationId: 'org-9',
    );
    final importController = _CommitRecordingImportController();
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        extraOverrides: [
          chordProImportControllerProvider.overrideWith(
            (_) => importController,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    importController.setImportState(
      const ImportAwaitingDuplicateResolution(
        ImportBatchResult(
          successes: [],
          duplicates: [
            ImportDuplicate(
              filename: 'old.cho',
              incomingSource: '{title: Old}',
              incomingTitle: 'Old',
              existingSongId: 'song-old',
              existingTitle: 'Old',
            ),
          ],
          errors: [],
        ),
        [],
        context: runContext,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songImportDuplicateConfirmAction));
    await tester.pumpAndSettle();

    expect(importController.committedWith, [runContext]);
  });
```

```dart
/// Records the context a commit was handed instead of writing.
class _CommitRecordingImportController extends _StatefulImportController {
  final committedWith = <ActiveCatalogContext>[];

  @override
  Future<void> commitWithResolutions({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) async {
    committedWith.add(context);
  }
}
```

Expected before the change: both new tests fail to compile (`context` is not
a field of `ImportAwaitingDuplicateResolution` nor a parameter of
`commitWithResolutions`), which is the stated reason.

**Implementation.**

`lib/src/presentation/song_library/chordpro_import_controller.dart`:

1. The awaiting state:

   ```dart
   class ImportAwaitingDuplicateResolution extends ChordProImportState {
     const ImportAwaitingDuplicateResolution(
       this.result,
       this.successes, {
       required this.context,
     });

     final ImportBatchResult result;
     final List<ImportSuccess> successes;

     /// IR1 (docs/specs/2026-10-11-import-run-ownership.md): the catalog
     /// context the run analysed these files against. The commit that resumes
     /// the run is given this context and writes into it and nothing else.
     final ActiveCatalogContext context;
   }
   ```

2. In `_runImport`, replace

   ```dart
       if (analysisResult.duplicates.isNotEmpty) {
         state = ImportAwaitingDuplicateResolution(
           analysisResult,
           analysisResult.successes,
         );
         return;
       }
   ```

   with the same call plus `context: context,`.

3. `commitWithResolutions`: replace

   ```dart
     Future<void> commitWithResolutions({
       required List<ImportSuccess> successes,
       required List<ResolvedDuplicate> resolvedDuplicates,
     }) async {
       // One run at a time, as startImport.
       if (isImportRunning(state)) {
         return;
       }
       try {
         final context = _contextReader();
         if (context == null) {
           state = const ImportFailed(AppStrings.songImportNoContextMessage);
           return;
         }
         _runUserId = context.userId;
         await _commit(
           context: context,
           successes: successes,
           resolvedDuplicates: resolvedDuplicates,
         );
       } finally {
         _endRun();
       }
     }
   ```

   with

   ```dart
     /// IR1: [context] is the context of the run whose duplicates were
     /// resolved (the awaiting state's), never read from the live provider
     /// here; the live context is only compared against it, in [_commit].
     Future<void> commitWithResolutions({
       required ActiveCatalogContext context,
       required List<ImportSuccess> successes,
       required List<ResolvedDuplicate> resolvedDuplicates,
     }) async {
       // One run at a time, as startImport.
       if (isImportRunning(state)) {
         return;
       }
       try {
         _runUserId = context.userId;
         await _commit(
           context: context,
           successes: successes,
           resolvedDuplicates: resolvedDuplicates,
         );
       } finally {
         _endRun();
       }
     }
   ```

`lib/src/presentation/song_library/song_list_screen.dart`:

4. In the listener, the awaiting case and the host method (the binding is
   named `runContext`: `context` is the `BuildContext` there):

   ```dart
           case ImportAwaitingDuplicateResolution(
             :final result,
             :final successes,
             context: final runContext,
           ):
             unawaited(
               _resolveImportDuplicates(
                 context,
                 ref,
                 result,
                 successes,
                 runContext,
               ),
             );
   ```

   ```dart
     Future<void> _resolveImportDuplicates(
       BuildContext context,
       WidgetRef ref,
       ImportBatchResult result,
       List<ImportSuccess> successes,
       ActiveCatalogContext runContext,
     ) async {
       ...
       await ref
           .read(chordProImportControllerProvider.notifier)
           .commitWithResolutions(
             context: runContext,
             successes: successes,
             resolvedDuplicates: resolved,
           );
     }
   ```

   plus the import of `active_catalog_context.dart`.

**Existing tests (the spec's intentional changes, mechanical):**

5. The six hand-built awaiting states gain
   `context: <a const ActiveCatalogContext>` (a file-level `const` per file):
   `test/presentation/auth/sign_out_flow_test.dart:150`,
   `test/presentation/song_library/chordpro_import_controller_test.dart` lines
   40, 375, 407, 416, `test/presentation/song_library/song_list_screen_test.dart:1061`.
6. The two direct `commitWithResolutions` calls in
   `chordpro_import_controller_test.dart` (`startCommit`, and "is refused
   while a commit is running") gain
   `context: const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1')`,
   the context their `activeCatalogContextProvider` override returns.
7. `test/integration/cross_user_local_first_leak_test.dart`, fixture
   `resolveDuplicates`: add `context: awaiting.context` to the
   `commitWithResolutions` call (the three red tests stay skipped until
   Task 2).

**Verify:** the new tests pass; the three integration tests stay skipped (IR2
is Task 2). Full suite and analyzer clean. Commit: `fix(import): a duplicate
resolution names the context of its run (IR1)`.

## Task 2 — a commit starts only while its context is active (IR2; AC1–AC3, AC6–AC8)

**Test first** (same new group in `chordpro_import_controller_test.dart`):

```dart
    final changedContexts = <String, ActiveCatalogContext?>{
      'another user': ActiveCatalogContext(
        userId: 'user-b',
        organizationId: 'org-b',
      ),
      'the same user, another organization': ActiveCatalogContext(
        userId: 'user-a',
        organizationId: 'org-2',
      ),
      'no context': null,
    };
    for (final entry in changedContexts.entries) {
      test('IR2: ${entry.key} while the dialog was open writes nothing and '
          'fails the run', () async {
        await controller.startImport();
        live = entry.value;

        await answerDialog();

        expect(service.committedWith, isEmpty);
        expect(
          controller.currentState,
          isA<ImportFailed>().having(
            (s) => s.message,
            'message',
            AppStrings.songImportContextChangedMessage,
          ),
        );
        expect(tracker.isRunning, isFalse);
      });
    }

    test('IR2: a run without duplicates whose context changed while the '
        'picker was open is refused at its commit', () async {
      service.reportDuplicates = false;
      pickerOpen = Completer<void>();
      final run = controller.startImport();
      await pumpEventQueue();
      expect(controller.currentState, isA<ImportPicking>());
      expect(tracker.isRunningFor('user-a'), isTrue);

      live = ActiveCatalogContext(userId: 'user-b', organizationId: 'org-b');
      pickerOpen!.complete();
      await run;

      expect(service.committedWith, isEmpty);
      expect(
        controller.currentState,
        isA<ImportFailed>().having(
          (s) => s.message,
          'message',
          AppStrings.songImportContextChangedMessage,
        ),
      );
      expect(tracker.isRunning, isFalse);
    });

    test('IR2: a refused commit leaves the controller usable', () async {
      await controller.startImport();
      live = ActiveCatalogContext(userId: 'user-b', organizationId: 'org-b');
      await answerDialog();
      expect(controller.currentState, isA<ImportFailed>());

      live = runContext;
      await controller.startImport();

      expect(controller.currentState, isA<ImportAwaitingDuplicateResolution>());
      expect(tracker.isRunning, isFalse);
    });
```

Watch them fail: `AppStrings.songImportContextChangedMessage` does not exist
(compile error; add the constant first, then the tests fail because the
service is called with `runContext`).

**Implementation:**

1. `lib/src/shared/app_strings.dart`, after `songImportNoContextMessage`:

   ```dart
     static const songImportContextChangedMessage =
         'The account or workspace changed, so the import was stopped and '
         'nothing was imported. Start the import again.';
   ```

2. `chordpro_import_controller.dart`, at the start of `_commit`, replace

   ```dart
       state = const ImportCommitting();

       final skippedCount = resolvedDuplicates
   ```

   with

   ```dart
       // IR2 (docs/specs/2026-10-11-import-run-ownership.md): the run writes
       // only into the catalog it analysed against, and only while that is
       // still the active one. The user, the organization or the context
       // itself may have changed while the dialog or the picker was open
       // (R17, R16). Nothing is written; the state becomes ImportFailed, so
       // a run that was in a running phase releases the tracker and SO7's
       // link through the state setter as for any other end.
       if (_contextReader() != context) {
         state = const ImportFailed(AppStrings.songImportContextChangedMessage);
         return;
       }
       state = const ImportCommitting();

       final skippedCount = resolvedDuplicates
   ```

3. `test/integration/cross_user_local_first_leak_test.dart`: remove the three
   `skip: 'red until Task 2'` markers.

**Mutation checks (run by the implementer, results in the report; revert
after each):**

- Delete the `if (_contextReader() != context)` block: the three
  integration tests and the five IR2 unit tests fail (`committedWith`
  non-empty / rows exist).
- In `commitWithResolutions`, ignore the `context` argument and use
  `_contextReader()` instead (with a `!` or an early return on null): integration
  tests a and b and the IR1 unit test fail (the guard then compares the live
  context with itself).
- In the host, pass `ref.read(activeCatalogContextProvider)` instead of the
  awaiting state's context: the AC9 widget test fails.

**Verify:** all of `cross_user_local_first_leak_test.dart` green, including the
three formerly skipped tests and the two guards; full suite and analyzer
clean. Commit: `fix(import): a commit starts only while its catalog context is
active (IR2, R17, R16)`.

## Task 3 — documentation

- ADR-037: append the amendment "Import runs hold their context
  (2026-10-11)": the run's context is captured at its start and travels with
  the awaiting state (IR1); a commit starts only while it is still the active
  context (IR2); why not per row (IR3, RW3's AC3/AC4); no purge, no
  `PurgeReason`, ADR-035 unchanged. Link the spec.
- `docs/architecture/architecture.md`: in the offline-authenticated paragraph,
  after the sentence about a ChordPro import writing the prior user's work,
  add: an import run is bound to the catalog context it analysed against, the
  commit is given that context as an argument and `commitWithResolutions`
  never reads the live context, and `_commit` starts only while the live
  context still equals it (ADR-037 amendment 2026-10-11).
- `docs/testing/testing-strategy.md`, "Cross-user ownership pattern": add the
  rule "answer a duplicate dialog the way the host does
  (`fixture.resolveDuplicates`), after the user changed, and assert on the
  pending rows and on what a sync pass sends".
- Confirm `docs/deferred/2026-10-09-sign-out-guard-residuals.md` and the
  roadmap note match the spec (both were edited at the design gate).
- The committed `graphify-out/` stays as it is (stale since `d3c00b0`; a
  refresh is its own PR).

Verify: markdown only; full suite not required, but run `flutter analyze`
once at the end of the PR anyway. Commit: `docs: import run ownership (ADR-037
amendment, architecture, testing strategy)`.

## Task 4 — a run parks only while its context is active (IR2, second check point; AC10)

Added after the adversarial review, at the user's request: the duplicate dialog
could also OPEN after the user switch (the OS picker or the analysis straddled
the auth edge). Never opening needs no pop, so the R9 argument that keeps the
"outlives the switch" shape deferred does not apply.

**Test first.**

`test/presentation/song_library/chordpro_import_controller_test.dart`, in the
group "a run is bound to the catalog context it analysed against (IR1, IR2)":

```dart
    test('IR2: a run whose context changed while the picker was open never '
        'reaches the dialog', () async {
      final seen = <ChordProImportState>[];
      controller.addListener(seen.add, fireImmediately: false);
      pickerOpen = Completer<void>();
      final run = controller.startImport();
      await pumpEventQueue();
      expect(controller.currentState, isA<ImportPicking>());

      live = ActiveCatalogContext(userId: 'user-b', organizationId: 'org-b');
      pickerOpen!.complete();
      await run;

      expect(seen.whereType<ImportAwaitingDuplicateResolution>(), isEmpty);
      expect(
        controller.currentState,
        isA<ImportFailed>().having(
          (s) => s.message,
          'message',
          AppStrings.songImportContextChangedMessage,
        ),
      );
      expect(service.committedWith, isEmpty);
      expect(tracker.isRunning, isFalse);
    });
```

(`service.reportDuplicates` defaults to `true`, so the analysis finds a
duplicate and, without the new check, the run parks.)

`test/integration/cross_user_local_first_leak_test.dart`, two tests in the
group "a duplicate resolution never writes into another user's catalog (R17)"
(the probe of the review is the first one):

- **picker variant.** Fixture as in test b (`seedSongsForA`, `seedPlanningForA`,
  `seedSongsForB`, `lookupAnswersFor: {_userB}`; A has unsynced work, so B's
  sign-in asks and B's context is live). Cold start as A. Add a listener
  (`fixture.container.listen(chordProImportControllerProvider, (_, next) =>
  seen.add(next))`) before starting. `fixture.startImport(incomingForA,
  holdPickerUntil: pickerAnswer.future)`; expect `ImportPicking`. `signInAs(B)`;
  expect the prompt pending and `catalogContextUserId == _userB`. Complete the
  picker, await the run, `_settle()`. Expect: no `ImportAwaitingDuplicateResolution`
  in `seen`, `importState` is `ImportFailed`, `pendingSongCount` is 0 for A and B.
- **analysis variant.** Same fixture and listener. `fixture.catalogReadGate.hold()`
  after the cold start, then `fixture.startImport(incomingForA)`; expect
  `ImportAnalysing` (the run is blocked in the analysis's read; if the gate does
  not hold the read, STOP and report). `signInAs(B)`, `catalogReadGate.release()`,
  await the run, `_settle()`. Same expectations.

Expected before the change: all three fail (the run enters
`ImportAwaitingDuplicateResolution`).

**Implementation** (`lib/src/presentation/song_library/chordpro_import_controller.dart`,
`_runImport`): directly after the `try/catch` that builds `analysisResult` and
before `if (analysisResult.duplicates.isNotEmpty)`, add

```dart
    // IR2 (docs/specs/2026-10-11-import-run-ownership.md): a run parks at the
    // dialog, or ends in the summary, only while it is still in the catalog it
    // analysed against. The picker or the analysis may have straddled a user
    // switch, and the dialog would list this run's titles to whoever is
    // current now. Nothing is written; _commit checks again before it writes.
    if (_contextReader() != context) {
      state = const ImportFailed(AppStrings.songImportContextChangedMessage);
      return;
    }
```

**Mutation check (report the result; revert after):** delete this block: the
unit test and both integration tests fail; `_commit`'s own check stays.

**Verify:** full `flutter test` and `flutter analyze` clean. Commit (code and
tests only): `fix(import): a run parks at the dialog only while its context is
active (IR2, R18 second shape)`.

**Documentation (second commit):** ADR-037 amendment, the IR2 bullet: add one
sentence that the same comparison runs where a run parks at the dialog;
`architecture.md`: in the one inserted sentence say that a run parks at the
dialog, and `_commit` starts, only while the live context still equals the run's;
`docs/testing/testing-strategy.md`: the bullet names `catalogReadGate` (pause the
analysis) next to `holdPickerUntil`; `docs/deferred/2026-10-09-sign-out-guard-residuals.md`:
remove the paragraph "A second shape" from R18 (the already open dialog stays),
and add to the "Closed since this entry was written" note that R18's second
shape was closed in the same PR. Commit: `docs(import): the dialog never opens
for a changed context (R18 second shape)`.

## Final review and PR

- One adversarial Opus 5.5 (high) whole-diff review with this question:
  "Show an event sequence (any import phase, the duplicate dialog, a user
  switch, reauth confirm and cancel, sign-out, offline state) in which one
  user's import writes into another user's catalog or organization, or in
  which the import gets stuck or leaves a view with no way out."
- Exit criterion: only a cross-user write or view, unconfirmed data loss, and
  a view with no way out block. At most ONE fix round; everything else goes to
  `docs/deferred/`.
- Open the PR; do not merge. If CI's dependency audit fails because of an
  upstream version, fix it in a separate `chore(deps)` commit.
