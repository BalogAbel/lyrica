import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/application/song_library/import_run_tracker.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _testContext = ActiveCatalogContext(
  userId: 'user-1',
  organizationId: 'org-1',
);

/// SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): a running
/// import writes pending work in the background, so the state the sign-out
/// guard reads must stay truthful for as long as the run lasts, and the run
/// must always release the provider when it ends.
void main() {
  const success = ImportSuccess(
    title: 'Egy út',
    source: '{title: Egy út}',
    filename: 'egy-ut.cho',
  );
  const emptyResult = ImportBatchResult(
    successes: [],
    duplicates: [],
    errors: [],
  );

  group('isImportRunning', () {
    // Running: a phase that will write, or end, without further user input.
    // Awaiting duplicates writes nothing until the user resolves them in the
    // modal dialog; with no dialog nothing can resolve them.
    final expected = <ChordProImportState, bool>{
      const ImportIdle(): false,
      const ImportPicking(): true,
      const ImportAnalysing(): true,
      const ImportAwaitingDuplicateResolution(
        emptyResult,
        [],
        context: _testContext,
      ): false,
      const ImportCommitting(): true,
      const ImportDone(result: emptyResult, skippedCount: 0): false,
      const ImportFailed('failed'): false,
    };

    test('covers every state of the sealed hierarchy', () {
      expect(expected, hasLength(7));
    });

    for (final entry in expected.entries) {
      test('${entry.key.runtimeType} is ${entry.value}', () {
        expect(isImportRunning(entry.key), entry.value);
      });
    }
  });

  group('a commit through the real provider', () {
    late Completer<ImportBatchResult> commit;
    late ProviderContainer container;
    late _CommittingImportService commitService;

    setUp(() {
      commit = Completer<ImportBatchResult>();
      commitService = _CommittingImportService(commit.future);
      container = ProviderContainer(
        overrides: [
          chordProImportServiceProvider.overrideWithValue(commitService),
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> endsWith(
      void Function() end,
      Future<void> committing,
      ProviderSubscription<ChordProImportState> subscription,
    ) async {
      // The song list was replaced: nobody listens any more.
      subscription.close();
      await container.pump();
      expect(container.exists(chordProImportControllerProvider), isTrue);
      expect(
        container.read(chordProImportControllerProvider),
        isA<ImportCommitting>(),
      );

      end();
      await committing;
      await container.pump();
      expect(container.exists(chordProImportControllerProvider), isFalse);
    }

    Future<void> startCommit(
      void Function(
        Future<void> committing,
        ProviderSubscription<ChordProImportState> subscription,
      )
      body,
    ) async {
      final subscription = container.listen(
        chordProImportControllerProvider,
        (_, _) {},
      );
      final committing = container
          .read(chordProImportControllerProvider.notifier)
          .commitWithResolutions(
            context: _testContext,
            successes: const [success],
            resolvedDuplicates: const [],
          );
      await container.pump();
      expect(
        container.read(chordProImportControllerProvider),
        isA<ImportCommitting>(),
      );
      body(committing, subscription);
    }

    test('keeps the provider alive after its last listener is gone and '
        'releases it when the commit is done', () async {
      late Future<void> committing;
      late ProviderSubscription<ChordProImportState> subscription;
      await startCommit((c, s) {
        committing = c;
        subscription = s;
      });
      await endsWith(
        () => commit.complete(emptyResult),
        committing,
        subscription,
      );
    });

    test('releases the provider when the commit fails', () async {
      late Future<void> committing;
      late ProviderSubscription<ChordProImportState> subscription;
      await startCommit((c, s) {
        committing = c;
        subscription = s;
      });
      await endsWith(
        () => commit.completeError(StateError('write failed')),
        committing,
        subscription,
      );
    });

    test('reset() is refused while the commit is writing', () async {
      late Future<void> committing;
      late ProviderSubscription<ChordProImportState> subscription;
      await startCommit((c, s) {
        committing = c;
        subscription = s;
      });

      container.read(chordProImportControllerProvider.notifier).reset();

      expect(
        container.read(chordProImportControllerProvider),
        isA<ImportCommitting>(),
      );
      await endsWith(
        () => commit.complete(emptyResult),
        committing,
        subscription,
      );
    });

    test('startImport is refused while the commit is writing', () async {
      late Future<void> committing;
      late ProviderSubscription<ChordProImportState> subscription;
      await startCommit((c, s) {
        committing = c;
        subscription = s;
      });

      await container
          .read(chordProImportControllerProvider.notifier)
          .startImport();

      expect(
        container.read(chordProImportControllerProvider),
        isA<ImportCommitting>(),
      );
      await endsWith(
        () => commit.complete(emptyResult),
        committing,
        subscription,
      );
    });

    test('reports the commit to the app-scoped tracker', () async {
      late Future<void> committing;
      late ProviderSubscription<ChordProImportState> subscription;
      await startCommit((c, s) {
        committing = c;
        subscription = s;
      });
      expect(container.read(importRunTrackerProvider).isRunning, isTrue);
      final tracker = container.read(importRunTrackerProvider);
      expect(tracker.isRunningFor('user-1'), isTrue);
      expect(tracker.isRunningFor('user-2'), isFalse);

      subscription.close();
      commit.complete(emptyResult);
      await committing;
      await container.pump();

      expect(container.read(importRunTrackerProvider).isRunning, isFalse);
      expect(tracker.isRunningFor('user-1'), isFalse);
      expect(tracker.isRunningFor('user-2'), isFalse);
    });

    test('a failed commit leaves the tracker idle', () async {
      late Future<void> committing;
      late ProviderSubscription<ChordProImportState> subscription;
      await startCommit((c, s) {
        committing = c;
        subscription = s;
      });
      expect(container.read(importRunTrackerProvider).isRunning, isTrue);

      commit.completeError(StateError('boom'));
      await committing;

      expect(
        container.read(chordProImportControllerProvider),
        isA<ImportFailed>(),
      );
      expect(container.read(importRunTrackerProvider).isRunning, isFalse);
      subscription.close();
    });

    test(
      'commitWithResolutions is refused while a commit is running',
      () async {
        late Future<void> committing;
        late ProviderSubscription<ChordProImportState> subscription;
        await startCommit((c, s) {
          committing = c;
          subscription = s;
        });

        await container
            .read(chordProImportControllerProvider.notifier)
            .commitWithResolutions(
              context: _testContext,
              successes: const [success],
              resolvedDuplicates: const [],
            );

        expect(
          container.read(chordProImportControllerProvider),
          isA<ImportCommitting>(),
        );
        expect(commitService.commitCalls, 1);

        commit.complete(emptyResult);
        await committing;
        subscription.close();
      },
    );

    group('startImport', () {
      void mockPicker(Future<Object?> Function() answer) {
        TestWidgetsFlutterBinding.ensureInitialized();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_filePickerChannel, (call) => answer());
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(_filePickerChannel, null),
        );
      }

      test('a picker cancel leaves the tracker idle', () async {
        mockPicker(() async => null);
        final subscription = container.listen(
          chordProImportControllerProvider,
          (_, _) {},
        );

        await container
            .read(chordProImportControllerProvider.notifier)
            .startImport();

        expect(
          container.read(chordProImportControllerProvider),
          isA<ImportIdle>(),
        );
        expect(container.read(importRunTrackerProvider).isRunning, isFalse);
        subscription.close();
      });

      test('an exception nothing caught ends the run as failed', () async {
        mockPicker(
          () async => [
            {
              'name': 'a.cho',
              'path': null,
              'bytes': Uint8List.fromList(utf8.encode('{title: A}')),
              'size': 10,
            },
          ],
        );
        final subscription = container.listen(
          chordProImportControllerProvider,
          (_, _) {},
        );

        await container
            .read(chordProImportControllerProvider.notifier)
            .startImport()
            .then<void>(
              (_) => fail('the escaped exception must fail the future'),
              onError: (Object _) {},
            );

        expect(
          container.read(chordProImportControllerProvider),
          isA<ImportFailed>().having(
            (s) => s.message,
            'message',
            AppStrings.songImportInterruptedMessage,
          ),
        );
        expect(container.read(importRunTrackerProvider).isRunning, isFalse);
        subscription.close();
        await container.pump();
        expect(container.exists(chordProImportControllerProvider), isFalse);
      });
    });
  });

  group('the run link on every end path', () {
    late ProviderContainer container;
    late _SettableImportController controller;
    late ProviderSubscription<_SettableImportController> subscription;
    late ImportRunTracker tracker;

    final probeProvider = Provider.autoDispose<_SettableImportController>((
      ref,
    ) {
      final created = _SettableImportController(
        keepAlive: ref.keepAlive,
        runTracker: ref.read(_trackerProvider),
      );
      ref.onDispose(created.dispose);
      return created;
    });

    setUp(() {
      tracker = ImportRunTracker();
      container = ProviderContainer(
        overrides: [_trackerProvider.overrideWithValue(tracker)],
      );
      addTearDown(container.dispose);
      subscription = container.listen(probeProvider, (_, _) {});
      controller = subscription.read();
    });

    final runningStates = <String, ChordProImportState>{
      'ImportPicking': const ImportPicking(),
      'ImportAnalysing': const ImportAnalysing(),
      'ImportCommitting': const ImportCommitting(),
    };
    final endStates = <String, ChordProImportState>{
      'ImportIdle': const ImportIdle(),
      'ImportAwaitingDuplicateResolution':
          const ImportAwaitingDuplicateResolution(
            emptyResult,
            [],
            context: _testContext,
          ),
      'ImportDone': const ImportDone(result: emptyResult, skippedCount: 0),
      'ImportFailed': const ImportFailed('failed'),
    };

    for (final running in runningStates.entries) {
      for (final end in endStates.entries) {
        test('${running.key} -> ${end.key} releases the provider', () async {
          controller.setImportState(running.value);
          expect(tracker.isRunning, isTrue);
          subscription.close();
          await container.pump();
          expect(container.exists(probeProvider), isTrue);

          controller.setImportState(end.value);
          await container.pump();
          expect(container.exists(probeProvider), isFalse);
          expect(tracker.isRunning, isFalse);
        });
      }
    }

    test('an awaiting-duplicates state with no presenter does not hold the '
        'provider', () async {
      // The song list was replaced while the analysis ran; the analysis ends
      // in AwaitingDuplicateResolution and nothing will ever resolve it.
      controller.setImportState(const ImportAnalysing());
      subscription.close();
      await container.pump();
      expect(container.exists(probeProvider), isTrue);

      controller.setImportState(
        const ImportAwaitingDuplicateResolution(
          emptyResult,
          [],
          context: _testContext,
        ),
      );
      await container.pump();

      expect(container.exists(probeProvider), isFalse);
    });

    test('reset() from AwaitingDuplicateResolution returns to idle', () {
      controller.setImportState(
        const ImportAwaitingDuplicateResolution(
          emptyResult,
          [],
          context: _testContext,
        ),
      );

      controller.reset();

      expect(controller.currentState, isA<ImportIdle>());
    });

    test('a listener that throws does not skip the release', () async {
      controller.onError = (_, _) {};
      controller.addListener((next) {
        if (next is ImportDone) throw StateError('listener failed');
      }, fireImmediately: false);
      controller.setImportState(const ImportCommitting());
      subscription.close();
      await container.pump();
      expect(container.exists(probeProvider), isTrue);

      expect(
        () => controller.setImportState(
          const ImportDone(result: emptyResult, skippedCount: 0),
        ),
        throwsA(anything),
      );
      await container.pump();

      expect(container.exists(probeProvider), isFalse);
      expect(tracker.isRunning, isFalse);
    });

    test('a disposed controller is not running and never reports running '
        'again', () async {
      controller.setImportState(const ImportCommitting());
      expect(tracker.isRunning, isTrue);

      subscription.close();
      container.invalidate(probeProvider);
      await container.pump();
      expect(tracker.isRunning, isFalse);

      expect(
        () => controller.setImportState(const ImportAnalysing()),
        throwsStateError,
      );
      expect(tracker.isRunning, isFalse);
    });

    test('is keyed per instance: one controller going idle does not hide '
        'another that is running', () {
      final a = _SettableImportController(runTracker: tracker);
      final b = _SettableImportController(runTracker: tracker);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      a.setImportState(const ImportCommitting());
      b.setImportState(const ImportAnalysing());
      b.setImportState(const ImportIdle());
      expect(tracker.isRunning, isTrue);

      a.setImportState(const ImportDone(result: emptyResult, skippedCount: 0));
      expect(tracker.isRunning, isFalse);
    });
  });

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

    final changedContexts = <String, ActiveCatalogContext?>{
      'another user': ActiveCatalogContext(
        userId: 'user-b',
        organizationId: 'org-b',
      ),
      'the same user, another organization': ActiveCatalogContext(
        userId: 'user-a',
        organizationId: 'org-2',
      ),
      'another user, same organization': ActiveCatalogContext(
        userId: 'user-b',
        organizationId: 'org-a',
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
  });
}

final _trackerProvider = Provider<ImportRunTracker>((ref) {
  throw UnimplementedError('overridden by the test');
});

const _filePickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

/// An [ImportBatchResult] whose analysis outcome cannot be read, so the
/// controller throws outside every catch it has.
class _ThrowingResult implements ImportBatchResult {
  @override
  List<ImportSuccess> get successes => const [];

  @override
  List<ImportError> get errors => const [];

  @override
  List<ImportDuplicate> get duplicates => throw StateError('unreadable');

  @override
  bool get hasIssues => throw StateError('unreadable');
}

class _CommittingImportService implements ChordProImportService {
  _CommittingImportService(this._commit);

  final Future<ImportBatchResult> _commit;
  int commitCalls = 0;

  @override
  Future<ImportBatchResult> analyse({
    required ActiveCatalogContext context,
    required List<ImportFileInput> files,
  }) async => _ThrowingResult();

  @override
  Future<ImportBatchResult> commitImport({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) {
    commitCalls++;
    return _commit;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChordProImportService implements ChordProImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An import controller whose state the test sets directly.
class _SettableImportController extends ChordProImportController {
  _SettableImportController({super.keepAlive, super.runTracker})
    : super(
        importService: _FakeChordProImportService(),
        contextReader: () => null,
      );

  void setImportState(ChordProImportState next) => state = next;

  ChordProImportState get currentState => state;
}

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
