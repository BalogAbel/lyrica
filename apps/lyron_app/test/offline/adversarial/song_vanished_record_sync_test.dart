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

/// Adversarial coverage for the song/catalog half of D4 of
/// `docs/specs/2026-08-06-in-flight-create-cancellation.md`.
///
/// `SongMutationSyncController._runSync` has the identical shape to
/// planning's `_run`: it snapshots every pending song up front, then sends
/// them one at a time. `DriftSongMutationStore.saveSyncAttemptResult` is the
/// store-level write the controller's failure branch concludes a remote
/// attempt with -- the song-side equivalent of planning's
/// `saveSyncAttemptResult`/`retryMutation`. If the song's row physically
/// vanished mid-flight (e.g. the pendingCreate collapse branch in
/// `SongLibraryService.deleteSong`) that write must not throw and take the
/// rest of the batch down with it.
///
/// This suite drives the real `DriftSongMutationStore`/`DriftSongCatalogStore`
/// (not a hand-rolled fake) for the same reason the planning twin does: the
/// fix lives inside the storage boundary.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('Song sync survives a vanished record (D4)', () {
    test('a song removed mid-flight is skipped, and the songs queued behind '
        'it still reach the backend', () async {
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

      for (final id in ['song-1', 'song-2', 'song-3']) {
        await mutationStore.upsertSong(
          userId: 'user-1',
          record: SongMutationRecord(
            id: id,
            organizationId: 'org-1',
            slug: id,
            title: id,
            chordproSource: '{title: $id}',
            version: 1,
            baseVersion: null,
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        );
      }

      final remote = _GatedRejectingSongRemote();
      final controller = SongMutationSyncController(
        store: mutationStore,
        remoteRepository: remote,
      );

      final syncFuture = controller.syncPendingSongs(context);

      // Wait until song-1's remote call is actually in flight before
      // racing a concurrent delete against it.
      await remote.entered.future;

      // The user deletes song-1 -- still a pendingCreate -- while its
      // create is in flight. Mirrors
      // SongLibraryService.deleteSong's pendingCreate branch, which calls
      // exactly this store method to collapse the row.
      await mutationStore.deleteSong(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );

      // Release the gate: song-1's remote call now comes back with a
      // rejection, and the concluding saveSyncAttemptResult write has no
      // row left to write to.
      remote.gate.complete();

      // Pre-fix: DriftSongMutationStore.saveSyncAttemptResult throws
      // StateError('Song mutation record not found: song-1'), which
      // escapes _runSync uncaught and aborts the whole sync pass before
      // song-2 and song-3 are ever attempted.
      await syncFuture;

      expect(
        remote.syncedIds,
        containsAll(<String>['song-1', 'song-2', 'song-3']),
        reason:
            'song-2 and song-3, queued behind song-1, must not be '
            'abandoned just because song-1 could not be concluded',
      );

      final song2After = await songStore.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-2',
      );
      final song3After = await songStore.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-3',
      );
      expect(
        song2After,
        isNull,
        reason: 'song-2 synced and reconciled normally, undisturbed',
      );
      expect(
        song3After,
        isNull,
        reason: 'song-3 synced and reconciled normally, undisturbed',
      );
    });
  });
}

class _GatedRejectingSongRemote implements SongMutationRemoteRepository {
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();
  final List<String> syncedIds = [];

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    syncedIds.add(record.id);
    if (record.id == 'song-1') {
      if (!entered.isCompleted) {
        entered.complete();
        await gate.future;
      }
      throw const SongMutationSyncException(
        SongMutationSyncErrorCode.authorizationDenied,
      );
    }
    return record.copyWith(syncStatus: SongSyncStatus.synced);
  }

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) {
    throw UnimplementedError();
  }
}
