import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';

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

    setUp(() {
      commit = Completer<ImportBatchResult>();
      container = ProviderContainer(
        overrides: [
          chordProImportServiceProvider.overrideWithValue(
            _CommittingImportService(commit.future),
          ),
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
  });

  group('the run link on every end path', () {
    late ProviderContainer container;
    late _SettableImportController controller;
    late ProviderSubscription<_SettableImportController> subscription;

    final probeProvider = Provider.autoDispose<_SettableImportController>((
      ref,
    ) {
      final created = _SettableImportController(keepAlive: ref.keepAlive);
      ref.onDispose(created.dispose);
      return created;
    });

    setUp(() {
      container = ProviderContainer();
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
          subscription.close();
          await container.pump();
          expect(container.exists(probeProvider), isTrue);

          controller.setImportState(end.value);
          await container.pump();
          expect(container.exists(probeProvider), isFalse);
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
    });
  });
}

class _CommittingImportService implements ChordProImportService {
  _CommittingImportService(this._commit);

  final Future<ImportBatchResult> _commit;

  @override
  Future<ImportBatchResult> commitImport({
    required ActiveCatalogContext context,
    required List<ImportSuccess> successes,
    required List<ResolvedDuplicate> resolvedDuplicates,
  }) => _commit;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChordProImportService implements ChordProImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An import controller whose state the test sets directly.
class _SettableImportController extends ChordProImportController {
  _SettableImportController({required KeepAliveLink Function() keepAlive})
    : super(
        importService: _FakeChordProImportService(),
        contextReader: () => null,
        keepAlive: keepAlive,
      );

  void setImportState(ChordProImportState next) => state = next;

  ChordProImportState get currentState => state;
}
