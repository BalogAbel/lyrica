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

/// Adversarial coverage for the song/catalog half of
/// `docs/specs/2026-08-05-sync-snapshot-identity.md` (the PR #64 re-review
/// finding, ADR-030's planning-side twin): `SongMutationSyncController._runSync`
/// reads a snapshot of a pending song, sends it, and awaits the backend. A
/// local edit made to the SAME song during that remote round trip must
/// survive -- not be silently destroyed by the post-sync `reconcileSyncedSong`
/// write, which today deletes the mutation row unconditionally, keyed only by
/// song identity.
///
/// This suite drives the real `DriftSongCatalogStore`/`DriftSongMutationStore`
/// (not a hand-rolled fake) because the fix lives inside the storage
/// boundary: a fake store could easily "pass" this test by encoding the
/// desired behaviour directly, without proving the underlying conditional
/// write is correct.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('Song sync snapshot identity (D2/D3)', () {
    test('a local edit made during the remote round trip survives -- the '
        'song mutation stays pending with the newer content, and a second '
        'sync sends it', () async {
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
          version: 1,
          baseVersion: null,
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      );

      final remote = _GatedSongRemote();
      final controller = SongMutationSyncController(
        store: mutationStore,
        remoteRepository: remote,
      );

      final syncFuture = controller.syncPendingSongs(context);

      // Wait until the remote call has actually been reached (the
      // controller sent its snapshot) before racing a local edit against it.
      await remote.entered.future;

      // The user keeps typing while the sync is in flight -- a further
      // local edit lands on the exact song the in-flight remote call is
      // about to conclude.
      await mutationStore.upsertSong(
        userId: 'user-1',
        record: const SongMutationRecord(
          id: 'song-1',
          organizationId: 'org-1',
          slug: 'alpha',
          title: 'Alpha',
          chordproSource: '{title: Edited while syncing}',
          version: 1,
          baseVersion: null,
          syncStatus: SongSyncStatus.pendingCreate,
        ),
      );

      remote.gate.complete();
      await syncFuture;

      final afterFirstSync = await songStore.readSongMutationBySongId(
        userId: 'user-1',
        organizationId: 'org-1',
        songId: 'song-1',
      );

      expect(
        afterFirstSync,
        isNotNull,
        reason: 'the newer edit must not be silently discarded',
      );
      expect(
        afterFirstSync!.syncStatus,
        SongSyncStatus.pendingCreate.value,
        reason:
            'a stale post-sync write must leave the row pending (D3), '
            'not synced away',
      );
      expect(
        afterFirstSync.source,
        '{title: Edited while syncing}',
        reason: 'the row must carry the newer content, not the synced one',
      );

      // The next sync picks up the newer content and sends it.
      await controller.syncPendingSongs(context);

      expect(
        remote.syncedSources,
        hasLength(2),
        reason: 'the second sync must resend the never-accepted content',
      );
      expect(remote.syncedSources.last, '{title: Edited while syncing}');
    });

    test(
      'the unchanged case still completes exactly as before -- reconciled '
      'and cleared -- when nothing edits the song during the sync',
      () async {
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
            chordproSource: '{title: Untouched}',
            version: 1,
            baseVersion: null,
            syncStatus: SongSyncStatus.pendingCreate,
          ),
        );

        final remote = _GatedSongRemote();
        final controller = SongMutationSyncController(
          store: mutationStore,
          remoteRepository: remote,
        );

        // No concurrent edit this time -- release the gate immediately.
        remote.gate.complete();
        await controller.syncPendingSongs(context);

        final afterSync = await songStore.readSongMutationBySongId(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(
          afterSync,
          isNull,
          reason:
              'the ordinary path must still reconcile-then-clear exactly as '
              'before the D2 condition was added',
        );
        expect(remote.syncedSources, ['{title: Untouched}']);

        final summary = await songStore.readActiveSummaryById(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(summary, isNotNull);
      },
    );
  });
}

class _GatedSongRemote implements SongMutationRemoteRepository {
  final Completer<void> gate = Completer<void>();
  final Completer<void> entered = Completer<void>();
  final List<String?> syncedSources = [];

  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) async {
    syncedSources.add(record.chordproSource);
    if (!entered.isCompleted) {
      entered.complete();
      await gate.future;
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
