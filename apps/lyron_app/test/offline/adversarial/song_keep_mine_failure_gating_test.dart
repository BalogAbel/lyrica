import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';

/// Finding B's remaining ungated write, raised in the fourth PR #64 review
/// round. `SongMutationSyncController.keepMine` gates its SUCCESS write on
/// the pre-send snapshot's `localRevision` but wrote its failure status with
/// no `expectedRevision` at all -- the same asymmetry Finding B closed
/// everywhere else, and undocumented here.
///
/// Scope, stated honestly: no *application* path can reach the burial today.
/// `keepMine`'s only caller is the conflict row's "keep mine" button, so the
/// row is `conflict`, and `SongLibraryService.updateSong`/`deleteSong` both
/// refuse a `conflict` row outright (`SongConflictResolutionRequiredException`)
/// -- so the user cannot produce the concurrent local edit that would be
/// buried. This is therefore a store-level contract test, not a reproduction
/// of a user-reachable defect: it pins that the write is revision-gated so
/// the invariant does not depend on a guard two layers up in a different
/// file, which is exactly the kind of cross-file reasoning that goes stale.
/// `keepMine`'s own doc already records that it deliberately sits outside the
/// context lease and can interleave with other song writes.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('keepMine failure-status write is revision-gated', () {
    test('a local write landing during overwriteSong\'s round trip is not '
        'buried under this attempt\'s conflict status', () async {
      final songDatabase = SongCatalogDatabase.inMemory();
      addTearDown(songDatabase.close);
      final songStore = DriftSongCatalogStore(songDatabase);
      final planningDatabase = PlanningLocalDatabase.inMemory();
      addTearDown(planningDatabase.close);
      final mutationStore = DriftSongMutationStore(
        songCatalogStore: songStore,
        planningLocalStore: DriftPlanningLocalStore(planningDatabase),
      );

      const context = SongMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await mutationStore.upsertSong(
        userId: 'user-1',
        record: const SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Alpha}',
          version: 2,
          baseVersion: 1,
          syncStatus: SongSyncStatus.conflict,
          errorCode: SongMutationSyncErrorCode.conflict,
          errorMessage: 'base_version_conflict',
          conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
        ),
      );

      final remote = _GatedFailingKeepMineRemote(
        const SongMutationSyncException(
          SongMutationSyncErrorCode.connectivityFailure,
        ),
      );
      final controller = SongMutationSyncController(
        store: mutationStore,
        remoteRepository: remote,
      );

      final keepMineFuture = controller.keepMine(context, songId: 'song-1');
      unawaited(keepMineFuture.catchError((Object _) {}));

      await remote.entered.future;

      // A local write lands on the same song while this overwrite's remote
      // call is in flight, bumping the row past the revision keepMine
      // captured before sending. Written through the store directly, since
      // the service layer refuses to edit a `conflict` row -- the point here
      // is the store-level contract, not the service guard.
      await mutationStore.upsertSong(
        userId: 'user-1',
        record: const SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Newer, never sent}',
          version: 2,
          baseVersion: 1,
          syncStatus: SongSyncStatus.pendingUpdate,
        ),
      );

      remote.gate.complete();

      await expectLater(
        keepMineFuture,
        throwsA(isA<SongMutationSyncException>()),
        reason:
            'keepMine still rethrows so the user sees the failure -- that '
            'part is unchanged',
      );

      final after = await songStore.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(after, isNotNull);
      expect(
        after!.syncStatus,
        SongSyncStatus.pendingUpdate.value,
        reason:
            'an ungated failure write stamps `conflict` -- excluded from '
            'readPendingSongs -- straight onto the newer content, so it is '
            'never resent: buried, not deleted, the exact shape Finding B '
            'closed on every other failure write',
      );
      expect(after.source, '{title: Newer, never sent}');
    });

    test('the unchanged case still records the conflict exactly as before '
        'when nothing writes to the song during the round trip', () async {
      final songDatabase = SongCatalogDatabase.inMemory();
      addTearDown(songDatabase.close);
      final songStore = DriftSongCatalogStore(songDatabase);
      final planningDatabase = PlanningLocalDatabase.inMemory();
      addTearDown(planningDatabase.close);
      final mutationStore = DriftSongMutationStore(
        songCatalogStore: songStore,
        planningLocalStore: DriftPlanningLocalStore(planningDatabase),
      );

      const context = SongMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await mutationStore.upsertSong(
        userId: 'user-1',
        record: const SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Alpha}',
          version: 2,
          baseVersion: 1,
          syncStatus: SongSyncStatus.conflict,
          errorCode: SongMutationSyncErrorCode.conflict,
          errorMessage: 'base_version_conflict',
          conflictSourceSyncStatus: SongSyncStatus.pendingUpdate,
        ),
      );

      final remote = _GatedFailingKeepMineRemote(
        const SongMutationSyncException(
          SongMutationSyncErrorCode.authorizationDenied,
        ),
      );
      remote.gate.complete();
      final controller = SongMutationSyncController(
        store: mutationStore,
        remoteRepository: remote,
      );

      await expectLater(
        controller.keepMine(context, songId: 'song-1'),
        throwsA(isA<SongMutationSyncException>()),
      );

      final after = await songStore.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );
      expect(after!.syncStatus, SongSyncStatus.conflict.value);
      expect(after.source, '{title: Alpha}');
    });
  });
}

class _GatedFailingKeepMineRemote implements SongMutationRemoteRepository {
  _GatedFailingKeepMineRemote(this.failure);

  final SongMutationSyncException failure;
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    if (!entered.isCompleted) {
      entered.complete();
    }
    await gate.future;
    throw failure;
  }

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();
}
