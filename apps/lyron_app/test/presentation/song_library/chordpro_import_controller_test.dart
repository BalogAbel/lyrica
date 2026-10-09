import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';

/// SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): an import run
/// writes pending work in the background, so its state must stay readable by
/// the sign-out guard for as long as the run lasts.
void main() {
  late Completer<ImportBatchResult> commit;
  late ProviderContainer container;

  const success = ImportSuccess(
    title: 'Egy út',
    source: '{title: Egy út}',
    filename: 'egy-ut.cho',
  );

  setUp(() {
    commit = Completer<ImportBatchResult>();
    container = ProviderContainer(
      overrides: [
        chordProImportServiceProvider.overrideWithValue(
          _CommittingImportService(commit.future),
        ),
        activeCatalogContextProvider.overrideWithValue(
          const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  const emptyResult = ImportBatchResult(
    successes: [],
    duplicates: [],
    errors: [],
  );

  test('a running commit keeps the provider alive after its last listener '
      'is gone, and releases it when the run ends', () async {
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

    // The song list was replaced: nobody listens any more.
    subscription.close();
    await container.pump();
    expect(container.exists(chordProImportControllerProvider), isTrue);
    expect(
      container.read(chordProImportControllerProvider),
      isA<ImportCommitting>(),
    );

    commit.complete(emptyResult);
    await committing;
    await container.pump();
    expect(container.exists(chordProImportControllerProvider), isFalse);
  });

  test('startImport is refused while a run is in progress', () async {
    final subscription = container.listen(
      chordProImportControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final notifier = container.read(chordProImportControllerProvider.notifier);
    final committing = notifier.commitWithResolutions(
      successes: const [success],
      resolvedDuplicates: const [],
    );
    await container.pump();
    expect(
      container.read(chordProImportControllerProvider),
      isA<ImportCommitting>(),
    );

    await notifier.startImport();

    expect(
      container.read(chordProImportControllerProvider),
      isA<ImportCommitting>(),
    );
    commit.complete(emptyResult);
    await committing;
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
