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
      const ImportAwaitingDuplicateResolution(emptyResult, []): false,
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

      subscription.close();
      commit.complete(emptyResult);
      await committing;
      await container.pump();

      expect(container.read(importRunTrackerProvider).isRunning, isFalse);
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
          const ImportAwaitingDuplicateResolution(emptyResult, []),
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
        const ImportAwaitingDuplicateResolution(emptyResult, []),
      );
      await container.pump();

      expect(container.exists(probeProvider), isFalse);
    });

    test('reset() from AwaitingDuplicateResolution returns to idle', () {
      controller.setImportState(
        const ImportAwaitingDuplicateResolution(emptyResult, []),
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
        throwsA(anything),
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
