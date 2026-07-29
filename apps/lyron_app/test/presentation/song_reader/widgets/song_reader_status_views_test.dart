import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/presentation/song_reader/widgets/song_reader_status_views.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _emptyCatalogState = CatalogSnapshotState(
  context: null,
  connectionStatus: CatalogConnectionStatus.unavailable,
  refreshStatus: CatalogRefreshStatus.idle,
  sessionStatus: CatalogSessionStatus.verified,
  hasCachedCatalog: false,
);

SongMutationRecord _mutationRecord({
  required SongSyncStatus syncStatus,
  SongMutationSyncErrorCode? errorCode,
}) {
  return SongMutationRecord(
    id: 'song-1',
    organizationId: 'org-1',
    slug: 'song-1',
    title: 'Fixture',
    chordproSource: '',
    version: 1,
    baseVersion: 1,
    syncStatus: syncStatus,
    errorCode: errorCode,
  );
}

void main() {
  group('canShowScopedDeletedTombstone', () {
    test('is true when the catalog context is resolved', () {
      expect(
        canShowScopedDeletedTombstone(
          catalogState: _emptyCatalogState,
          mutationRecord: null,
        ),
        isFalse,
      );
    });

    test('is true when the mutation record is a remote-deleted conflict', () {
      final record = _mutationRecord(
        syncStatus: SongSyncStatus.conflict,
        errorCode: SongMutationSyncErrorCode.remoteDeleted,
      );

      expect(
        canShowScopedDeletedTombstone(
          catalogState: _emptyCatalogState,
          mutationRecord: record,
        ),
        isTrue,
      );
    });

    test(
      'is false for a conflict record whose error is not remote-deleted',
      () {
        final record = _mutationRecord(
          syncStatus: SongSyncStatus.conflict,
          errorCode: SongMutationSyncErrorCode.connectivityFailure,
        );

        expect(
          canShowScopedDeletedTombstone(
            catalogState: _emptyCatalogState,
            mutationRecord: record,
          ),
          isFalse,
        );
      },
    );
  });

  testWidgets('SongReaderLoadingView shows the loading message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SongReaderLoadingView())),
    );

    expect(find.text(AppStrings.songReaderLoadingMessage), findsOneWidget);
  });

  testWidgets('SongReaderScopedUnavailableView shows the scoped message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SongReaderScopedUnavailableView()),
      ),
    );

    expect(
      find.text(AppStrings.scopedReaderContextUnavailableMessage),
      findsOneWidget,
    );
  });

  testWidgets('SongReaderAccessDeniedView shows the access-denied message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SongReaderAccessDeniedView())),
    );

    expect(find.text(AppStrings.songReaderAccessDeniedMessage), findsOneWidget);
  });

  testWidgets('SongReaderNotFoundView shows the unavailable message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SongReaderNotFoundView())),
    );

    expect(find.text(AppStrings.songReaderUnavailableMessage), findsOneWidget);
  });

  testWidgets('SongReaderLoadFailureView shows the message and retries', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongReaderLoadFailureView(onRetry: () => retries += 1),
        ),
      ),
    );

    expect(find.text(AppStrings.songReaderLoadFailureMessage), findsOneWidget);

    await tester.tap(find.text(AppStrings.retryAction));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('SongReaderDeletedTombstoneView shows title and message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SongReaderDeletedTombstoneView(
            title: 'Zulu Song',
            message: 'This song was deleted.',
          ),
        ),
      ),
    );

    expect(find.text('Zulu Song'), findsOneWidget);
    expect(find.text(AppStrings.songReaderDeletedTitle), findsOneWidget);
    expect(find.text('This song was deleted.'), findsOneWidget);
  });

  testWidgets(
    'SongReaderScopedContextFailureScaffold shows back action and scoped message',
    (tester) async {
      var backTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SongReaderScopedContextFailureScaffold(
            onBack: () => backTaps += 1,
          ),
        ),
      );

      expect(find.text(AppStrings.songReaderTitle), findsOneWidget);
      expect(
        find.text(AppStrings.scopedReaderContextUnavailableMessage),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(AppStrings.songReaderBackAction));
      await tester.pump();

      expect(backTaps, 1);
    },
  );
}
